"""
visualize_scaler.py — Script untuk Visualisasi Statistik StandardScaler (mu, sigma)
==================================================================================
Script ini membaca parameter Rata-rata (mean / mu) dan Standar Deviasi (scale / sigma)
dari file pickle scaler_biceps.pkl dan scaler_triceps.pkl, menghasilkan tabel
format Markdown, serta menyimpan grafik visualisasinya ke dalam folder `reports/`.
"""

import os
import pickle
import matplotlib.pyplot as plt
import numpy as np

def visualize_scaler(exercise_type="biceps"):
    model_path = f"models/scaler_{exercise_type}.pkl"
    if not os.path.exists(model_path):
        print(f"[ERROR] File scaler tidak ditemukan di: {model_path}")
        return

    with open(model_path, "rb") as f:
        data = pickle.load(f)
    
    scaler = data["scaler"]
    features = data["feature_columns"]
    means = scaler.mean_
    scales = scaler.scale_

    print(f"\n===================================================================")
    print(f"      TABEL PARAMETER NORMALISASI STANDARD SCALER ({exercise_type.upper()})      ")
    print(f"===================================================================")
    print(f"| {'No':<2} | {'Nama Fitur (Column)':<22} | {'Rata-rata (μ)':<14} | {'Std Deviasi (σ)':<14} |")
    print(f"|---|------------------------|----------------|----------------|")
    for i, (feat, m, s) in enumerate(zip(features, means, scales), 1):
        print(f"| {i:<2} | {feat:<22} | {m:14.4f} | {s:14.4f} |")
    print(f"===================================================================\n")

    # Generate Visualisasi Chart (Kita pisahkan fitur rasio/durasi/sudut dari fitur berskala besar seperti velocity/smoothness agar mudah dibaca)
    # Kategori 1: Sudut & Rentang (Degrees)
    angle_feats = [f for f in features if "angle" in f or "rom" in f or "sway" in f or "drift" in f]
    # Kategori 2: Waktu, Rasio & Visibility
    time_feats = [f for f in features if "duration" in f or "ratio" in f or "visibility" in f]
    
    os.makedirs("reports", exist_ok=True)

    # Plot 1: Fitur Sudut & Rentang (Degrees)
    if angle_feats:
        idx = [features.index(f) for f in angle_feats]
        m_sub = [means[i] for i in idx]
        s_sub = [scales[i] for i in idx]

        plt.figure(figsize=(10, 6))
        x = np.arange(len(angle_feats))
        bars = plt.bar(x, m_sub, yerr=s_sub, capsize=5, color='#2b5c8f', edgecolor='black', alpha=0.85, label=r'Rata-rata ($\mu$) $\pm$ Std ($\sigma$)')
        plt.xticks(x, angle_feats, rotation=30, ha='right', fontsize=10)
        plt.ylabel('Nilai Sudut / Rentang (Derajat / °)', fontsize=11)
        plt.title(f'Distribusi Parameter StandardScaler ($\mu \pm \sigma$) - Fitur Sudut ({exercise_type.upper()})', fontsize=13, fontweight='bold')
        plt.grid(axis='y', linestyle='--', alpha=0.5)
        plt.legend()
        plt.tight_layout()
        out_path = f"reports/scaler_angles_{exercise_type}.png"
        plt.savefig(out_path, dpi=300)
        plt.close()
        print(f"[SAVED] Grafik Fitur Sudut disimpan ke: {out_path}")

    # Plot 2: Fitur Waktu & Rasio
    if time_feats:
        idx = [features.index(f) for f in time_feats]
        m_sub = [means[i] for i in idx]
        s_sub = [scales[i] for i in idx]

        plt.figure(figsize=(10, 6))
        x = np.arange(len(time_feats))
        bars = plt.bar(x, m_sub, yerr=s_sub, capsize=5, color='#28a745', edgecolor='black', alpha=0.85, label=r'Rata-rata ($\mu$) $\pm$ Std ($\sigma$)')
        plt.xticks(x, time_feats, rotation=30, ha='right', fontsize=10)
        plt.ylabel('Nilai (Detik / Skala Rasio)', fontsize=11)
        plt.title(f'Distribusi Parameter StandardScaler ($\mu \pm \sigma$) - Fitur Waktu & Rasio ({exercise_type.upper()})', fontsize=13, fontweight='bold')
        plt.grid(axis='y', linestyle='--', alpha=0.5)
        plt.legend()
        plt.tight_layout()
        out_path = f"reports/scaler_time_{exercise_type}.png"
        plt.savefig(out_path, dpi=300)
        plt.close()
        print(f"[SAVED] Grafik Fitur Waktu & Rasio disimpan ke: {out_path}")

if __name__ == "__main__":
    visualize_scaler("biceps")
    visualize_scaler("triceps")
