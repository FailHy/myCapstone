"""
evaluator_service.py
=====================
ARSITEKTUR NORMALISASI (Post-Fix):

  Training  : raw features → StandardScaler.fit_transform() per fold
               Final model : StandardScaler.fit_transform() pada 100% data
               Scaler disimpan sebagai scaler_{exercise}.pkl

  Serving   : raw features → scaler.transform() (scaler yang SAMA)
               → model.predict_proba()

  Invariant : scaler yang dipakai serving == scaler yang dipakai saat model
               dilatih. Train/serve skew = 0.

Catatan lain yang DIPERTAHANKAN:
  - hybrid_gatekeeper tetap dipanggil sebelum inferensi ML (rule-based safety).
  - PredictionSmoother (majority vote 3 rep) tetap aktif.
  - rep_results dikumpulkan untuk batch INSERT di /session/end.
"""

import pandas as pd
import numpy as np
from typing import Dict, Any, Tuple
from collections import deque

from ml.features.feature_utils import (
    RepetitionSegmenter,
    RepBuffer,
    extract_repetition_features,
    validate_repetition_quality,
)
from ml.features.pose_utils import ArmLandmarks, Point2D, arm_visibility_ok, compute_frame_angles


class PredictionSmoother:
    """Small repetition-level majority vote to reduce flicker across reps."""

    def __init__(self, window_size: int = 3) -> None:
        self.window = deque(maxlen=window_size)

    def update(self, label: str) -> str:
        if label == "uncertain":
            return label
        self.window.append(label)
        if not self.window:
            return label
        labels = list(self.window)
        return max(set(labels), key=labels.count)


class ExerciseEvaluatorService:
    def __init__(self, exercise_type: str, model: Any, label_encoder: Any,
                 feature_columns: list, scaler: Any = None):
        self.exercise_type   = exercise_type
        self.model           = model
        self.label_encoder   = label_encoder
        self.feature_columns = feature_columns
        self.scaler          = scaler  # Population StandardScaler

        if scaler is None:
            import logging
            logging.getLogger(__name__).warning(
                f"[{exercise_type}] Scaler tidak tersedia! Prediksi akan SALAH karena "
                f"model dilatih dengan data yang di-normalize, tapi serving memakai raw features."
            )

        # Isolated state for THIS specific user session
        self.segmenter    = RepetitionSegmenter(exercise_type=exercise_type)
        self.buffer       = RepBuffer()
        self.smoother     = PredictionSmoother(window_size=3)
        self.rep_count    = 0
        self.correct_reps = 0
        self.predictions: list = []
        # STEP 4: kumpulkan data per-rep untuk batch INSERT di /session/end
        # Tidak mengubah ML pipeline — hanya menyalin data yang sudah ada
        self.rep_results: list = []

    def _parse_raw_landmarks(self, landmarks_dict: Dict[str, Any]) -> ArmLandmarks:
        return ArmLandmarks(
            shoulder=Point2D(**landmarks_dict["shoulder"]),
            elbow=Point2D(**landmarks_dict["elbow"]),
            wrist=Point2D(**landmarks_dict["wrist"]),
            hip=Point2D(**landmarks_dict["hip"]),
        )

    def process_frame(self, timestamp: float, landmarks_dict: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a single frame dari Flutter client.

        Args:
            timestamp: Unix epoch float dikirim dari Flutter.
            landmarks_dict: Flat dict berisi key shoulder/elbow/wrist/hip,
                            masing-masing berupa {x, y, visibility}.
                            Ini adalah hasil model_dump() dari LandmarksPayload.

        Returns:
            Dict dengan key 'status' dan info tambahan tergantung event.
        """
        # FIX CRITICAL-01: landmarks_dict sudah flat, langsung parse
        if not landmarks_dict:
            return {"status": "no_pose", "state": self.segmenter.state}

        try:
            arm_lms = self._parse_raw_landmarks(landmarks_dict)
        except Exception as e:
            return {"status": f"invalid_landmarks: {str(e)}", "state": self.segmenter.state}

        # FIX CRITICAL-02: arm_visibility_ok butuh ArmLandmarks, bukan float
        if not arm_visibility_ok(arm_lms):
            return {"status": "low_visibility", "state": self.segmenter.state}

        # Gunakan mean_visibility dari ArmLandmarks yang sudah di-parse
        mean_vis = arm_lms.mean_visibility()
        angles = compute_frame_angles(arm_lms)
        features_frame = {**angles, "mean_visibility": mean_vis}

        # FIX: update segmenter DULU, baru append ke buffer jika state aktif.
        # Ini konsisten dengan collect_data.py L330-333 (training time):
        #   event = segmenter.update(...)
        #   if segmenter.state != "idle":  ← guard
        #       buffer.append(...)
        # Tanpa guard ini, idle frames sebelum rep dimulai masuk ke buffer
        # dan mengkontaminasi: rep_duration, velocity_mean, up_phase_ratio,
        # shoulder_angle_range — yaitu 4 dari 5 feature terpenting model.
        event = self.segmenter.update(angles["elbow_angle"], timestamp)
        if self.segmenter.state != "idle":
            self.buffer.append(timestamp, features_frame)

        if event == "completed":
            self.rep_count += 1
            features = extract_repetition_features(self.buffer)
            is_valid, msg = validate_repetition_quality(self.buffer, features, self.exercise_type)

            if not is_valid:
                label = "invalid"
                confidence = 1.0
                smoothed_label = label
                feedback_text = "Gerakan tidak valid. Pastikan seluruh tubuh terlihat kamera."
            else:
                label, confidence = self._predict(features)
                smoothed_label = self.smoother.update(label)
                try:
                    from ml.features.feature_utils import feedback_from_prediction
                    feedback_text = feedback_from_prediction(smoothed_label, confidence, features)
                except Exception:
                    feedback_text = smoothed_label

            # Track predictions (sudah ada sebelumnya — jangan ubah)
            self.predictions.append(smoothed_label)
            if smoothed_label == "correct":
                self.correct_reps += 1

            # STEP 4: simpan snapshot per-rep untuk batch INSERT nanti
            # Data ini sudah tersedia — tidak ada kalkulasi baru
            self.rep_results.append({
                "rep_number":         self.rep_count,
                "prediction":         label,
                "smoothed_prediction": smoothed_label,
                "confidence":         confidence,
                "feedback_text":      feedback_text,
                "features":           features,
            })

            # Reset state untuk repetisi berikutnya.
            # keep_down=False agar state kembali ke 'idle', konsisten dengan
            # collect_data.py (training) yang memanggil segmenter.reset() tanpa argumen.
            self.buffer.clear()
            self.segmenter.reset(keep_down=False)

            running_accuracy = (
                round(self.correct_reps / self.rep_count * 100, 1)
                if self.rep_count > 0 else 0.0
            )

            return {
                "status":              "rep_completed",
                "rep_count":           self.rep_count,
                "prediction":          label,
                "smoothed_prediction": smoothed_label,
                "confidence":          confidence,
                "feedback":            feedback_text,
                "accuracy":            running_accuracy,
                "features":            features,
            }

        return {"status": "tracking", "state": self.segmenter.state}

    def _predict(self, raw_features: Dict[str, float]) -> Tuple[str, float]:
        """
        Normalisasi fitur dengan population scaler, lalu jalankan XGBoost.
        Scaler WAJIB ada karena model dilatih dengan subject-normalized features.
        """
        features = raw_features.copy()

        # Hitung ratio features (sama dengan training pipeline)
        rep_dur = features.get("rep_duration", 1e-6)
        features["up_phase_ratio"]   = features.get("up_phase_duration", 0.0) / (rep_dur + 1e-6)
        features["down_phase_ratio"] = features.get("down_phase_duration", 0.0) / (rep_dur + 1e-6)

        # Hybrid gatekeeper (rule-based pre-filter sebelum model)
        try:
            from ml.features.feature_utils import hybrid_gatekeeper
            allowed_to_model, rule_label, rule_feedback = hybrid_gatekeeper(features)
            if not allowed_to_model:
                return rule_label, 1.0
        except ImportError:
            pass

        # Build DataFrame dengan kolom sesuai urutan training
        X_live = pd.DataFrame(
            [{col: float(features.get(col, 0.0)) for col in self.feature_columns}]
        )

        # === TERAPKAN SCALER (IDENTIK DENGAN TRAINING) ===
        # Scaler di-fit saat training pada 100% training data dan disimpan
        # sebagai scaler_{exercise}.pkl. Dengan menerapkan transform yang sama
        # di sini, distribusi fitur serving == distribusi fitur training.
        if self.scaler is not None:
            try:
                X_live = pd.DataFrame(
                    self.scaler.transform(X_live),
                    columns=self.feature_columns
                )
            except Exception as e:
                import logging
                logging.getLogger(__name__).error(f"Scaler transform failed: {e}. Using raw features.")

        # Inference
        if hasattr(self.model, "predict_proba"):
            proba      = self.model.predict_proba(X_live)[0]
            pred_idx   = int(np.argmax(proba))
            confidence = float(np.max(proba))
        else:
            pred_idx   = int(self.model.predict(X_live)[0])
            proba      = None
            confidence = 1.0

        if self.label_encoder is not None:
            label = str(self.label_encoder.inverse_transform([pred_idx])[0])
        else:
            label = "correct" if pred_idx == 0 else "incorrect"

        # === STRUCTURED FEATURE AUDIT LOG ===
        # Log distribusi probabilitas DAN nilai fitur aktual untuk setiap rep.
        # Ini memungkinkan diagnosis kasus body_swing/incorrect tanpa debugger:
        #   grep 'FEATURE_AUDIT' backend.log | python -m json.tool
        if proba is not None and self.label_encoder is not None:
            import logging, json
            dist = {
                str(cls): round(float(p), 4)
                for cls, p in zip(self.label_encoder.classes_, proba)
            }
            audit_logger = logging.getLogger("bitri.feature_audit")
            audit_logger.info(
                "FEATURE_AUDIT " + json.dumps({
                    "exercise":      self.exercise_type,
                    "rep":           self.rep_count,
                    "prediction":    label,
                    "confidence":    round(confidence, 4),
                    "proba_dist":    dist,
                    "raw_features": {
                        k: round(float(v), 4)
                        for k, v in raw_features.items()
                        if isinstance(v, (int, float))
                    },
                    "scaled_features": {
                        col: round(float(X_live[col].iloc[0]), 4)
                        for col in self.feature_columns
                    },
                }, ensure_ascii=False)
            )

        return label, confidence


# ----------------------------------------------------------------------
# INVARIANT YANG BERLAKU SETELAH FIX INI
# ----------------------------------------------------------------------
# 1. Train/serve scaler konsisten:
#    scaler_{exercise}.pkl di-fit oleh train_model.py pada raw training
#    data (100% data), dan transform yang SAMA diterapkan di sini.
#    Tidak ada script lain yang boleh membuat atau mengganti file ini.
#
# 2. Segmenter reset konsisten:
#    reset(keep_down=False) sesuai dengan collect_data.py (training).
#
# 3. feature_columns konsisten:
#    Kolom dan urutan dari feature_columns_{exercise}.json == kolom
#    yang dipakai saat model.fit() == kolom yang disimpan di scaler pkl.
#    Verifikasi: scaler_data["feature_columns"] == feature_columns_*.json
# ----------------------------------------------------------------------