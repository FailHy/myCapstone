import logging
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from backend.core.config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Engine dengan connection pool yang dikonfigurasi eksplisit.
#
# pool_size     : jumlah koneksi yang selalu dijaga hidup.
#                 5 cukup untuk demo sidang (1-3 user concurrent).
# max_overflow  : koneksi tambahan di atas pool_size saat spike.
# pool_timeout  : detik maksimal menunggu koneksi dari pool sebelum error.
# pool_recycle  : detik sebelum koneksi di-recycle (hindari stale connection
#                 setelah PostgreSQL memutus koneksi idle).
# pool_pre_ping : test koneksi sebelum dipakai (True = lebih aman untuk demo).
#
# FIX MEDIUM: tambahkan pool config eksplisit agar tidak pakai default
# SQLAlchemy yang terlalu generous untuk context demo/single-server.
# ---------------------------------------------------------------------------
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30,
    pool_recycle=1800,   # recycle setiap 30 menit
    pool_pre_ping=True,  # cek koneksi hidup sebelum dipakai
    echo=False,          # set True hanya untuk debug SQL query
)

# ---------------------------------------------------------------------------
# Session factory
# ---------------------------------------------------------------------------
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# ---------------------------------------------------------------------------
# Base class untuk ORM models
#
# FIX MEDIUM: sqlalchemy.ext.declarative.declarative_base() sudah deprecated
# sejak SQLAlchemy 2.0. Ganti dengan subclass DeclarativeBase dari
# sqlalchemy.orm (sudah available sejak SQLAlchemy 1.4+).
# ---------------------------------------------------------------------------
class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# Dependency FastAPI: satu DB session per request, selalu di-close setelah.
# ---------------------------------------------------------------------------
def get_db():
    """
    FastAPI dependency untuk mendapatkan SQLAlchemy session.
    Gunakan dengan: db: Session = Depends(get_db)
    """
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()