import pandas as pd
import numpy as np
from typing import Dict, Any, Tuple
from collections import deque

from ml.features.feature_utils import (
    RepetitionSegmenter, 
    RepBuffer, 
    extract_repetition_features, 
    validate_repetition_quality
)
from ml.features.pose_utils import ArmLandmarks, Point2D, arm_visibility_ok, compute_frame_angles

class PredictionSmoother:
    """Small repetition-level majority vote to reduce flicker across reps."""
    def __init__(self, window_size: int = 3) -> None:
        self.window = deque(maxlen=window_size)

    def update(self, label: str) -> str:
        if label in ["uncertain", "calibrating"]:
            return label
        self.window.append(label)
        if not self.window:
            return label
        labels = list(self.window)
        return max(set(labels), key=labels.count)

class ExerciseEvaluatorService:
    def __init__(self, exercise_type: str, model: Any, label_encoder: Any, feature_columns: list):
        self.exercise_type = exercise_type
        self.model = model
        self.label_encoder = label_encoder
        self.feature_columns = feature_columns

        # Isolated state for THIS specific user session
        self.segmenter = RepetitionSegmenter(exercise_type=exercise_type)
        self.buffer = RepBuffer()
        self.smoother = PredictionSmoother(window_size=3)
        self.rep_count = 0
        
        # HISTORY BUFFER FOR LIVE NORMALIZATION (RCA Fix)
        self.rep_history = [] 

    def _parse_raw_landmarks(self, landmarks_dict: Dict[str, Any]) -> ArmLandmarks:
        return ArmLandmarks(
            shoulder=Point2D(**landmarks_dict["shoulder"]),
            elbow=Point2D(**landmarks_dict["elbow"]),
            wrist=Point2D(**landmarks_dict["wrist"]),
            hip=Point2D(**landmarks_dict["hip"])
        )

    def process_frame(self, frame_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a single frame from the Flutter client.
        frame_data schema: { "timestamp": float, "landmarks": {...}, "visibility": float }
        """
        timestamp = frame_data.get("timestamp", 0.0)
        visibility = frame_data.get("visibility", 1.0)
        raw_landmarks = frame_data.get("landmarks", {})

        if not raw_landmarks:
            return {"status": "no_pose", "state": self.segmenter.state}

        if not arm_visibility_ok(visibility):
            return {"status": "low_visibility", "state": self.segmenter.state}

        try:
            arm_lms = self._parse_raw_landmarks(raw_landmarks)
        except Exception as e:
            return {"status": f"invalid_landmarks: {str(e)}", "state": self.segmenter.state}

        angles = compute_frame_angles(arm_lms)
        features_frame = {**angles, "mean_visibility": visibility}

        self.buffer.append(timestamp, features_frame)
        event = self.segmenter.update(angles["elbow_angle"], timestamp)

        if event == "completed":
            self.rep_count += 1
            features = extract_repetition_features(self.buffer)
            is_valid, msg = validate_repetition_quality(self.buffer, features, self.exercise_type)

            if not is_valid:
                label = "invalid"
                confidence = 1.0
                smoothed_label = label
            else:
                label, confidence = self._predict(features)
                smoothed_label = self.smoother.update(label)

            # Reset state ready for next rep
            self.buffer.clear()
            self.segmenter.reset(keep_down=True)

            return {
                "status": "rep_completed",
                "rep_count": self.rep_count,
                "prediction": label,
                "smoothed_prediction": smoothed_label,
                "confidence": confidence,
                "features": features
            }

        return {"status": "tracking", "state": self.segmenter.state}

    def _predict(self, raw_features: Dict[str, float]) -> Tuple[str, float]:
        """Runs the XGBoost model with Live Normalization & Ratio Features."""
        features = raw_features.copy()
        
        # 1. GENERATE RATIO FEATURES (RCA Fix)
        rep_dur = features.get("rep_duration", 1e-6)
        features["up_phase_ratio"] = features.get("up_phase_duration", 0.0) / (rep_dur + 1e-6)
        features["down_phase_ratio"] = features.get("down_phase_duration", 0.0) / (rep_dur + 1e-6)

        # 2. HYBRID GATEKEEPER (Checks absolute errors before ML)
        try:
            from ml.features.feature_utils import hybrid_gatekeeper
            allowed_to_model, rule_label, rule_feedback = hybrid_gatekeeper(features)
            if not allowed_to_model:
                return rule_label, 1.0
        except ImportError:
            pass 

        # 3. APPEND TO HISTORY FOR LIVE NORMALIZATION
        self.rep_history.append(features)

        # 4. CALIBRATION PHASE (Rep 1)
        if len(self.rep_history) < 2:
            # We don't have enough data to calculate standard deviation yet.
            # UX: We tell the user we are calibrating their body baseline.
            return "calibrating", 1.0

        # 5. LIVE Z-SCORE NORMALIZATION (RCA Fix)
        # Translates current raw features into Z-scores based on user's history
        normalized_features = {}
        df_history = pd.DataFrame(self.rep_history)
        
        for col in self.feature_columns:
            if col in df_history.columns:
                mean_val = df_history[col].mean()
                std_val = df_history[col].std()
                if pd.isna(std_val) or std_val == 0.0:
                    normalized_features[col] = 0.0
                else:
                    normalized_features[col] = float((features[col] - mean_val) / std_val)
            else:
                normalized_features[col] = 0.0

        # 6. INFERENCE WITH XGBOOST
        X_live = pd.DataFrame([normalized_features])

        if hasattr(self.model, "predict_proba"):
            proba = self.model.predict_proba(X_live)[0]
            pred_idx = int(np.argmax(proba))
            confidence = float(np.max(proba))
        else:
            pred_idx = int(self.model.predict(X_live)[0])
            confidence = 1.0

        if self.label_encoder is not None:
            label = str(self.label_encoder.inverse_transform([pred_idx])[0])
        else:
            label = "correct" if pred_idx == 0 else "incorrect"

        return label, confidence