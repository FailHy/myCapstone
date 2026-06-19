import pandas as pd
import json
from pathlib import Path
from xgboost import XGBClassifier
from sklearn.model_selection import cross_val_predict
from sklearn.preprocessing import LabelEncoder
import numpy as np

# Mengambil konfigurasi path dari config.py
from tools.config import (
    CLEAN_DATASET_PATH, 
    REPORT_DIR, 
    FEATURE_COLUMNS,
    DATASET_DIR
)

# Import fungsi fitur kita
from ml.features.feature_utils import generate_ratio_features, normalize_features_per_subject

def audit_and_clean_labels():
    print("Memulai Audit Label Otomatis dengan Cleanlab...")
    try:
        from cleanlab.filter import find_label_issues
    except ImportError:
        print("MENGINSTALL CLEANLAB... Silakan jalankan: pip install cleanlab")
        return

    # Paths (menggunakan config.py)
    dataset_path = CLEAN_DATASET_PATH
    suspicious_output = REPORT_DIR / 'suspicious_labels.csv'
    ultra_clean_output = DATASET_DIR / 'data_ultra_clean.csv'

    # Load data
    try:
        df = pd.read_csv(dataset_path)
    except FileNotFoundError:
        print(f"File tidak ditemukan: {dataset_path}")
        return

    df_biceps = df[df['exercise_type'] == 'biceps'].copy()

    # Feature Engineering & Normalization (Sesuai dengan cara model dilatih)
    df_biceps = generate_ratio_features(df_biceps)
    
    # Menambahkan fitur rasio ke daftar fitur
    all_possible_features = FEATURE_COLUMNS + ['up_phase_ratio', 'down_phase_ratio']
    features = [col for col in all_possible_features if col in df_biceps.columns]

    # Drop baris yang memiliki nilai NaN pada fitur atau label
    df_biceps = df_biceps.dropna(subset=['error_type'] + features).reset_index(drop=True)
    
    # Normalisasi per subject
    df_normalized = normalize_features_per_subject(df_biceps, features, 'subject_id')

    X = df_normalized[features]
    
    # Encode label
    le = LabelEncoder()
    y_encoded = le.fit_transform(df_normalized['error_type'])

    # Dapatkan prediksi probabilitas (Cross-Validation)
    print("Mengevaluasi probabilitas setiap baris (bisa memakan waktu beberapa detik)...")
    model = XGBClassifier(random_state=42, eval_metric='mlogloss')
    pred_probs = cross_val_predict(model, X, y_encoded, cv=5, method='predict_proba')

    # Deteksi Label Bermasalah
    issues_idx = find_label_issues(
        labels=y_encoded, 
        pred_probs=pred_probs, 
        return_indices_ranked_by='self_confidence'
    )

    if len(issues_idx) == 0:
        print("Dataset sudah sangat bersih! Tidak ada label issue ditemukan.")
        # Jika sudah bersih, langsung salin saja ke data_ultra_clean.csv
        df.to_csv(ultra_clean_output, index=False)
        print(f"Dataset disimpan di: {ultra_clean_output}")
        return

    print(f"Ditemukan {len(issues_idx)} baris dengan label mencurigakan.")

    # 1. BUAT REPORT UNTUK REVIEW MANUAL
    df_issues = df_biceps.iloc[issues_idx].copy()
    
    # Tambahkan kolom prediksi model agar Anda tahu apa tebakan model
    predicted_classes = np.argmax(pred_probs[issues_idx], axis=1)
    df_issues['MODEL_PREDICTION'] = le.inverse_transform(predicted_classes)
    df_issues['MODEL_CONFIDENCE'] = np.max(pred_probs[issues_idx], axis=1)

    # Reorder kolom agar mudah dibaca di Excel
    cols = ['sample_id', 'subject_id', 'error_type', 'MODEL_PREDICTION', 'MODEL_CONFIDENCE', 'rom_elbow', 'elbow_velocity_mean', 'rep_duration']
    other_cols = [c for c in df_issues.columns if c not in cols]
    df_issues = df_issues[cols + other_cols]

    suspicious_output.parent.mkdir(parents=True, exist_ok=True)
    df_issues.to_csv(suspicious_output, index=False)
    print(f"✅ Laporan detail disimpan di: {suspicious_output}")
    print("   -> Buka file ini di Excel. Bandingkan kolom 'error_type' (label asli) dengan 'MODEL_PREDICTION'.")

    # 2. BUAT DATASET "ULTRA CLEAN" (Menghapus baris yang bermasalah)
    df_clean_biceps = df_biceps.drop(index=issues_idx)
    
    # Kembalikan kolom ke kondisi awal sebelum feature engineering rasio ditambahkan (opsional, tapi lebih baik agar konsisten dengan format awal)
    df_clean_biceps = df_clean_biceps.drop(columns=['up_phase_ratio', 'down_phase_ratio'], errors='ignore')
    
    # Gabungkan kembali dengan data triceps yang tidak diotak-atik
    df_triceps = df[df['exercise_type'] == 'triceps'].copy()
    df_ultra_clean = pd.concat([df_clean_biceps, df_triceps], ignore_index=True)
    
    # Urutkan berdasarkan sample_id
    df_ultra_clean = df_ultra_clean.sort_values(by='sample_id')
    
    ultra_clean_output.parent.mkdir(parents=True, exist_ok=True)
    df_ultra_clean.to_csv(ultra_clean_output, index=False)
    print(f"✅ Dataset Ultra-Clean (tanpa {len(issues_idx)} baris bermasalah) disimpan di: {ultra_clean_output}")

if __name__ == "__main__":
    audit_and_clean_labels()