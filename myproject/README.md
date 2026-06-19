# BiTri AI Backend & Machine Learning System

## Overview

BiTri AI merupakan sistem evaluasi latihan **Biceps Curl** dan **Triceps Extension** berbasis Artificial Intelligence yang dikembangkan sebagai bagian dari penelitian skripsi.

Sistem ini bertujuan untuk:

* Menghitung repetisi latihan secara otomatis.
* Mengevaluasi kualitas gerakan latihan.
* Memberikan feedback secara real-time.
* Mendukung integrasi dengan aplikasi mobile Flutter.
* Menjadi platform penelitian untuk analisis biomekanik berbasis pose estimation.

---

# Project Scope

Folder `myproject` berfungsi sebagai pusat pengembangan:

* Backend API
* Machine Learning Pipeline
* Data Collection
* Model Training
* Real-time Exercise Evaluation
* Dataset Processing
* Experimental Analysis

Frontend Flutter berada pada repository/folder terpisah.

---

# Current Project Status

## Backend

Status: **85–90% Complete**

Implemented:

* FastAPI REST API
* WebSocket Real-time Communication
* Session Management
* Async Inference (`asyncio.to_thread`)
* Session TTL Cleanup
* Exercise State Machine
* Repetition Segmentation
* Real-time Feedback Pipeline

Remaining:

* Rep timeout mechanism
* Buffer size limitation
* Database integration

---

## Machine Learning

Status: **Research Phase**

Implemented:

* Feature Extraction Pipeline
* XGBoost Training Pipeline
* Dataset Cleaning
* Exploratory Data Analysis (EDA)

Current Challenge:

* Limited participant diversity.
* Potential subject bias.
* Generalization validation.

Planned Improvements:

* Increase participants to 5–10 subjects.
* LOSO Cross Validation.
* Hybrid Rule-Based + ML approach.

---

# Technologies Used

## Backend

* FastAPI
* WebSocket
* AsyncIO
* Pydantic
* Uvicorn

## Machine Learning

* XGBoost
* Scikit-Learn
* Pandas
* NumPy
* Joblib

## Computer Vision

* MediaPipe Pose
* OpenCV

## Development Tools

* Python 3.11+
* VS Code
* Git

---

# Folder Structure

```text
myproject/

├── backend/
│   ├── api/
│   │   ├── endpoints/
│   │   ├── websocket/
│   │   └── schemas/
│   │
│   ├── core/
│   │   ├── session_manager.py
│   │   ├── evaluator_service.py
│   │   └── state_machine.py
│   │
│   ├── main_simulation.py
│   └── running.py
│
├── dataset/
│   └── data_training.csv
│
├── logs/
│   ├── collection_error.log
│   └── rejected_sample_log.csv
│
├── models/
│   ├── xgboost_model.pkl
│   ├── label_encoder.pkl
│   └── scaler.pkl
│
├── reports/
│   ├── eda/
│   ├── evaluation/
│   └── experiments/
│
├── scripts/
│   ├── clean_dataset.py
│   ├── collect_data.py
│   ├── config.py
│   ├── csvtodb.py
│   ├── data_eda.py
│   ├── feature_utils.py
│   ├── live_evaluator.py
│   ├── pose_utils.py
│   ├── remapping.py
│   └── train_model.py
│
├── tests/
│   ├── test_api.py
│   ├── test_ml.py
│   └── test_websocket.py
│
├── docs/
│   ├── architecture.md
│   ├── dataset_guidelines.md
│   ├── model_decision.md
│   └── troubleshooting.md
│
├── .gitignore
├── requirements.txt
├── README.md
└── setup.py
```

---

# Folder Responsibilities

## backend/

Responsible for:

* API endpoint definitions.
* WebSocket communication.
* Session lifecycle management.
* Real-time inference orchestration.

Should NOT contain:

* Dataset processing logic.
* Model training code.

---

## scripts/

Responsible for:

* Data collection.
* Feature engineering.
* Model training.
* EDA analysis.
* Offline evaluation.

Should NOT contain:

* API routes.
* WebSocket implementations.

---

## dataset/

Contains:

* Raw datasets.
* Processed datasets.

Rules:

* Never edit manually.
* Use scripts for modifications.

---

## models/

Contains:

* Trained models.
* Encoders.
* Preprocessing artifacts.

Rules:

* Version every major model update.
* Include metadata for training configuration.

Example:

```text
xgb_v1_subject3.pkl
xgb_v2_subject5.pkl
```

---

## reports/

Contains:

* EDA results.
* Model evaluation outputs.
* Confusion matrices.
* Research experiments.

Purpose:

Support thesis documentation.

---

## logs/

Contains:

* Collection failures.
* Rejected samples.
* Runtime debugging information.

Should be excluded from Git if large.

---

# Running the Project

## 1. Clone Repository

```bash
git clone <repository-url>
cd myproject
```

---

## 2. Create Virtual Environment

Linux/macOS:

```bash
python -m venv venv
source venv/bin/activate
```

Windows:

```powershell
python -m venv venv
venv\Scripts\activate
```

---

## 3. Install Dependencies

```bash
pip install -r requirements.txt
```

---

## 4. Run Backend API

```bash
python backend/running.py
```

or

```bash
python -m uvicorn backend.api.main:app --host 0.0.0.0 --port 8000 --reload
# gunakan ini jika menggunakan hp eksternal
```

Backend default:

```text
http://localhost:8000
```

---

## 5. Collect Dataset

```bash
# STEP 1: Kumpulkan data training (butuh webcam)
python -m ml.collection.collect_data
```

Output:

```text
dataset
```

---

## 6. Cleaning Dataset

```bash
# STEP 2: Bersihkan dataset
python -m tools.clean_dataset
```

Output:

```text
models/
```

---

## 7. EDA

```bash
# STEP 3: (Opsional) Lihat EDA
python -m ml.evaluation.data_eda
```

---

## 8. Training

```bash
# STEP 4: Training model XGBoost
python -m ml.training.train_model
```

---

## 9. Live Evaluator

```bash
# STEP 5: (Opsional) Test real-time evaluator standalone
python -m ml.inference.live_evaluator
```

---

# AI-Agent Integration Best Practices

This repository is designed to be AI-agent friendly.

Supported Agents:

* ChatGPT
* Claude
* Gemini
* Cursor AI
* GitHub Copilot

---

## Recommended Workflow

### Before Asking AI

Provide:

1. Current folder structure.
2. Relevant source files.
3. Current error logs.
4. Expected behavior.
5. Actual behavior.

---

## Prompt Template

```text
You are a Senior Software Engineer and ML Engineer.

Project Overview:
[Paste README overview]

Task:
[Describe objective]

Relevant Files:
[List files]

Current Behavior:
[Observed output]

Expected Behavior:
[Desired output]

Constraints:
- Maintain existing architecture.
- Avoid breaking WebSocket API.
- Preserve ML pipeline compatibility.

Output:
1. Root cause analysis.
2. Proposed solution.
3. Required code changes.
4. Risks and validation steps.
```

---

# Development Guidelines

## Backend

Follow:

* Single Responsibility Principle.
* Async-first design.
* Non-blocking inference.

Avoid:

* Business logic inside routes.
* Long-running synchronous operations.

---

## Machine Learning

Follow:

* Reproducible experiments.
* Subject-aware validation.
* Proper dataset versioning.

Avoid:

* Random train-test split for human-pose data.
* Mixing participants across train/test.

---

## Dataset Collection Rules

Each `subject_id` must represent:

ONE UNIQUE HUMAN.

Correct:

```text
S01 → Person A
S02 → Person B
S03 → Person C
```

Incorrect:

```text
S01 → Person A
S02 → Person A
S03 → Person A
```

Changing clothes or recording sessions DOES NOT create a new subject.

---

# Known Limitations

* Side-view camera assumption.
* Limited participant diversity.
* Potential subject bias.
* MediaPipe sensitivity to occlusion.
* No production database yet.

These limitations are acceptable within undergraduate research scope if documented properly.

---

# Future Roadmap

Phase 1:

* Flutter integration.

Phase 2:

* Collect 5–10 participants.

Phase 3:

* Retrain model using LOSO-CV.

Phase 4:

* Database integration.

Phase 5:

* Production optimization.

---

# Project Assessment

Backend:

9/10

Frontend:

7/10

ML Architecture:

8/10

Dataset Generalization:

3/10

Overall:

7.5/10

The primary bottleneck is no longer software engineering.

The main challenge moving forward is building a sufficiently diverse dataset to improve model generalization while maintaining explainable feedback for exercise evaluation.
