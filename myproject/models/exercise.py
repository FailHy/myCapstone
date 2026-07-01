from sqlalchemy import Column, Integer, String
from backend.core.database import Base

class Exercise(Base):
    __tablename__ = "exercises"

    exercise_id      = Column(Integer, primary_key=True, index=True)
    name             = Column(String(100), nullable=False, unique=True)
    description      = Column(String(255), nullable=True)
    category         = Column(String(100), nullable=True)
    difficulty_level = Column(String(50), nullable=True)
