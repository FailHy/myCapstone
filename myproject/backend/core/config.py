import os

class Settings:
    # SECRET_KEY sangat penting untuk sign JWT. 
    # Idealnya ini disimpan di file .env, tapi untuk skripsi kita hardcode defaultnya agar aman saat di-run.
    SECRET_KEY: str = os.getenv("SECRET_KEY", "bitri-ai-skripsi-super-secret-key-2024")
    
    # Algoritma enkripsi JWT
    ALGORITHM: str = "HS256"
    
    # Masa berlaku token. Kita set 30 hari (dalam menit) agar saat demo sidang tidak tiba-tiba logout.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30 
    
    # Konfigurasi Database PostgreSQL
    # Sesuaikan "postgres:password" dengan username dan password database lokalmu
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:capstone123@localhost:5432/capstone")

settings = Settings()