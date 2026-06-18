from datetime import datetime, timedelta
from typing import Optional
from jose import jwt
import bcrypt
from backend.core.config import settings

def hash_password(password: str) -> str:
    """Mengubah password plaintext menjadi hash"""
    # bcrypt butuh format bytes, jadi kita encode dulu
    pwd_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed_password = bcrypt.hashpw(pwd_bytes, salt)
    return hashed_password.decode('utf-8') # Kembalikan sebagai string untuk disimpan di DB

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Mengecek apakah password plaintext cocok dengan hash di database"""
    password_bytes = plain_password.encode('utf-8')
    hashed_password_bytes = hashed_password.encode('utf-8')
    return bcrypt.checkpw(password_bytes, hashed_password_bytes)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Membuat JWT Access Token baru"""
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire})
    
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt