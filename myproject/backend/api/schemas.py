from pydantic import BaseModel, Field, EmailStr, ConfigDict
from typing import Dict, Optional, Any, List
from datetime import datetime

# --- Sub-models for Landmarks ---
class Point2D(BaseModel):
    x: float
    y: float
    visibility: float

class LandmarksPayload(BaseModel):
    shoulder: Point2D
    elbow: Point2D
    wrist: Point2D
    hip: Point2D

# --- API Request Models ---
class SessionStartRequest(BaseModel):
    user_id: str
    exercise_type: str = Field(default="biceps", description="Type of exercise, e.g., 'biceps' or 'triceps'")

class SessionEndRequest(BaseModel):
    session_id: str

class PredictRequest(BaseModel):
    session_id: str
    timestamp: float
    landmarks: LandmarksPayload

# --- API Response Models ---
class SessionStartResponse(BaseModel):
    session_id: str
    message: str

class PredictResponse(BaseModel):
    status: str
    state: Optional[str] = None
    rep_count: Optional[int] = None
    prediction: Optional[str] = None
    smoothed_prediction: Optional[str] = None
    confidence: Optional[float] = None
    message: Optional[str] = None
    features: Optional[Dict[str, Any]] = None

class SessionEndResponse(BaseModel):
    status: str
    total_reps: int
    correct_reps: int = 0
    accuracy: float = 0.0
    exercise_type: str
    error_distribution: Optional[Dict[str, int]] = None
    rep_results: Optional[List[Dict[str, Any]]] = None

class HistoryItem(BaseModel):
    id: int
    exercise_type: str
    total_reps: int
    correct_reps: int
    accuracy: float
    created_at: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
    
# Schema untuk Request: POST /auth/register
class UserCreate(BaseModel):
    name: str
    email: EmailStr
    password: str

# Schema untuk Request: POST /auth/login
class UserLogin(BaseModel):
    email: EmailStr
    password: str

# Schema untuk Response data user
class UserResponse(BaseModel):
    user_id: int
    name: str
    email: EmailStr
    created_at: Optional[datetime] = None
    last_login: Optional[datetime] = None

    # Mengizinkan Pydantic membaca data dari object SQLAlchemy
    model_config = ConfigDict(from_attributes=True)

# Schema untuk Response JWT Token
class Token(BaseModel):
    access_token: str
    token_type: str