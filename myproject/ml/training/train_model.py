from __future__ import annotations

import argparse
import json
import pickle
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
import xgboost as xgb
from sklearn.metrics import (
    accuracy_score, 
    balanced_accuracy_score, 
    classification_report, 
    confusion_matrix, 
    f1_score
)
# Ganti GroupShuffleSplit dengan LeaveOneGroupOut untuk evaluasi yang lebih kuat
from sklearn.model_selection import LeaveOneGroupOut, train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.utils.class_weight import compute_sample_weight

# Mengambil konfigurasi path dari config.py
from tools.config import (
    # normal training
    # CLEAN_DATASET_PATH,
    # ==========================
    # cleaning ultra more better
    ULTRA_CLEAN_DATASET_PATH, 
    REPORT_DIR,
    FEATURE_COLUMNS, 
    MODEL_DIR, 
    LABEL_ENCODER_PATH,
)

# Import fungsi feature engineering dari feature_utils
from ml.features.feature_utils import (
    generate_ratio_features,
)

# -----------------------------------------------------------------------------
# 1. FUNGSI PERSIAPAN DATA
# -----------------------------------------------------------------------------
def clean_previous_artifacts() -> None:
    """Membersihkan artefak model lama agar tidak terjadi penumpukan/konflik."""
    for path in [MODEL_DIR, REPORT_DIR]:
        if path.exists():
            for file in path.glob("*"):
                try:
                    if file.is_file(): file.unlink()
                    elif file.is_dir(): shutil.rmtree(file)
                except Exception as e:
                    print(f"Gagal menghapus {file}: {e}")

def load_and_filter_dataset(path: Path, exercise_type: str) -> pd.DataFrame:
    """Membaca dataset, memfilter jenis latihan, DAN membuang data sintesis lama."""
    if not path.exists():
        raise FileNotFoundError(f"Dataset bersih tidak ditemukan di: {path}")
    
    df = pd.read_csv(path)
    if df.empty:
        raise ValueError("Dataset bersih kosong!")
        
    if "exercise_type" not in df.columns:
        print("WARNING: Kolom 'exercise_type' tidak ditemukan. Mengasumsikan semua data adalah Biceps.")
        df["exercise_type"] = "biceps"

    df_filtered = df[df["exercise_type"] == exercise_type].copy()
    return df_filtered


# -----------------------------------------------------------------------------
# 2. FUNGSI PEMBUATAN & VISUALISASI MODEL
# -----------------------------------------------------------------------------
def make_model(num_classes: int, random_state: int) -> xgb.XGBClassifier:
    """Inisialisasi arsitektur model XGBoost dengan hyperparameter anti-overfitting."""
    common = dict(
        n_estimators=150,           
        max_depth=4,                
        learning_rate=0.05,         
        subsample=0.8,              
        colsample_bytree=0.8,       
        random_state=random_state,
        eval_metric="logloss" if num_classes == 2 else "mlogloss",
    )
    if num_classes == 2:
        return xgb.XGBClassifier(objective="binary:logistic", **common)
    return xgb.XGBClassifier(objective="multi:softprob", num_class=num_classes, **common)

def save_learning_curve(evals_result: dict, exercise_name: str, output_dir: Path) -> None:
    if not evals_result:
        return # Skip jika model dilatih penuh tanpa eval_set (seperti final_model)
        
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"xgboost_learning_curve_{exercise_name}.png"
    
    fig, ax = plt.subplots(figsize=(8, 5))
    metric_name = list(evals_result['validation_0'].keys())[0]
    train_errors = evals_result['validation_0'][metric_name]
    test_errors = evals_result['validation_1'][metric_name]
    epochs = range(len(train_errors))
    
    ax.plot(epochs, train_errors, label='Train Error', color='blue', linewidth=2)
    ax.plot(epochs, test_errors, label='Test Error', color='red', linewidth=2)
    
    ax.set_title(f'XGBoost Learning Curve - {exercise_name.upper()}')
    ax.set_xlabel('Epoch (Jumlah Pohon)')
    ax.set_ylabel(f'Error ({metric_name})')
    ax.legend()
    ax.grid(True, linestyle='--', alpha=0.6)
    
    fig.tight_layout()
    fig.savefig(output_path, dpi=150)
    plt.close(fig)

def save_confusion_matrix(y_true, y_pred, label_names, exercise_name: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"xgboost_confusion_matrix_{exercise_name}.png"
    
    cm = confusion_matrix(y_true, y_pred, labels=range(len(label_names)))
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=label_names, yticklabels=label_names)
    
    plt.title(f'Confusion Matrix (OOF) - {exercise_name.upper()}')
    plt.ylabel('Aktual')
    plt.xlabel('Prediksi')
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()

# -----------------------------------------------------------------------------
# 3. PIPELINE PELATIHAN (Dengan RCA Fixes: LOGO CV & Class Weights)
# -----------------------------------------------------------------------------
def train_single_model(df_filtered: pd.DataFrame, exercise_name: str, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print(f" 🚀 MEMULAI PELATIHAN MODEL: {exercise_name.upper()}")
    print(f"{'='*60}")

    target_col = "error_type"

    # 1. Feature Engineering
    df_engineered = generate_ratio_features(df_filtered)

    # Gabungkan fitur asli dengan fitur baru yang mungkin dibuat
    all_possible_features = FEATURE_COLUMNS + ['up_phase_ratio', 'down_phase_ratio']
    features = [col for col in all_possible_features if col in df_engineered.columns]

    # Drop NAs
    df_engineered = df_engineered.dropna(subset=[target_col] + features).reset_index(drop=True)
    if len(df_engineered) < 20:
        print(f"⚠️ Melewati {exercise_name.upper()} karena datanya terlalu sedikit ({len(df_engineered)} baris).")
        return

    # 2. Siapkan X dan y dari data mentah (belum di-scale)
    #    StandardScaler akan di-fit DI DALAM loop CV untuk mencegah leakage.
    X = df_engineered[features].astype(float)

    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(df_engineered[target_col].astype(str))
    label_names = list(label_encoder.classes_)
    num_classes = len(label_names)

    # Gunakan subject_id untuk grouping CV
    if "subject_id" in df_engineered.columns and len(df_engineered["subject_id"].unique()) > 1:
        groups = df_engineered["subject_id"].values
        logo = LeaveOneGroupOut()
        splits = list(logo.split(X, y, groups))
        print(f"   -> Menggunakan Leave-One-Group-Out CV ({len(splits)} Folds / Subjects)")
    else:
        # Fallback jika tidak ada subject_id
        from sklearn.model_selection import StratifiedKFold
        skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=args.random_state)
        splits = list(skf.split(X, y))
        print("   -> Menggunakan Stratified 5-Fold CV (Subjek kurang bervariasi)")
        groups = None

    # Array untuk menyimpan seluruh prediksi Out-Of-Fold
    y_true_all = []
    y_pred_all = []

    # 3. Cross Validation Loop
    #    PENTING: StandardScaler di-fit HANYA pada data training setiap fold
    #    agar tidak terjadi data leakage dari test fold ke scaler.
    for fold, (train_idx, test_idx) in enumerate(splits):
        X_train_raw, X_test_raw = X.iloc[train_idx], X.iloc[test_idx]
        y_train, y_test = y[train_idx], y[test_idx]

        # Fit scaler hanya pada training fold, transform keduanya
        fold_scaler = StandardScaler()
        X_train_scaled = pd.DataFrame(
            fold_scaler.fit_transform(X_train_raw),
            columns=features,
        )
        X_test_scaled = pd.DataFrame(
            fold_scaler.transform(X_test_raw),
            columns=features,
        )

        # Hitung class weights untuk fold ini
        sample_weights = compute_sample_weight(class_weight='balanced', y=y_train)

        model_fold = make_model(num_classes=num_classes, random_state=args.random_state)
        model_fold.fit(
            X_train_scaled, y_train,
            sample_weight=sample_weights,
            verbose=False,
        )

        preds = model_fold.predict(X_test_scaled)
        y_true_all.extend(y_test)
        y_pred_all.extend(preds)

        if groups is not None:
            test_subject = groups[test_idx][0]
            print(f"      Fold {fold+1} | Test Subject: {test_subject} | Acc: {accuracy_score(y_test, preds)*100:.1f}%")

    # 4. Evaluasi Keseluruhan (Out-Of-Fold)
    print("\n   📊 LAPORAN EVALUASI (OUT-OF-FOLD / SELURUH SUBJEK)")
    acc = accuracy_score(y_true_all, y_pred_all) * 100
    bal_acc = balanced_accuracy_score(y_true_all, y_pred_all) * 100
    print(f"   - Akurasi (Accuracy) : {acc:.2f}%")
    print(f"   - Akurasi (Balanced) : {bal_acc:.2f}%\n")

    all_labels = list(range(num_classes))
    print(classification_report(
        y_true_all, y_pred_all,
        labels=all_labels, target_names=label_names, zero_division=0,
    ))

    save_confusion_matrix(y_true_all, y_pred_all, label_names, exercise_name, REPORT_DIR)

    # 5. Latih Final Model pada 100% Data
    #    Fit scaler baru pada SEMUA data training — ini yang akan disimpan
    #    dan dipakai saat serving sehingga skala train == serving.
    print("   -> Melatih scaler & model final pada 100% data...")
    final_scaler = StandardScaler()
    X_scaled_all = pd.DataFrame(
        final_scaler.fit_transform(X),
        columns=features,
    )

    final_model = make_model(num_classes=num_classes, random_state=args.random_state)
    final_weights = compute_sample_weight(class_weight='balanced', y=y)

    # Dummy eval_set untuk learning curve (10% dari data yang sudah di-scale)
    X_train_f, X_val_f, y_train_f, y_val_f, w_train_f, _ = train_test_split(
        X_scaled_all, y, final_weights,
        test_size=0.1, random_state=args.random_state, stratify=y,
    )

    eval_set_final = [(X_train_f, y_train_f), (X_val_f, y_val_f)]
    final_model.fit(
        X_train_f, y_train_f,
        eval_set=eval_set_final,
        sample_weight=w_train_f,
        verbose=False,
    )

    save_learning_curve(final_model.evals_result(), exercise_name, REPORT_DIR)

    # 6. Simpan Model & Artefak
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    # Model
    final_model.save_model(str(MODEL_DIR / f"xgboost_{exercise_name}_model.json"))
    with (MODEL_DIR / f"{exercise_name}_xgboost_model.pkl").open("wb") as f:
        pickle.dump(final_model, f)

    # Label encoder
    with LABEL_ENCODER_PATH.open("wb") as f:
        pickle.dump(label_encoder, f)

    # Feature columns
    with (MODEL_DIR / f"feature_columns_{exercise_name}.json").open("w") as f:
        json.dump(features, f, indent=2)

    # Scaler — WAJIB disimpan agar serving menggunakan transformasi yang IDENTIK
    # dengan yang dipakai saat training. Tidak boleh di-fit ulang di luar sini.
    scaler_path = MODEL_DIR / f"scaler_{exercise_name}.pkl"
    with scaler_path.open("wb") as f:
        pickle.dump({"scaler": final_scaler, "feature_columns": features}, f)

    print(f"✅ Selesai! Model, scaler, dan artefak {exercise_name.upper()} berhasil disimpan.")


def train_all_models(args: argparse.Namespace) -> None:
    if not args.input.exists():
         print(f"ERROR: Dataset tidak ditemukan di: {args.input}")
         return

    df_full = pd.read_csv(args.input)
    if "exercise_type" not in df_full.columns:
        train_single_model(df_full, "biceps", args)
        return
        
    available_exercises = df_full["exercise_type"].dropna().unique()
    
    for exercise in available_exercises:
        df_filtered = load_and_filter_dataset(args.input, exercise)
        train_single_model(df_filtered, exercise, args)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    # normal training
    # parser.add_argument("--input", type=Path, default=CLEAN_DATASET_PATH)

    # ultra cleaning
    parser.add_argument("--input", type=Path, default=ULTRA_CLEAN_DATASET_PATH)
    parser.add_argument("--test-size", type=float, default=0.2)
    parser.add_argument("--random-state", type=int, default=42)
    return parser.parse_args()

if __name__ == "__main__":
    main_args = parse_args()
    train_all_models(main_args)