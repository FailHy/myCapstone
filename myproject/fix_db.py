import sys
import os

# Append the myproject directory so that backend imports work
sys.path.append(os.path.abspath(os.path.join(os.getcwd(), '../myproject')))

from sqlalchemy import text
from backend.core.database import SessionLocal

def upgrade():
    db = SessionLocal()
    try:
        # Check if the column exists to avoid errors on multiple runs
        result = db.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='training_sessions' AND column_name='exercise_type';"))
        if not result.fetchone():
            print("Adding 'exercise_type' column to 'training_sessions' table...")
            db.execute(text("ALTER TABLE training_sessions ADD COLUMN exercise_type VARCHAR(50) NOT NULL DEFAULT 'biceps';"))
            db.execute(text("ALTER TABLE training_sessions ALTER COLUMN exercise_type DROP DEFAULT;"))
            db.commit()
            print("Successfully added column.")
        else:
            print("Column 'exercise_type' already exists.")
    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    upgrade()
