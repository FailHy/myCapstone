"""Real-time evaluator with hybrid rule-based + XGBoost inference (With Live Normalization)."""

from __future__ import annotations

import argparse
import csv
import json
import pickle
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

try:
    import pygame
except Exception:  # pragma: no cover
    pygame = None

from tools.config import (
    CONFIDENCE_THRESHOLD,
    ELBOW_START_ANGLE,
    FEATURE_COLUMNS_PATH,
    LABEL_ENCODER_PATH,
    LIVE_PREDICTION_LOG,
    MODEL_PKL_PATH,
    REJECTED_SAMPLE_LOG,
    VISIBILITY_THRESHOLD,
)
from ml.features.feature_utils import (
    RepBuffer,
    RepetitionSegmenter,
    extract_repetition_features,
    feedback_from_prediction,
    hybrid_gatekeeper,
    validate_repetition_quality,
)
from ml.features.pose_utils import arm_visibility_ok, compute_frame_angles, get_arm_landmarks

def init_audio() -> None:
    if pygame is None: return
    try: pygame.mixer.init()
    except Exception: pass

def play_beep(is_correct: bool) -> None:
    if pygame is None: return
    try:
        pygame.mixer.music.stop()
        sample_rate = 44100
        duration = 0.25
        freq = 880.0 if is_correct else 330.0
        t = np.linspace(0, duration, int(sample_rate * duration), False)
        wave = np.sin(2 * np.pi * freq * t)
        audio = np.zeros((len(wave), 2), dtype=np.int16)
        audio[:, 0] = audio[:, 1] = (wave * 32767).astype(np.int16)
        sound = pygame.sndarray.make_sound(audio)
        sound.set_volume(0.5)
        sound.play()
    except Exception: pass

def run_live(exercise: str, camera_id: int) -> None:
    print(f"Loading {exercise.upper()} ML Model...")
    try:
        with open(MODEL_PKL_PATH, "rb") as f: model = pickle.load(f)
        with open(LABEL_ENCODER_PATH, "rb") as f: label_encoder = pickle.load(f)
        with open(FEATURE_COLUMNS_PATH, "r") as f: feature_cols = json.load(f)
    except FileNotFoundError as e:
        print(f"Error: Model artifacts missing! {e}")
        return

    init_audio()
    mp_pose = mp.solutions.pose
    mp_drawing = mp.solutions.drawing_utils
    draw_spec_landmark = mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
    draw_spec_connection = mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2)

    cap = cv2.VideoCapture(camera_id)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    segmenter = RepetitionSegmenter(exercise_type=exercise)
    buffer = RepBuffer()
    
    # State Trackers
    rep_history = []  # For Live Normalization
    counter = 0
    last_label = "N/A"
    last_confidence = 0.0
    last_feedback = ""
    last_source = ""
    active_arm = "unknown"

    # UI Helpers
    def put_text(img, text, y, color=(255, 255, 255), scale=0.7):
        cv2.putText(img, text, (15, y), cv2.FONT_HERSHEY_SIMPLEX, scale, color, 2, cv2.LINE_AA)

    print("\n--- READY! Tampilkan seluruh tubuh (bahu hingga pinggul) di kamera. ---")
    
    with mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
        prev_time = time.time()
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret: break
            
            frame = cv2.flip(frame, 1)
            curr_time = time.time()
            fps = 1.0 / (curr_time - prev_time + 1e-6)
            prev_time = curr_time
            
            height, width, _ = frame.shape
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb_frame)

            status = ""
            left_angle = right_angle = 0.0

            if results.pose_landmarks:
                try:
                    vis_left = results.pose_landmarks.landmark[mp_pose.PoseLandmark.LEFT_ELBOW].visibility
                    vis_right = results.pose_landmarks.landmark[mp_pose.PoseLandmark.RIGHT_ELBOW].visibility
                    
                    if active_arm == "unknown":
                        if vis_left > vis_right and vis_left > VISIBILITY_THRESHOLD: active_arm = "left"
                        elif vis_right > VISIBILITY_THRESHOLD: active_arm = "right"

                    if active_arm != "unknown":
                        arm_lms = get_arm_landmarks(results.pose_landmarks, active_arm)
                        vis = arm_lms.elbow.visibility
                        if not arm_visibility_ok(vis):
                            status = "Visibility Low - Move into frame"
                        else:
                            angles = compute_frame_angles(arm_lms)
                            left_angle = right_angle = angles["elbow_angle"]
                            features_frame = {**angles, "mean_visibility": vis}
                            
                            buffer.append(curr_time, features_frame)
                            event = segmenter.update(angles["elbow_angle"], curr_time)

                            if event == "completed":
                                counter += 1
                                raw_features = extract_repetition_features(buffer)
                                features = raw_features.copy()
                                
                                # 1. RATIO FEATURES
                                rep_dur = features.get("rep_duration", 1e-6)
                                features["up_phase_ratio"] = features.get("up_phase_duration", 0.0) / (rep_dur + 1e-6)
                                features["down_phase_ratio"] = features.get("down_phase_duration", 0.0) / (rep_dur + 1e-6)

                                # 2. HYBRID GATEKEEPER
                                allowed, rule_lbl, rule_fb = hybrid_gatekeeper(features)
                                
                                if not allowed:
                                    last_label, last_confidence, last_feedback, last_source = rule_lbl, 1.0, rule_fb, "Gatekeeper"
                                    threading.Thread(target=play_beep, args=(last_label=="correct",), daemon=True).start()
                                else:
                                    # 3. LIVE NORMALIZATION
                                    rep_history.append(features)
                                    
                                    if len(rep_history) < 2:
                                        # CALIBRATION REPS
                                        last_label = "calibrating"
                                        last_confidence = 1.0
                                        last_feedback = "Kalibrasi AI: Lakukan 1 repetisi lagi..."
                                        last_source = "Calibration"
                                    else:
                                        # Z-SCORE
                                        norm_feat = {}
                                        df_h = pd.DataFrame(rep_history)
                                        for c in feature_cols:
                                            if c in df_h.columns:
                                                m, s = df_h[c].mean(), df_h[c].std()
                                                norm_feat[c] = 0.0 if (pd.isna(s) or s==0) else float((features[c]-m)/s)
                                            else:
                                                norm_feat[c] = 0.0
                                                
                                        # 4. XGBOOST INFERENCE
                                        X_live = pd.DataFrame([norm_feat])
                                        if hasattr(model, "predict_proba"):
                                            proba = model.predict_proba(X_live)[0]
                                            pred_idx = int(np.argmax(proba))
                                            last_confidence = float(np.max(proba))
                                        else:
                                            pred_idx = int(model.predict(X_live)[0])
                                            last_confidence = 1.0
                                            
                                        last_label = str(label_encoder.inverse_transform([pred_idx])[0])
                                        last_source = "XGBoost (AI)"
                                        
                                        # Limit feedback trigger threshold
                                        if last_confidence >= CONFIDENCE_THRESHOLD:
                                            last_feedback = feedback_from_prediction(last_label, last_confidence, features)
                                        else:
                                            last_feedback = f"Uncertain ({last_confidence:.2f}). Fokus pada form."
                                            
                                        threading.Thread(target=play_beep, args=(last_label=="correct",), daemon=True).start()

                                buffer.clear()
                                segmenter.reset(keep_down=True)
                except Exception as exc:
                    status = f"Error: {exc}"

                mp_drawing.draw_landmarks(frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS, draw_spec_landmark, draw_spec_connection)
            else:
                status = "No pose detected"

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"): break

            # UI OVERLAY
            cv2.rectangle(frame, (0, 0), (width, 130), (0, 0, 0), -1)
            
            if last_label == "correct": label_color = (0, 255, 0)
            elif last_label == "calibrating": label_color = (255, 255, 0) # Cyan for calibrating
            elif last_label == "incorrect": label_color = (0, 0, 255)
            else: label_color = (0, 165, 255) # Orange for errors

            put_text(frame, f"FPS: {fps:.1f} | Reps: {counter} | Arm: {active_arm} | State: {segmenter.state}", 25)
            put_text(frame, f"Pred: {last_label.upper()} | Conf: {last_confidence:.2f} | Source: {last_source}", 55, label_color, 0.65)
            put_text(frame, f"Feedback: {last_feedback or status}", 85, label_color, 0.55)
            put_text(frame, "Press Q to exit", 115, (255, 255, 255), 0.50)

            cv2.imshow(f"LIVE INFERENCE: {exercise.upper()}", frame)

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--exercise", type=str, default="biceps")
    parser.add_argument("--camera", type=int, default=0)
    args = parser.parse_args()
    run_live(args.exercise, args.camera)