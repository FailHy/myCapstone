"""
evaluator_service.py
=====================
FIX SUMMARY (vs versi sebelumnya):

1. [BUG UTAMA DIHAPUS] Live session-relative Z-score normalization dihapus
   total. Versi sebelumnya menghitung Z-score rom_elbow (dan fitur lain)
   terhadap rep_history milik sesi live yang sedang berjalan -- termasuk
   rep yang baru saja diprediksi salah (not_full_up, body_swing, dst).
   Akibatnya baseline tercemar oleh urutan rep, dan rep 'correct' yang
   datang setelah beberapa rep buruk bisa mendapat Z-score negatif palsu
   meski ROM-nya secara absolut normal. Model TIDAK pernah dilatih dengan
   skema normalisasi sesi-relatif semacam ini, jadi ini murni train/serve
   skew di level fitur, bukan masalah kualitas model.

   -> Fitur sekarang dikirim ke model dalam skala ABSOLUT, identik dengan
      apa yang dipakai saat training (lihat clean_dataset.py / FEATURE_COLUMNS).

2. [DIHAPUS] State "calibrating" dan rep_history terkait Z-score di atas
   ikut dihapus karena tidak lagi diperlukan. Rep pertama sekarang langsung
   dinilai, bukan di-skip.

3. [DIPERTAHANKAN] up_phase_ratio / down_phase_ratio tetap dihitung karena
   bisa jadi fitur yang valid -- TAPI lihat catatan ASUMSI di bawah ini.
   Anda WAJIB verifikasi dua hal sebelum deploy:
     a) Apakah 'up_phase_ratio' dan 'down_phase_ratio' benar-benar ada di
        self.feature_columns (yaitu di tools/config.py FEATURE_COLUMNS)?
     b) Apakah kolom itu dihitung dengan rumus yang SAMA PERSIS saat
        training/clean_dataset.py? Kalau training tidak punya kolom ini
        sama sekali, HAPUS blok ini -- mengirim kolom ekstra yang tidak
        dikenal model tidak akan menyebabkan crash (karena ada filtering
        ke self.feature_columns), tapi tetap baca catatan di bagian akhir
        file ini.

4. [DIPERTAHANKAN] hybrid_gatekeeper tetap dipanggil sebelum inferensi ML,
   sesuai desain awal Anda (rule-based check untuk error absolut sebelum
   model dipanggil).

5. [TIDAK DIUBAH, PERLU VERIFIKASI TERPISAH] RepetitionSegmenter.reset(
   keep_down=True) dipertahankan apa adanya karena sudah ada di kode
   Anda sebelumnya dan tidak terkait langsung dengan bug Z-score ini.
   Saya TIDAK punya source RepetitionSegmenter, jadi saya tidak bisa
   memverifikasi bahwa reset(keep_down=True) di sini benar-benar
   ekuivalen dengan apa yang dipakai di collect_data.py (yang memakai
   .reset() tanpa argumen). Ini tetap PR terbuka -- lihat catatan akhir.
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
                feedback_text = "Gerakan tidak valid. Pastikan seluruh tubuh terlihat kamera."
            else:
                label, confidence = self._predict(features)
                smoothed_label = self.smoother.update(label)
                try:
                    from ml.features.feature_utils import feedback_from_prediction
                    feedback_text = feedback_from_prediction(smoothed_label, confidence, features)
                except Exception:
                    feedback_text = smoothed_label

            # Track predictions
            self.predictions.append(smoothed_label)
            if smoothed_label == "correct":
                self.correct_reps += 1

            # Reset state ready for next rep
            self.buffer.clear()
            self.segmenter.reset(keep_down=True)

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

        # === CRITICAL FIX: TERAPKAN POPULATION NORMALIZATION ===
        # Model dilatih dengan subject-normalized data (Z-score per subject).
        # Saat serving, kita approximasikan dengan population scaler (global Z-score)
        # yang di-fit dari seluruh training set.
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

        # Log distribusi probabilitas untuk debugging
        if proba is not None and self.label_encoder is not None:
            dist = {str(cls): round(float(p), 4)
                    for cls, p in zip(self.label_encoder.classes_, proba)}
            import logging
            logging.getLogger(__name__).info(
                f"[{self.exercise_type}] Rep prediction: {label} ({confidence:.2%}) | dist={dist}"
            )

        return label, confidence


# ----------------------------------------------------------------------
# CATATAN AKHIR -- HAL YANG SAYA TIDAK BISA VERIFIKASI DARI SINI
# ----------------------------------------------------------------------
# 1. self.feature_columns datang dari ModelLoader.get_artifacts() yang
#    sumbernya tidak saya lihat. Sebelum deploy, print isi
#    self.feature_columns sekali di __init__ dan bandingkan manual dengan
#    FEATURE_COLUMNS di tools/config.py / kolom yang benar-benar dipakai
#    XGBoost saat model.fit(). Kalau ada mismatch nama kolom (mis. training
#    pakai 'rom_elbow' tapi feature_columns berisi nama lain), prediksi
#    akan tetap "jalan" tanpa error tapi dengan nilai 0.0 yang salah --
#    ini silent failure paling berbahaya, tidak akan kelihatan dari log
#    error biasa.
#
# 2. RepetitionSegmenter.reset(keep_down=True) di live vs collect_data.py
#    yang memakai .reset() tanpa argumen -- saya tidak punya source
#    RepetitionSegmenter untuk memastikan keduanya menghasilkan state awal
#    yang identik. Ini tetap area yang perlu diverifikasi terpisah, di
#    luar fix Z-score ini.
#
# 3. Sebelum retrain model apapun: jalankan dulu kode ini apa adanya
#    terhadap model yang SUDAH ADA (akurasi offline 92%). Karena bug-nya
#    ada di serving (skala fitur), model yang sudah dilatih kemungkinan
#    besar sudah cukup baik begitu pipeline ini diperbaiki -- retrain
#    baru perlu dipertimbangkan SETELAH Anda konfirmasi fix ini tidak
#    cukup menyelesaikan masalah live evaluator.
# ----------------------------------------------------------------------