import pickle
import json
import logging
from pathlib import Path
from typing import Tuple, Dict, Any

from tools.config import MODEL_PKL_PATH, TRICEPS_MODEL_PKL_PATH, LABEL_ENCODER_PATH, MODEL_DIR

logger = logging.getLogger(__name__)

class ModelLoader:
    _instance = None
    _models: Dict[str, Any] = {}
    _label_encoder = None
    _feature_columns: Dict[str, list] = {}
    _scalers: Dict[str, Any] = {}  # population scaler per exercise

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._load_all()
        return cls._instance

    def _load_all(self) -> None:
        logger.info("Loading ML artifacts into memory...")

        # Load label encoder (shared antara biceps dan triceps)
        if LABEL_ENCODER_PATH.exists():
            with LABEL_ENCODER_PATH.open("rb") as f:
                self._label_encoder = pickle.load(f)
        else:
            logger.warning(f"Label encoder not found at {LABEL_ENCODER_PATH}")

        # Load models dan feature_columns masing-masing exercise secara terpisah
        exercise_map = {
            "biceps": (
                MODEL_PKL_PATH,
                MODEL_DIR / "feature_columns_biceps.json",
                MODEL_DIR / "scaler_biceps.pkl",
            ),
            "triceps": (
                TRICEPS_MODEL_PKL_PATH,
                MODEL_DIR / "feature_columns_triceps.json",
                MODEL_DIR / "scaler_triceps.pkl",
            ),
        }

        for exercise, (model_path, features_path, scaler_path) in exercise_map.items():
            # Load model
            if model_path.exists():
                with model_path.open("rb") as f:
                    self._models[exercise] = pickle.load(f)
                logger.info(f"Model '{exercise}' loaded from {model_path.name}")
            else:
                logger.warning(f"Model for '{exercise}' not found at {model_path}")

            # Load feature columns per exercise
            if features_path.exists():
                with features_path.open("r") as f:
                    self._feature_columns[exercise] = json.load(f)
                logger.info(
                    f"Feature columns '{exercise}': {len(self._feature_columns[exercise])} features"
                )
            else:
                logger.warning(f"Feature columns for '{exercise}' not found.")
                self._feature_columns[exercise] = []

            # Load population scaler for serving normalization
            if scaler_path.exists():
                with scaler_path.open("rb") as f:
                    scaler_data = pickle.load(f)
                self._scalers[exercise] = scaler_data["scaler"]
                logger.info(f"Scaler '{exercise}' loaded (population normalization).")
            else:
                logger.warning(
                    f"Scaler for '{exercise}' not found at {scaler_path}. "
                    f"Predictions will use raw features — this WILL cause wrong results!"
                )
                self._scalers[exercise] = None

    def get_artifacts(self, exercise_type: str) -> Tuple[Any, Any, list, Any]:
        """Returns (model, label_encoder, feature_columns, scaler) untuk exercise_type."""
        if exercise_type not in self._models:
            raise ValueError(
                f"Model untuk '{exercise_type}' belum dimuat atau tidak ditemukan."
            )
        feature_cols = self._feature_columns.get(exercise_type, [])
        scaler = self._scalers.get(exercise_type)
        if not feature_cols:
            logger.warning(f"Feature columns untuk '{exercise_type}' kosong!")
        if scaler is None:
            logger.warning(
                f"Scaler untuk '{exercise_type}' tidak ditemukan! "
                f"Jalankan: python -c 'from backend.services.model_loader import ModelLoader; ModelLoader()._regenerate_scalers()' "
                f"atau retrain model dengan menyertakan scaler."
            )
        return self._models[exercise_type], self._label_encoder, feature_cols, scaler