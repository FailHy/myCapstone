from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from backend.core.database import Base


class TrainingSession(Base):
    __tablename__ = "training_sessions"

    session_id          = Column(Integer, primary_key=True, index=True)
    user_id             = Column(
                            Integer,
                            ForeignKey("users.user_id", ondelete="CASCADE"),
                            nullable=False, index=True
                          )
    exercise_id         = Column(
                            Integer,
                            ForeignKey("exercises.exercise_id", ondelete="CASCADE"),
                            nullable=False, index=True
                          )

    # Lifecycle timestamps — diisi saat sesi mulai/selesai
    session_date        = Column(DateTime(timezone=True), server_default=func.now())
    start_time          = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    end_time            = Column(DateTime(timezone=True), nullable=True)
    duration_seconds    = Column(Integer, default=0)

    # Hasil latihan
    total_repetitions   = Column(Integer, default=0, nullable=False)
    correct_repetitions = Column(Integer, default=0, nullable=False)
    session_status      = Column(String(50), default="active")

    # Audit timestamps
    created_at          = Column(DateTime(timezone=True), server_default=func.now())
    updated_at          = Column(DateTime(timezone=True),
                                 server_default=func.now(), onupdate=func.now())

    # Relationships
    history = relationship(
        "TrainingHistory",
        back_populates="session",
        uselist=False,
        cascade="all, delete-orphan",
    )
