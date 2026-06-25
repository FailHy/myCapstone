import os
from pathlib import Path

# --- FIX CRITICAL-04: Load .env file jika ada ---
# Cari .env di project root (dua level di atas backend/core/)
_env_path = Path(__file__).resolve().parents[2] / ".env"
if _env_path.exists():
    with open(_env_path) as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and not _line.startswith("#") and "=" in _line:
                _key, _, _val = _line.partition("=")
                os.environ.setdefault(_key.strip(), _val.strip())

_DEFAULT_SECRET = "CHANGE_ME_BEFORE_PRODUCTION"

class Settings:
    # SECRET_KEY harus di-set di .env — jangan hardcode di source code.
    # Buat .env di root project dengan isi: SECRET_KEY=<nilai acak>
    # Contoh generate: python -c "import secrets; print(secrets.token_hex(32))"
    SECRET_KEY: str = os.getenv("SECRET_KEY", _DEFAULT_SECRET)

    # Algoritma enkripsi JWT
    ALGORITHM: str = "HS256"

    # Masa berlaku token. 30 hari cukup untuk demo sidang.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", str(60 * 24 * 30)))

    # Konfigurasi Database PostgreSQL
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:capstone123@localhost:5432/capstone")

    def __post_init__(self):
        if self.SECRET_KEY == _DEFAULT_SECRET:
            import warnings
            warnings.warn(
                "SECRET_KEY menggunakan nilai default! Buat file .env di root project.",
                stacklevel=2
            )

settings = Settings()

# Tampilkan warning satu kali saat startup jika secret belum diset
if settings.SECRET_KEY == _DEFAULT_SECRET:
    import warnings
    warnings.warn(
        "[BiTri-AI] SECURITY WARNING: SECRET_KEY menggunakan nilai default. "
        "Buat file .env dan isi SECRET_KEY=<nilai acak dari secrets.token_hex(32)>.",
        UserWarning,
        stacklevel=1,
    )