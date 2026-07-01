"""
live_evaluator.py
==================
Real-time evaluator dengan hybrid rule-based + XGBoost inference.

ARSITEKTUR NORMALISASI:
  raw features
    → ratio features (up_phase_ratio, down_phase_ratio)
    → hybrid_gatekeeper() [rule-based safety net]
    → scaler.transform()  [StandardScaler identik dengan saat training]
    → model.predict_proba()
    → label_encoder.inverse_transform()
    → feedback_from_prediction()

Scaler (scaler_{exercise}.pkl) di-fit saat training pada 100% data training
dan disimpan bersama model. Hal ini menjamin distribusi fitur saat serving
sama persis dengan distribusi fitur saat training (train/serve skew = 0).
"""

from __future__ import annotations

import argparse
import csv
import json
import pickle
import threading
import time
import sys
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
import xgboost as xgb  # Penting: memastikan pickle bisa memuat model XGBoost

try:
    import pygame
except Exception:  # pragma: no cover
    pygame = None

from tools.config import (
    MODEL_DIR,
    LABEL_ENCODER_PATH,
    VISIBILITY_THRESHOLD,
)

CONFIDENCE_THRESHOLD = 0.75

from ml.features.feature_utils import (
    RepBuffer,
    RepetitionSegmenter,
    extract_repetition_features,
    feedback_from_prediction,
    hybrid_gatekeeper,
    validate_repetition_quality,
)

from ml.features.pose_utils import arm_visibility_ok, compute_frame_angles, ArmLandmarks, Point2D

# FIX MEDIUM: DEBUG_MODE dibaca dari environment variable, bukan hardcoded True.
# Set BITRI_DEBUG=1 di terminal untuk mengaktifkan debug output.
# Contoh: BITRI_DEBUG=1 python -m ml.inference.live_evaluator --exercise biceps
import os as _os
DEBUG_MODE: bool = _os.getenv("BITRI_DEBUG", "0").strip() in ("1", "true", "yes")


def debug_print(msg: str) -> None:
    if DEBUG_MODE:
        print(f"[DEBUG] {msg}")


def init_audio() -> None:
    if pygame is None:
        return
    try:
        pygame.mixer.init()
    except Exception:
        pass


def play_beep(is_correct: bool) -> None:
    if pygame is None:
        return
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
    except Exception:
        pass


def run_live(exercise: str, camera_id: int) -> None:
    print(f"\nLoading {exercise.upper()} ML Model...")

    model_pkl = MODEL_DIR / f"{exercise}_xgboost_model.pkl"
    features_json = MODEL_DIR / f"feature_columns_{exercise}.json"
    scaler_pkl = MODEL_DIR / f"scaler_{exercise}.pkl"

    try:
        with open(model_pkl, "rb") as f:
            model = pickle.load(f)
        with open(LABEL_ENCODER_PATH, "rb") as f:
            label_encoder = pickle.load(f)
        with open(features_json, "r") as f:
            feature_cols = json.load(f)
        print(f"✅ Model {exercise.upper()} berhasil dimuat!")
    except FileNotFoundError as e:
        print(f"❌ Error: Artefak model untuk {exercise.upper()} tidak ditemukan!")
        print(f"   Pastikan Anda sudah menjalankan: python -m ml.training.train_model")
        print(f"   Detail: {e}")
        return

    # Muat scaler — WAJIB ada agar distribusi fitur serving == training.
    # Scaler dihasilkan otomatis oleh train_model.py dan disimpan bersama model.
    scaler = None
    if scaler_pkl.exists():
        try:
            with open(scaler_pkl, "rb") as f:
                scaler_data = pickle.load(f)
            scaler = scaler_data["scaler"]
            print(f"✅ Scaler {exercise.upper()} berhasil dimuat!")
        except Exception as e:
            print(f"⚠️  Scaler gagal dimuat ({e}). Prediksi akan kurang akurat.")
    else:
        print(
            f"⚠️  scaler_{exercise}.pkl tidak ditemukan. "
            f"Jalankan ulang training untuk membuat scaler baru."
        )

    debug_print(f"Feature columns dimuat dari model: {feature_cols}")

    init_audio()
    mp_pose = mp.solutions.pose
    mp_drawing = mp.solutions.drawing_utils
    draw_spec_landmark = mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
    draw_spec_connection = mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2)

    cap = cv2.VideoCapture(camera_id)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    segmenter = RepetitionSegmenter(exercise_type=exercise)
    buffer = RepBuffer()

    # State Trackers
    counter = 0
    last_label = "N/A"
    last_confidence = 0.0
    last_feedback = ""
    last_source = ""
    active_arm = "unknown"

    # Auto-Logger 20 Output
    log_file_path = Path("logs/live_prediction_log.csv")
    log_file_path.parent.mkdir(parents=True, exist_ok=True)
    log_count = 0
    max_logs = 20

    with open(log_file_path, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Timestamp', 'Latihan', 'Tangan_Aktif', 'Repetisi_Ke', 'Prediksi', 'Confidence', 'ROM_Elbow', 'Feedback'])

    last_state = segmenter.state
    last_arm_debug = ""

    def put_text(img, text, y, color=(255, 255, 255), scale=0.7):
        cv2.putText(img, text, (15, y), cv2.FONT_HERSHEY_SIMPLEX, scale, color, 2, cv2.LINE_AA)

    print("\n" + "=" * 50)
    print(f" 🏋️  MULAI LATIHAN: {exercise.upper()}")
    print("=" * 50)
    print("--- READY! Tampilkan seluruh tubuh (bahu hingga pinggul) di kamera. ---")
    print("--- Tekan 'Q' pada keyboard untuk keluar ---")

    with mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
        prev_time = time.time()
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

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

                    if active_arm == "left" and vis_left < VISIBILITY_THRESHOLD:
                        active_arm = "unknown"
                        debug_print("Lengan Kiri hilang dari layar. Mencari ulang...")
                    elif active_arm == "right" and vis_right < VISIBILITY_THRESHOLD:
                        active_arm = "unknown"
                        debug_print("Lengan Kanan hilang dari layar. Mencari ulang...")

                    if active_arm == "unknown":
                        if vis_left > vis_right and vis_left > VISIBILITY_THRESHOLD:
                            active_arm = "left"
                            debug_print(f"Lengan aktif pindah ke: {active_arm} (Vis: {vis_left:.2f})")
                        elif vis_right > VISIBILITY_THRESHOLD:
                            active_arm = "right"
                            debug_print(f"Lengan aktif pindah ke: {active_arm} (Vis: {vis_right:.2f})")

                    if active_arm != "unknown":
                        lms = results.pose_landmarks.landmark

                        def safe_point2d(lm):
                            try:
                                return Point2D(x=lm.x, y=lm.y, z=lm.z, visibility=lm.visibility)
                            except TypeError:
                                try:
                                    return Point2D(x=lm.x, y=lm.y, visibility=lm.visibility)
                                except TypeError:
                                    return Point2D(x=lm.x, y=lm.y)

                        if active_arm == "left":
                            arm_lms = ArmLandmarks(
                                shoulder=safe_point2d(lms[mp_pose.PoseLandmark.LEFT_SHOULDER]),
                                elbow=safe_point2d(lms[mp_pose.PoseLandmark.LEFT_ELBOW]),
                                wrist=safe_point2d(lms[mp_pose.PoseLandmark.LEFT_WRIST]),
                                hip=safe_point2d(lms[mp_pose.PoseLandmark.LEFT_HIP]),
                            )
                            vis = lms[mp_pose.PoseLandmark.LEFT_ELBOW].visibility
                        else:
                            arm_lms = ArmLandmarks(
                                shoulder=safe_point2d(lms[mp_pose.PoseLandmark.RIGHT_SHOULDER]),
                                elbow=safe_point2d(lms[mp_pose.PoseLandmark.RIGHT_ELBOW]),
                                wrist=safe_point2d(lms[mp_pose.PoseLandmark.RIGHT_WRIST]),
                                hip=safe_point2d(lms[mp_pose.PoseLandmark.RIGHT_HIP]),
                            )
                            vis = lms[mp_pose.PoseLandmark.RIGHT_ELBOW].visibility

                        if last_arm_debug != active_arm:
                            debug_print(f"Tracking lengan: {active_arm} | Visibility: {vis:.2f}")
                            last_arm_debug = active_arm

                        if not arm_visibility_ok(arm_lms):
                            status = "Visibility Low - Move into frame"
                        else:
                            angles = compute_frame_angles(arm_lms)
                            left_angle = right_angle = angles["elbow_angle"]
                            features_frame = {**angles, "mean_visibility": vis}

                            buffer.append(curr_time, features_frame)
                            event = segmenter.update(angles["elbow_angle"], curr_time)

                            if segmenter.state != last_state:
                                debug_print(f"State Segmenter Berubah: {last_state} -> {segmenter.state} | Sudut: {angles['elbow_angle']:.1f}")
                                last_state = segmenter.state

                            if event == "completed":
                                debug_print(f">>> REPETISI SELESAI <<< | Sudut Akhir: {angles['elbow_angle']:.1f}")
                                counter += 1
                                raw_features = extract_repetition_features(buffer)
                                features = raw_features.copy()

                                debug_print(f"Fitur Diekstrak | ROM: {features.get('rom_elbow', 0):.1f}, Durasi: {features.get('rep_duration', 0):.2f}s")

                                # 1. RATIO FEATURES (dipertahankan -- lihat catatan verifikasi di atas)
                                rep_dur = features.get("rep_duration", 1e-6)
                                features["up_phase_ratio"] = features.get("up_phase_duration", 0.0) / (rep_dur + 1e-6)
                                features["down_phase_ratio"] = features.get("down_phase_duration", 0.0) / (rep_dur + 1e-6)

                                # 2. HYBRID GATEKEEPER
                                allowed, rule_lbl, rule_fb = hybrid_gatekeeper(features)

                                if not allowed:
                                    debug_print(f"Gatekeeper Aktif! | Label: {rule_lbl} | Alasan: {rule_fb}")
                                    last_label, last_confidence, last_feedback, last_source = rule_lbl, 1.0, rule_fb, "Gatekeeper"
                                    # Audio beep: fire-and-forget via daemon thread.
                                    # Threading digunakan karena pygame.mixer tidak async-compatible.
                                    # Daemon=True agar thread tidak menahan proses saat exit.
                                    _beep_thread = threading.Thread(
                                        target=play_beep,
                                        args=(last_label == "correct",),
                                        daemon=True,
                                        name="audio-beep",
                                    )
                                    _beep_thread.start()
                                else:
                                    # 3. INFERENSI DENGAN SCALER + XGBOOST
                                    debug_print("Menjalankan inferensi XGBoost dengan fitur ter-scaled.")
                                    X_live = pd.DataFrame(
                                        [{c: float(features.get(c, 0.0)) for c in feature_cols}]
                                    )

                                    # Terapkan scaler yang IDENTIK dengan saat training.
                                    # Scaler di-fit pada 100% training data (train_model.py).
                                    if scaler is not None:
                                        try:
                                            X_live = pd.DataFrame(
                                                scaler.transform(X_live),
                                                columns=feature_cols,
                                            )
                                        except Exception as scale_err:
                                            debug_print(f"Scaler transform error: {scale_err}")

                                    last_source = "XGBoost"

                                    if hasattr(model, "predict_proba"):
                                        proba = model.predict_proba(X_live)[0]
                                        pred_idx = int(np.argmax(proba))
                                        last_confidence = float(np.max(proba))
                                    else:
                                        pred_idx = int(model.predict(X_live)[0])
                                        last_confidence = 1.0

                                    last_label = str(label_encoder.inverse_transform([pred_idx])[0])
                                    debug_print(f"XGBoost Prediksi: {last_label} (Conf: {last_confidence:.2f})")

                                    if last_confidence >= CONFIDENCE_THRESHOLD:
                                        last_feedback = feedback_from_prediction(last_label, last_confidence, features)
                                    else:
                                        last_feedback = f"Uncertain ({last_confidence:.2f}). Fokus pada form."

                                    _beep_thread = threading.Thread(
                                        target=play_beep,
                                        args=(last_label == "correct",),
                                        daemon=True,
                                        name="audio-beep",
                                    )
                                    _beep_thread.start()

                                # --- SIMPAN KE LOG FILE (20 BARIS) ---
                                if log_count < max_logs:
                                    with open(log_file_path, mode='a', newline='', encoding='utf-8') as f:
                                        writer = csv.writer(f)
                                        writer.writerow([
                                            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                                            exercise.upper(),
                                            active_arm.upper(),
                                            counter,
                                            last_label,
                                            f"{last_confidence:.2f}",
                                            f"{features.get('rom_elbow', 0):.1f}",
                                            last_feedback,
                                        ])
                                    log_count += 1
                                    debug_print(f"✅ Data Repetisi Disimpan ke Log! ({log_count}/{max_logs})")
                                    if log_count == max_logs:
                                        print(f"\n🎉 20 LOG OUTPUT TELAH SELESAI DISIMPAN DI {log_file_path}\n")

                                buffer.clear()
                                # CATATAN: keep_down=False dipertahankan apa adanya dari kode asli.
                                # Belum diverifikasi konsistensinya terhadap evaluator_service.py
                                # (yang memakai keep_down=True) atau collect_data.py (yang memakai
                                # .reset() tanpa argumen). Lihat catatan akhir file.
                                segmenter.reset(keep_down=False)
                                debug_print("--- Buffer & Segmenter di-reset untuk repetisi berikutnya ---")
                except Exception as exc:
                    status = f"Error: {exc}"
                    debug_print(f"Exception Terjadi: {exc}")

                mp_drawing.draw_landmarks(frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS, draw_spec_landmark, draw_spec_connection)
            else:
                status = "No pose detected"

            frame = cv2.flip(frame, 1)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break

            cv2.rectangle(frame, (0, 0), (width, 130), (0, 0, 0), -1)

            if last_label == "correct":
                label_color = (0, 255, 0)
            elif last_label == "incorrect":
                label_color = (0, 0, 255)
            else:
                label_color = (0, 165, 255)  # Orange for errors

            put_text(frame, f"FPS: {fps:.1f} | Reps: {counter} | Arm: {active_arm} | State: {segmenter.state}", 25, scale=0.55)
            put_text(frame, f"Pred: {last_label.upper()} | Conf: {last_confidence:.2f} | Source: {last_source}", 55, label_color, 0.55)
            put_text(frame, f"Feedback: {last_feedback or status}", 85, label_color, 0.45)
            put_text(frame, "Press Q to exit", 115, (255, 255, 255), 0.45)

            cv2.imshow(f"LIVE INFERENCE: {exercise.upper()}", frame)

    cap.release()
    cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exercise", type=str, default=None, help="Jenis latihan (biceps/triceps)")
    parser.add_argument("--camera", type=int, default=0, help="ID Kamera (default: 0)")
    args = parser.parse_args()

    exercise = args.exercise
    if exercise is None:
        print("\n" + "=" * 40)
        print(" 🤖 AI FITNESS EVALUATOR - LIVE TESTING ")
        print("=" * 40)
        print("Pilih jenis latihan yang ingin dievaluasi:")
        print("1. Biceps Curl")
        print("2. Triceps Extension")
        print("0. Keluar")

        while True:
            pilihan = input("\nMasukkan angka pilihan (0-2): ").strip()
            if pilihan == "1":
                exercise = "biceps"
                break
            elif pilihan == "2":
                exercise = "triceps"
                break
            elif pilihan == "0":
                print("Keluar dari program.")
                sys.exit(0)
            else:
                print("Pilihan tidak valid, silakan masukkan 1 atau 2.")

    run_live(exercise, args.camera)


if __name__ == "__main__":
    main()


# ----------------------------------------------------------------------
# CATATAN AKHIR -- HAL YANG SAYA TIDAK BISA VERIFIKASI DARI SINI
# ----------------------------------------------------------------------
# 1. feature_cols dimuat dari feature_columns_{exercise}.json -- saya
#    tambahkan debug_print untuk menampilkan isinya saat model dimuat.
#    WAJIB Anda baca output ini sekali dan bandingkan manual dengan
#    kolom yang benar-benar dipakai saat model.fit() di script training.
#    Kalau 'up_phase_ratio'/'down_phase_ratio' TIDAK ada di file ini,
#    hapus blok perhitungannya -- bukan wajib (karena hasilnya
#    diabaikan otomatis lewat filtering {c: features.get(c,0.0) for c
#    in feature_cols}), tapi lebih bersih untuk audit berikutnya.
#
# 2. segmenter.reset(keep_down=False) di file ini vs
#    segmenter.reset(keep_down=True) di evaluator_service.py vs
#    .reset() tanpa argumen di collect_data.py (training-time
#    collection) -- TIGA pemanggilan berbeda untuk fungsi yang sama.
#    Saya tidak punya source RepetitionSegmenter sehingga tidak bisa
#    memastikan efeknya identik atau tidak. INI PERLU DIVERIFIKASI
#    TERPISAH sebelum dianggap selesai -- kalau ternyata parameter ini
#    mengubah state awal segmenter secara material, itu bisa jadi
#    sumber instabilitas TAMBAHAN di luar bug Z-score yang sudah
#    diperbaiki di file ini.
#
# 3. hybrid_gatekeeper() dan feedback_from_prediction() tidak saya
#    lihat isinya. Kalau gatekeeper memuat threshold absolut (misalnya
#    "rom_elbow < 60 -> not_full_up otomatis"), itu di luar cakupan
#    fix ini dan perlu diaudit terpisah jika rep dengan ROM tinggi
#    masih salah klasifikasi setelah fix Z-score ini diterapkan.
#
# 4. SARAN PENGUJIAN: setelah menjalankan file ini, ulangi gerakan
#    yang sama persis seperti rep 9 dan rep 12 di log sebelumnya
#    (ROM ~134, durasi ~3.6s). Kalau sekarang hasilnya KONSISTEN
#    (sama-sama correct, atau sama-sama label lain) -- itu konfirmasi
#    kuat bahwa Z-score memang akar masalahnya. Kalau MASIH tidak
#    konsisten, masalahnya ada di tempat lain (gatekeeper, segmenter,
#    atau feature_columns mismatch) dan butuh investigasi lanjutan
#    dengan source code feature_utils.py.
# ----------------------------------------------------------------------