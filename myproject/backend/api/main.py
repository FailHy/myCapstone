import sys
import asyncio
import logging
import logging.handlers
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

# ==========================================
# LOGGING SETUP
# ==========================================
_LOG_DIR = Path(__file__).resolve().parents[2] / "logs"
_LOG_DIR.mkdir(parents=True, exist_ok=True)

# General backend log (INFO+) — tulis ke file dan stdout
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(_LOG_DIR / "backend.log", encoding="utf-8"),
    ],
)

# Feature audit log — satu baris JSON per rep, mudah di-grep/parse:
#   grep 'FEATURE_AUDIT' logs/feature_audit.log | python -m json.tool
_audit_handler = logging.FileHandler(_LOG_DIR / "feature_audit.log", encoding="utf-8")
_audit_handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
_audit_logger = logging.getLogger("bitri.feature_audit")
_audit_logger.setLevel(logging.INFO)
_audit_logger.addHandler(_audit_handler)
_audit_logger.propagate = False  # jangan duplikat ke root logger

session_manager = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global session_manager
    # Import models so SQLAlchemy registers them before create_all
    from models.user import User             # noqa: F401
    from models.training_session import TrainingSession  # noqa: F401
    from models.exercise import Exercise     # noqa: F401
    from models.training_history import TrainingHistory  # noqa: F401
    from models.classification_result import ClassificationResult # noqa: F401
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
                
                if api_status == "rep_completed":
                    # STEP 5 & 6: Save classification result to database without blocking
                    db_session_id = await session_manager.get_db_session_id(session_id)
                    if db_session_id:
                        def save_result():
                            from backend.core.database import SessionLocal
                            from models.classification_result import ClassificationResult
                            from datetime import datetime, timezone
                            db_local = SessionLocal()
                            try:
                                result_record = ClassificationResult(
                                    session_id=db_session_id,
                                    rep_number=result.get("rep_count", 0),
                                    classification_status=result.get("prediction", "unknown"),
                                    smoothed_prediction=result.get("smoothed_prediction"),
                                    confidence_score=result.get("confidence"),
                                    feedback_text=result.get("feedback"),
                                    features=result.get("features", {}),
                                    frame_timestamp=datetime.now(timezone.utc)
                                )
                                db_local.add(result_record)
                                db_local.commit()
                            except Exception as e:
                                import logging
                                logging.getLogger(__name__).error(f"Gagal menyimpan classification result: {e}")
                                db_local.rollback()
                            finally:
                                db_local.close()

                        # Run DB operation in a separate thread so it doesn't block websocket
                        await asyncio.to_thread(save_result)
                
                if api_status == "rep_completed" or current_state != last_state:
                    # In evaluato_service api_status is 'rep_completed' instead of 'success'
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

# STEP 7: Endpoint untuk melihat history hasil klasifikasi per sesi
@app.get("/session/{session_id}/results")
async def get_session_results(session_id: str, db: Session = Depends(get_db)):
    """Mengambil history evaluasi per rep untuk suatu session_id (UUID atau DB session ID)."""
    from models.classification_result import ClassificationResult
    from models.training_session import TrainingSession

    # Cek apakah input adalah DB session ID (integer) atau UUID
    try:
        db_sess_id = int(session_id)
    except ValueError:
        # Jika bukan int, cari UUID di training_sessions (kalau UUID disimpan, tapi saat ini UUID di memory)
        # Untuk simplicity, asumsikan UUID tidak disimpan langsung di DB, jadi gunakan mapping memori kalau sesi masih aktif
        db_sess_id = await session_manager.get_db_session_id(session_id)
        if not db_sess_id:
            raise HTTPException(status_code=404, detail="Sesi UUID tidak ditemukan di memori. Gunakan ID DB sesi.")

    results = (
        db.query(ClassificationResult)
        .filter(ClassificationResult.session_id == db_sess_id)
        .order_by(ClassificationResult.rep_number.asc())
        .all()
    )

    return [
        {
            "rep_number": r.rep_number,
            "prediction": r.classification_status,
            "smoothed_prediction": r.smoothed_prediction,
            "confidence": float(r.confidence_score) if r.confidence_score is not None else None,
            "feedback_text": r.feedback_text
        }
        for r in results
    ]