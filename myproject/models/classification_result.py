"""
models/classification_result.py
================================
ORM model untuk tabel classification_results yang sudah ada di PostgreSQL.

Schema aktual (dari DB audit 2026-06-25):
  result_id              INTEGER     PK
  session_id             INTEGER     FK → training_sessions.session_id
  classification_status  VARCHAR     (label prediksi — dipetakan dari prediction)
  failure_type           VARCHAR     (error type jika bukan 'correct')
  confidence_score       NUMERIC     (confidence dari XGBoost)
  frame_timestamp        TIMESTAMP   (waktu rep selesai)
  created_at             TIMESTAMP   server default now()

Kolom tambahan yang di-ALTER TABLE oleh migration script:
  rep_number             INTEGER     (urutan rep dalam sesi)
  smoothed_prediction    VARCHAR     (hasil majority vote smoother)
  feedback_text          VARCHAR     (string feedback untuk user)
  features               JSONB       (12 fitur biomekanik)
"""

from sqlalchemy import Column, Integer, String, Float, DateTime, JSON, ForeignKey, Numeric
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from backend.core.database import Base


class ClassificationResult(Base):
    __tablename__ = "classification_results"

    # Kolom yang sudah ada di DB (tidak diubah namanya agar kompatibel)
    result_id             = Column(Integer, primary_key=True, index=True)
    session_id            = Column(
                                Integer,
                                ForeignKey("training_sessions.session_id", ondelete="CASCADE"),
                                nullable=False,
                                index=True,
                            )
    # classification_status = label prediksi utama (mapping dari prediction)
    classification_status = Column(String(50), nullable=False, default="unknown")
    # failure_type = error label jika bukan 'correct', NULL jika correct
    failure_type          = Column(String(100), nullable=True)
    # confidence_score = nilai probabilitas dari XGBoost (0.0–1.0)
    confidence_score      = Column(Numeric(5, 2), nullable=True)  # DB aktual NUMERIC(5,2) — verified via information_schema
    # frame_timestamp = waktu UTC saat rep selesai
    frame_timestamp       = Column(DateTime(timezone=False), nullable=True)
    created_at            = Column(DateTime(timezone=False), server_default=func.now())

    # Kolom tambahan — ditambahkan via migration script (migrate_classification_results.py)
    # SQLAlchemy akan membacanya jika kolom sudah ada; tidak akan crash jika belum
    rep_number            = Column(Integer, nullable=True)
    smoothed_prediction   = Column(String(50), nullable=True)
    feedback_text         = Column(String(500), nullable=True)
    features              = Column(JSON, nullable=True)
