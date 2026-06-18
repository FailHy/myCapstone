from fastapi import APIRouter, Depends, HTTPException, status, Body
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import timedelta
from jose import JWTError, jwt

from backend.core.database import get_db
from backend.core.security import hash_password, verify_password, create_access_token
from backend.core.config import settings

# --- PERBAIKAN IMPORT ---
# PASTIKAN BARIS INI DIAKTIFKAN KEMBALI (sesuaikan path-nya jika berbeda)
from models.user import User  
from backend.api.schemas import UserCreate, UserLogin, Token, UserResponse
# ------------------------

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

# Deklarasi skema pengamanan menggunakan Bearer Token
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register_user(
    user: UserCreate = Body(...), 
    db: Session = Depends(get_db)
):
    """
    Endpoint untuk mendaftarkan user baru.
    """
    # Gunakan Model User (kapital), dan bandingkan kolom DB dengan data request
    db_user = db.query(User).filter(User.email == user.email).first()
    
    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email sudah terdaftar"
        )
    
    hashed_pwd = hash_password(user.password)

    new_user = User(
        name=user.name,
        email=user.email,
        password_hash=hashed_pwd
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user) 
    
    return new_user

@router.post("/login", response_model=Token)
def login_user(
    user_credentials: UserLogin = Body(...), 
    db: Session = Depends(get_db)
):
    """
    Endpoint untuk login dan mendapatkan JWT Token.
    """
    db_user = db.query(User).filter(User.email == user_credentials.email).first()

    if not db_user or not verify_password(user_credentials.password, db_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email atau password salah",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(db_user.user_id)}, expires_delta=access_token_expires
    )
    
    return {"access_token": access_token, "token_type": "bearer"}

@router.get("/me", response_model=UserResponse)
def get_current_user_profile(
    token: str = Depends(oauth2_scheme), 
    db: Session = Depends(get_db)
):
    """
    Endpoint untuk mengambil profil user yang sedang login menggunakan JWT Token.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token tidak valid atau sudah kadaluarsa",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    try:
        # Decode token yang dikirim dari Flutter
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
        
    # Cari user di database berdasarkan user_id
    user = db.query(User).filter(User.user_id == int(user_id)).first()
    if user is None:
        raise credentials_exception
        
    return user