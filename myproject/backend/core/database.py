from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from backend.core.config import settings

# Inisialisasi engine SQLAlchemy
engine = create_engine(settings.DATABASE_URL)

# Membuat session class
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class untuk model SQLAlchemy
Base = declarative_base()

# Dependency untuk mendapatkan session database di setiap request FastAPI
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()