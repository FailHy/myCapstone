"""
training_ws.py — DEPRECATED / TIDAK DIGUNAKAN
================================================
File ini adalah sisa dari iterasi pengembangan sebelumnya dan
TIDAK DIINTEGRASIKAN ke main.py.

WebSocket endpoint yang aktif ada di main.py:
    @app.websocket("/ws/{session_id}")

Alur yang benar:
    1. POST /session/start  → dapatkan session_id
    2. WS  /ws/{session_id} → stream landmark frames
    3. POST /session/end    → akhiri sesi

File ini sengaja dikosongkan (CRITICAL-05 fix) untuk menghindari:
    - ImportError karena merujuk class EvaluatorService yang tidak ada
    - Dummy return {"label": "correct", "confidence": 0.9} yang palsu
    - Kebingungan saat audit atau sidang

Jika di masa depan ingin menambahkan endpoint WS alternatif
(misal: /ws/training/{exercise_type} tanpa session management),
buat file baru dan gunakan ExerciseEvaluatorService dari
backend/services/evaluator_service.py.
"""

# File ini sengaja dikosongkan. Tidak ada router yang di-export.