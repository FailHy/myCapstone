import sys
import asyncio
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, status, WebSocket, WebSocketDisconnect, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError
from sqlalchemy.orm import Session

PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.core.database import get_db, engine, Base
from backend.services.session_manager import SessionManager
from backend.api.schemas import (
    SessionStartRequest, SessionStartResponse,
    SessionEndRequest, SessionEndResponse,
    PredictRequest, HistoryItem
)

# ==========================================
# 1. IMPORT ROUTER AUTHENTICATION (ASLI)
# ==========================================
from backend.api.auth import router as auth_router

session_manager = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global session_manager
    # Import models so SQLAlchemy registers them before create_all
    from models.user import User             # noqa: F401
    from models.training_session import TrainingSession  # noqa: F401
    from models.exercise import Exercise     # noqa: F401
    from models.training_history import TrainingHistory  # noqa: F401
    Base.metadata.create_all(bind=engine)
    print("✅ Database tables verified/created.")

    print("🚀 Memulai API dan memuat model ML...")
    session_manager = SessionManager()

    cleanup_task = asyncio.create_task(session_manager.cleanup_loop())

    yield

    print("🛑 Mematikan API...")
    cleanup_task.cancel()
    await session_manager.shutdown()

app = FastAPI(title="BiTri AI Backend", lifespan=lifespan)

# ==========================================
# 2. KONFIGURASI CORS
# ==========================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# 3. DAFTARKAN ROUTER AUTHENTICATION
# ==========================================
# Ini akan mendaftarkan /auth/register dan /auth/login
app.include_router(auth_router)

@app.get("/")
async def root():
    """Endpoint untuk testing di browser"""
    return {"message": "BiTri API is running!"}

# ==========================================
# 4. ENDPOINT CORE ML & WEBSOCKET
# ==========================================
@app.post("/session/start", response_model=SessionStartResponse)
async def start_session(request: SessionStartRequest, db: Session = Depends(get_db)):
    try:
        session_id = await session_manager.create_session(
            user_id=request.user_id,
            exercise_type=request.exercise_type
        )

        # Buat record di DB saat sesi MULAI (bukan saat selesai)
        db_session_id = None
        user_id_str = str(request.user_id)
        try:
            user_id_int = int(user_id_str)
            if user_id_int > 0:
                from models.training_session import TrainingSession
                from models.exercise import Exercise

                exercise = db.query(Exercise).filter(
                    Exercise.name == request.exercise_type
                ).first()
                if not exercise:
                    exercise = Exercise(name=request.exercise_type, category="Strength")
                    db.add(exercise)
                    db.commit()
                    db.refresh(exercise)

                ts = TrainingSession(
                    user_id    = user_id_int,
                    exercise_id= exercise.exercise_id,
                    session_status = "active",
                )
                db.add(ts)
                db.commit()
                db.refresh(ts)
                db_session_id = ts.session_id

                # Simpan mapping session_id -> db_session_id di manager
                await session_manager.set_db_session_id(session_id, db_session_id)
                print(f"📋 Session started: uuid={session_id} db_id={db_session_id}")
        except (ValueError, TypeError) as e:
            print(f"⚠️ DB session create skipped: {e}")

        return SessionStartResponse(session_id=session_id, message="Sesi dibuat. Hubungkan ke WS.")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.websocket("/ws/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    await websocket.accept()
    
    try:
        evaluator = await session_manager.get_session(session_id)
    except KeyError:
        await websocket.send_json({"error": "Sesi tidak valid atau telah berakhir"})
        await websocket.close(code=1008)
        return

    last_state = None

    try:
        while True:
            raw_data = await websocket.receive_json()
            await session_manager.touch_session(session_id)

            # Handle heartbeat ping tanpa diproses sebagai frame
            if isinstance(raw_data, dict) and raw_data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            try:
                # =========================================================
                # PERBAIKAN MUTLAK (LAYER DEFENSIF MENCEGAH CRASH)
                # =========================================================
                # Hapus key 'session_id' dari data yang dikirim Flutter (jika ada)
                # untuk menghindari TypeError saat unpacking parameter **raw_data
                if isinstance(raw_data, dict):
                    raw_data.pop("session_id", None)
                
                # Sekarang unpacking dijamin aman dan hanya diisi dari URL path
                validated_data = PredictRequest(session_id=session_id, **raw_data)
                landmarks_dict = validated_data.landmarks.model_dump()

                # FIX CRITICAL-01: kirim landmarks_dict langsung (flat dict)
                # process_frame() yang baru menerima flat dict {shoulder, elbow, wrist, hip}
                result = await asyncio.to_thread(
                    evaluator.process_frame,
                    validated_data.timestamp,
                    landmarks_dict
                )
                
                current_state = result.get("state")
                api_status = result.get("status")
                
                if api_status == "success" or current_state != last_state:
                    await websocket.send_json(result)
                    last_state = current_state
                    
            except ValidationError as ve:
                await websocket.send_json({"error": "Struktur payload tidak valid", "details": ve.errors()})
                
    except WebSocketDisconnect:
        print(f"⚠️ Klien terputus dari sesi {session_id}")

@app.post("/session/end", response_model=SessionEndResponse)
async def end_session(request: SessionEndRequest, db: Session = Depends(get_db)):
    result = await session_manager.delete_session(request.session_id)
    if result["status"] == "error":
        raise HTTPException(status_code=404, detail="Sesi tidak ditemukan")

    # UPDATE record yang sudah dibuat saat /session/start
    db_session_id = result.get("db_session_id")
    user_id_str   = result.get("user_id", "")

    try:
        user_id_int = int(user_id_str)
        if user_id_int > 0 and db_session_id:
            from models.training_session import TrainingSession
            from models.training_history import TrainingHistory
            from datetime import datetime, timezone
            import json

            ts = db.query(TrainingSession).filter(
                TrainingSession.session_id == db_session_id
            ).first()

            if ts:
                ts.total_repetitions   = result["total_reps"]
                ts.correct_repetitions = result["correct_reps"]
                ts.session_status      = "completed"
                ts.end_time            = datetime.now(timezone.utc)
                # Hitung durasi jika start_time tersedia
                if ts.start_time:
                    delta = ts.end_time - ts.start_time.replace(tzinfo=timezone.utc) \
                            if ts.start_time.tzinfo is None \
                            else ts.end_time - ts.start_time
                    ts.duration_seconds = max(0, int(delta.total_seconds()))
                db.commit()

                # Buat/update training_history
                history = db.query(TrainingHistory).filter(
                    TrainingHistory.session_id == db_session_id
                ).first()
                if history:
                    history.average_accuracy    = result["accuracy"]
                    history.total_repetitions   = result["total_reps"]
                    history.correct_repetitions = result["correct_reps"]
                    history.summary             = json.dumps(result.get("error_distribution", {}))
                else:
                    history = TrainingHistory(
                        user_id             = user_id_int,
                        session_id          = db_session_id,
                        average_accuracy    = result["accuracy"],
                        total_repetitions   = result["total_reps"],
                        correct_repetitions = result["correct_reps"],
                        summary             = json.dumps(result.get("error_distribution", {})),
                    )
                    db.add(history)
                db.commit()
                print(f"💾 Session completed: db_id={db_session_id} reps={result['total_reps']} acc={result['accuracy']}%")
            else:
                print(f"⚠️ DB session {db_session_id} not found for update")
    except (ValueError, TypeError) as e:
        print(f"⚠️ DB session update skipped: {e}")

    return SessionEndResponse(
        status        = result["status"],
        total_reps    = result["total_reps"],
        correct_reps  = result["correct_reps"],
        accuracy      = result["accuracy"],
        exercise_type = result["exercise_type"],
    )


@app.get("/history/{user_id}")
async def get_history(user_id: int, db: Session = Depends(get_db)):
    """Ambil riwayat latihan user, 20 sesi terbaru."""
    from models.training_session import TrainingSession
    from models.training_history import TrainingHistory
    from models.exercise import Exercise

    sessions = (
        db.query(TrainingSession, TrainingHistory, Exercise)
        .join(TrainingHistory, TrainingSession.session_id == TrainingHistory.session_id)
        .join(Exercise, TrainingSession.exercise_id == Exercise.exercise_id)
        .filter(TrainingSession.user_id == user_id)
        .order_by(TrainingSession.created_at.desc())
        .limit(20)
        .all()
    )
    return [
        {
            "id":            ts.session_id,
            "exercise_type": ex.name,
            "total_reps":    th.total_repetitions,
            "correct_reps":  th.correct_repetitions,
            "accuracy":      th.average_accuracy,
            "created_at":    ts.created_at.isoformat() if ts.created_at else None,
        }
        for ts, th, ex in sessions
    ]