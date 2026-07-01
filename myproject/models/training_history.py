from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from backend.core.database import Base

class TrainingHistory(Base):
    __tablename__ = "training_history"

    history_id          = Column(Integer, primary_key=True, index=True)
    user_id             = Column(Integer, ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    session_id          = Column(Integer, ForeignKey("training_sessions.session_id", ondelete="CASCADE"), unique=True, nullable=False)
    average_accuracy    = Column(Float, default=0.0)
    summary             = Column(String, nullable=True)
    total_repetitions   = Column(Integer, default=0)
    correct_repetitions = Column(Integer, default=0)
    training_date       = Column(DateTime(timezone=True), server_default=func.now())
    duration_seconds    = Column(Integer, default=0)

    # Relationships
    session = relationship("TrainingSession", back_populates="history")
