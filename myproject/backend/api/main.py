import sys
import asyncio
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, status, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError

# PERBAIKAN DI SINI: Cukup gunakan satu .parent agar sesuai dengan posisi folder Anda
PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.services.session_manager import SessionManager
from backend.api.schemas import (
    SessionStartRequest, SessionStartResponse,
    SessionEndRequest, SessionEndResponse,
    PredictRequest
)

# ==========================================
# 1. IMPORT ROUTER AUTHENTICATION (ASLI)
# ==========================================
from backend.api.auth import router as auth_router

session_manager = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global session_manager
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
# 4. ENDPOINT CORE ML & WEBSOCKET (ASLI)
# ==========================================
@app.post("/session/start", response_model=SessionStartResponse)
async def start_session(request: SessionStartRequest):
    try:
        session_id = await session_manager.create_session(
            user_id=request.user_id, 
            exercise_type=request.exercise_type
        )
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
            
            try:
                validated_data = PredictRequest(session_id=session_id, **raw_data)
                landmarks_dict = validated_data.landmarks.model_dump()
                
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
async def end_session(request: SessionEndRequest):
    result = await session_manager.delete_session(request.session_id)
    if result["status"] == "error":
        raise HTTPException(status_code=404, detail="Sesi tidak ditemukan")
    return SessionEndResponse(**result)