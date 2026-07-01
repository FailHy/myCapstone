"""
diagnostic.py
=============
Script analisis kualitas data dan model untuk BiTri AI.

Jalankan dari root project:
    python -m ml.evaluation.diagnostic

Atau langsung:
    python ml/evaluation/diagnostic.py
"""

import json
import sys
from pathlib import Path

import pandas as pd
from sklearn.decomposition import PCA
from sklearn.metrics import accuracy_score
from sklearn.model_selection import cross_val_predict
from xgboost import XGBClassifier

from ml.features.feature_utils import generate_ratio_features

# FIX MEDIUM: gunakan path dari tools.config, bukan hardcode relative path
from tools.config import CLEAN_DATASET_PATH, MODEL_DIR


def _load_feature_columns(exercise: str = "biceps") -> list:
    """
    Muat feature columns dari file JSON di MODEL_DIR.
    FIX: sebelumnya hardcoded 'models/feature_columns_biceps.json'
         (relative path yang bergantung pada cwd).
         Sekarang menggunakan MODEL_DIR dari tools.config (absolute path).
    """
    path = MODEL_DIR / f"feature_columns_{exercise}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"Feature columns tidak ditemukan: {path}\n"
            f"Pastikan model sudah di-training dan file ada di folder models/."
        )
    with open(path, "r") as f:
        return json.load(f)


def check_subject_bias(exercise: str = "biceps") -> None:
    """
    Cek apakah fitur biomekanik 'bocor' informasi identitas subjek.

    Jika model bisa menebak 'siapa orangnya' hanya dari fitur gerakan,
    artinya ada subject bias — model belajar mengenali orang, bukan kesalahan gerak.
    Target ideal: akurasi < 50% (setara tebak acak).
    """
    print(f"--- 1. MENGECEK SUBJECT BIAS (IDENTITY LEAKAGE) — {exercise.upper()} ---")

    if not CLEAN_DATASET_PATH.exists():
        print(f"ERROR: Dataset bersih tidak ditemukan di {CLEAN_DATASET_PATH}")
        return

    df = pd.read_csv(CLEAN_DATASET_PATH)
    df_ex = df[df["exercise_type"] == exercise].copy()

    if df_ex.empty:
        print(f"WARNING: Tidak ada data untuk exercise_type='{exercise}'. Skip.")
        return

    df_ex = generate_ratio_features(df_ex)

    try:
        features = _load_feature_columns(exercise)
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        return

    # Filter kolom yang benar-benar ada di DataFrame
    available = [c for c in features if c in df_ex.columns]
    missing = [c for c in features if c not in df_ex.columns]
    if missing:
        print(f"WARNING: Kolom berikut tidak ada di dataset, akan dilewati: {missing}")

    X = df_ex[available]

    if "subject_id" not in df_ex.columns:
        print("WARNING: Kolom 'subject_id' tidak ada. Skip subject bias check.")
        return

    # Konversi subject_id string (S01, S02, ...) ke integer untuk XGBoost
    y_subject = df_ex["subject_id"].astype("category").cat.codes
    n_subjects = y_subject.nunique()

    if n_subjects < 2:
        print(f"WARNING: Hanya ada {n_subjects} subjek. Butuh minimal 2 untuk cross-val.")
        return

    cv_folds = min(3, n_subjects)
    model = XGBClassifier(random_state=42, verbosity=0)
    preds = cross_val_predict(model, X, y_subject, cv=cv_folds)
    acc = accuracy_score(y_subject, preds)

    print(f"Akurasi model dalam menebak 'Siapa Subjeknya': {acc * 100:.2f}%")
    if acc > 0.75:
        print("⚠️  CRITICAL WARNING: Model sangat mudah mengenali subjek. Fitur Anda bocor!")
        print("   Terapkan 'normalize_features_per_subject' sebelum melakukan training.")
    elif acc > 0.50:
        print("⚠️  WARNING: Ada indikasi subject bias. Pertimbangkan normalisasi per-subjek.")
    else:
        print("✅ GOOD: Model tidak dapat dengan mudah mengenali subjek dari fiturnya.")


def find_label_issues(exercise: str = "biceps") -> None:
    """
    Audit kualitas label menggunakan CleanLab.
    Deteksi baris data yang kemungkinan salah label.
    """
    print(f"\n--- 2. AUDIT KUALITAS LABEL (CLEANLAB) — {exercise.upper()} ---")
    try:
        from cleanlab.filter import find_label_issues as cl_find_issues
    except ImportError:
        print("CleanLab tidak terinstall. Jalankan: pip install cleanlab")
        return

    if not CLEAN_DATASET_PATH.exists():
        print(f"ERROR: Dataset bersih tidak ditemukan di {CLEAN_DATASET_PATH}")
        return

    df = pd.read_csv(CLEAN_DATASET_PATH)
    df_ex = df[df["exercise_type"] == exercise].copy()

    if df_ex.empty:
        print(f"WARNING: Tidak ada data untuk exercise_type='{exercise}'. Skip.")
        return

    df_ex = generate_ratio_features(df_ex)

    try:
        features = _load_feature_columns(exercise)
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        return

    available = [c for c in features if c in df_ex.columns]
    X = df_ex[available]
    y = df_ex["label"].astype("category").cat.codes

    model = XGBClassifier(random_state=42, verbosity=0)
    pred_probs = cross_val_predict(model, X, y, cv=3, method="predict_proba")

    issues = cl_find_issues(
        labels=y.values,
        pred_probs=pred_probs,
        return_indices_ranked_by="self_confidence",
    )

    print(f"Ditemukan {len(issues)} baris data yang berpotensi SALAH LABEL.")
    if len(issues) > 0:
        print("5 data paling mencurigakan (cek manual video/csv baris ini):")
        suspect_cols = [c for c in ["sample_id", "subject_id", "label"] if c in df_ex.columns]
        print(df_ex.iloc[issues[:5]][suspect_cols].to_string(index=False))


if __name__ == "__main__":
    # Izinkan jalankan dengan argumen exercise: python diagnostic.py triceps
    exercise_arg = sys.argv[1] if len(sys.argv) > 1 else "biceps"
    check_subject_bias(exercise_arg)
    find_label_issues(exercise_arg)