from __future__ import annotations

import asyncio
import time
import uuid
from collections import Counter
from typing import Any, Dict, Optional

from .model_loader import ModelLoader
from .evaluator_service import ExerciseEvaluatorService


# TTL dalam detik. Sesi yang tidak menerima frame selama ini akan dihapus.
_SESSION_TTL_SECONDS: int = 300  # 5 menit


class SessionManager:
    def __init__(self, session_ttl: int = _SESSION_TTL_SECONDS) -> None:
        # Dict utama: session_id -> ExerciseEvaluatorService
        self._sessions: Dict[str, ExerciseEvaluatorService] = {}

        # Dict user_id per sesi
        self._user_ids: Dict[str, str] = {}

        # Dict db_session_id (int row ID di tabel training_sessions) per sesi
        self._db_session_ids: Dict[str, Optional[int]] = {}

        # Dict timestamp last-touch: session_id -> float (epoch)
        self._last_activity: Dict[str, float] = {}

        # Lock tunggal untuk semua operasi ke _sessions dan _last_activity.
        # asyncio.Lock aman di single-process uvicorn. Jika upgrade ke
        # multi-process (Gunicorn), ganti dengan Redis-based session store.
        self._lock = asyncio.Lock()

        self._ttl = session_ttl
        self.model_loader = ModelLoader()

    # ------------------------------------------------------------------
    # PUBLIC ASYNC INTERFACE
    # ------------------------------------------------------------------

    async def create_session(
        self, user_id: str, exercise_type: str = "biceps"
    ) -> str:
        """
        Alokasi sesi baru. Mengembalikan session_id (UUID string).

        Raises:
            ValueError: jika exercise_type tidak dikenali model loader.
        """
        # ModelLoader.get_artifacts returns (model, label_encoder, feature_columns, scaler)
        model, label_encoder, feature_columns, scaler = self.model_loader.get_artifacts(
            exercise_type
        )

        service = ExerciseEvaluatorService(
            exercise_type  = exercise_type,
            model          = model,
            label_encoder  = label_encoder,
            feature_columns= feature_columns,
            scaler         = scaler,
        )

        session_id = str(uuid.uuid4())

        async with self._lock:
            self._sessions[session_id]      = service
            self._user_ids[session_id]      = user_id
            self._db_session_ids[session_id] = None  # set later via set_db_session_id
            self._last_activity[session_id] = time.monotonic()

        return session_id

    async def set_db_session_id(self, session_id: str, db_session_id: int) -> None:
        """Simpan mapping UUID session -> DB row ID (dipanggil setelah INSERT di /session/start)."""
        async with self._lock:
            if session_id in self._db_session_ids:
                self._db_session_ids[session_id] = db_session_id

    async def get_session(self, session_id: str) -> ExerciseEvaluatorService:
        """
        Ambil service untuk session_id yang aktif.

        Raises:
            KeyError: jika sesi tidak ditemukan atau sudah expired.
        """
        async with self._lock:
            if session_id not in self._sessions:
                raise KeyError(f"Session '{session_id}' not found or expired.")
            return self._sessions[session_id]

    async def touch_session(self, session_id: str) -> None:
        """
        Perbarui timestamp last-activity agar sesi tidak di-expire cleanup_loop.
        Dipanggil setiap frame di WebSocket handler.
        Tidak raise jika sesi tidak ada (client mungkin sudah disconnect).
        """
        async with self._lock:
            if session_id in self._last_activity:
                self._last_activity[session_id] = time.monotonic()

    async def delete_session(self, session_id: str) -> Dict[str, Any]:
        """
        Hapus sesi secara eksplisit dan kembalikan statistik workout.
        Dipanggil dari REST endpoint /session/end.
        """
        async with self._lock:
            service       = self._sessions.pop(session_id, None)
            user_id       = self._user_ids.pop(session_id, "")
            db_session_id = self._db_session_ids.pop(session_id, None)
            self._last_activity.pop(session_id, None)

        if service is not None:
            accuracy = (
                round(service.correct_reps / service.rep_count * 100, 1)
                if service.rep_count > 0 else 0.0
            )
            distribution = dict(Counter(service.predictions))
            distribution.pop('correct', None)
            distribution.pop('uncertain', None)

            return {
                "status":             "session_ended",
                "total_reps":         service.rep_count,
                "correct_reps":       service.correct_reps,
                "accuracy":           accuracy,
                "exercise_type":      service.exercise_type,
                "user_id":            user_id,
                "db_session_id":      db_session_id,
                "error_distribution": distribution,
            }
        return {"status": "error", "message": "not_found"}

    async def cleanup_loop(self) -> None:
        """
        Coroutine background: setiap 60 detik cek dan hapus sesi yang TTL-nya
        habis. Dipanggil dari lifespan sebagai asyncio.Task.

        Kenapa 60 detik? Cukup responsif untuk TTL 5 menit,
        tidak membebani lock di setiap detik.
        """
        while True:
            try:
                await asyncio.sleep(60)
                await self._expire_stale_sessions()
            except asyncio.CancelledError:
                # Task dibatalkan saat shutdown — keluar dengan bersih.
                break
            except Exception as exc:
                # Jangan crash loop karena 1 siklus gagal.
                print(f"[SessionManager] cleanup_loop error (non-fatal): {exc}")

    async def shutdown(self) -> None:
        """
        Pembersihan saat API shutdown. Hapus semua sesi aktif.
        Dipanggil dari lifespan after yield.
        """
        async with self._lock:
            count = len(self._sessions)
            self._sessions.clear()
            self._user_ids.clear()
            self._db_session_ids.clear()
            self._last_activity.clear()

        if count:
            print(f"[SessionManager] shutdown: cleared {count} active session(s).")

    # ------------------------------------------------------------------
    # INTERNAL HELPERS
    # ------------------------------------------------------------------

    async def _expire_stale_sessions(self) -> None:
        """Hapus sesi yang tidak aktif melebihi TTL."""
        now = time.monotonic()
        expired: list[str] = []

        async with self._lock:
            for sid, last in self._last_activity.items():
                if (now - last) > self._ttl:
                    expired.append(sid)

            for sid in expired:
                self._sessions.pop(sid, None)
                self._user_ids.pop(sid, None)
                self._db_session_ids.pop(sid, None)
                self._last_activity.pop(sid, None)

        if expired:
            print(
                f"[SessionManager] TTL cleanup: removed {len(expired)} "
                f"stale session(s): {expired}"
            )