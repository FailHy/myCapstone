import pandas as pd
import json
from xgboost import XGBClassifier
from sklearn.model_selection import cross_val_predict
from sklearn.metrics import accuracy_score
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.decomposition import PCA
from ml.features.feature_utils import generate_ratio_features

from tools.config import CLEAN_DATASET_PATH

def check_subject_bias():
    print("--- 1. MENGECEK SUBJECT BIAS (IDENTITY LEAKAGE) ---")
    df = pd.read_csv(CLEAN_DATASET_PATH)
    df_biceps = df[df['exercise_type'] == 'biceps'].copy()
    df_biceps = generate_ratio_features(df_biceps)
    
    with open('models/feature_columns_biceps.json', 'r') as f:
        features = json.load(f)
        
    X = df_biceps[features]
    y_subject = df_biceps['subject_id'] # Target adalah SIAPA orangnya, bukan gerakannya
    
    model = XGBClassifier(random_state=42)
    # Konversi string subject_id (S01, S02) ke integer untuk XGBoost
    y_subject_encoded = y_subject.astype('category').cat.codes 
    
    preds = cross_val_predict(model, X, y_subject_encoded, cv=3)
    acc = accuracy_score(y_subject_encoded, preds)
    
    print(f"Akurasi model dalam menebak 'Siapa Subjeknya': {acc*100:.2f}%")
    if acc > 0.75:
        print("CRITICAL WARNING: Model sangat mudah mengenali subjek. Fitur Anda bocor!")
        print("Terapkan 'normalize_features_per_subject' sebelum melakukan training.")
    else:
        print("GOOD: Model tidak dapat dengan mudah mengenali subjek dari fiturnya.")

def find_label_issues():
    print("\n--- 2. AUDIT KUALITAS LABEL (CLEANLAB) ---")
    try:
        from cleanlab.classification import CleanLearning
        from cleanlab.filter import find_label_issues
        
        df = pd.read_csv(CLEAN_DATASET_PATH)
        df_biceps = df[df['exercise_type'] == 'biceps'].copy()
        df_biceps = generate_ratio_features(df_biceps)
        
        with open('models/feature_columns_biceps.json', 'r') as f:
            features = json.load(f)
            
        X = df_biceps[features]
        y = df_biceps['label'].astype('category').cat.codes
        
        model = XGBClassifier(random_state=42)
        # Prediksi probabilitas menggunakan cross-validation
        pred_probs = cross_val_predict(model, X, y, cv=3, method='predict_proba')
        
        issues = find_label_issues(labels=y.values, pred_probs=pred_probs, return_indices_ranked_by='self_confidence')
        
        print(f"Ditemukan {len(issues)} baris data yang berpotensi SALAH LABEL.")
        print("Berikut adalah 5 data paling mencurigakan (Cek manual videonya/csv baris ini):")
        suspicious_samples = df_biceps.iloc[issues[:5]][['sample_id', 'subject_id', 'label']]
        print(suspicious_samples)
        
    except ImportError:
        print("Install cleanlab terlebih dahulu: pip install cleanlab")

if __name__ == "__main__":
    check_subject_bias()
    find_label_issues()