import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.getcwd(), '../myproject')))
from sqlalchemy import text
from backend.core.database import SessionLocal

def check():
    db = SessionLocal()
    try:
        result = db.execute(text("SELECT table_name FROM information_schema.tables WHERE table_schema='public';"))
        tables = [row[0] for row in result.fetchall()]
        print(f"Tables in DB: {tables}")
        
        if 'training_sessions' in tables:
            res = db.execute(text("SELECT column_name, data_type FROM information_schema.columns WHERE table_name='training_sessions';"))
            cols = [f"{row[0]} ({row[1]})" for row in res.fetchall()]
            print(f"Columns in training_sessions: {cols}")
    finally:
        db.close()

if __name__ == "__main__":
    check()
