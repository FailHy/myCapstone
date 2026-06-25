import sys
import os

# Append the myproject directory so that backend imports work
sys.path.append(os.path.abspath(os.path.join(os.getcwd(), '../myproject')))

from sqlalchemy import text
from backend.core.database import SessionLocal

def upgrade():
    db = SessionLocal()
    try:
        # Check existing columns
        result = db.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='training_sessions';"))
        existing_columns = [row[0] for row in result.fetchall()]
        print(f"Existing columns: {existing_columns}")
        
        columns_to_add = []
        if 'total_reps' not in existing_columns:
            columns_to_add.append("ADD COLUMN total_reps INTEGER NOT NULL DEFAULT 0")
        if 'correct_reps' not in existing_columns:
            columns_to_add.append("ADD COLUMN correct_reps INTEGER NOT NULL DEFAULT 0")
        if 'accuracy' not in existing_columns:
            columns_to_add.append("ADD COLUMN accuracy DOUBLE PRECISION NOT NULL DEFAULT 0.0")
            
        if columns_to_add:
            alter_query = f"ALTER TABLE training_sessions {', '.join(columns_to_add)};"
            print(f"Running: {alter_query}")
            db.execute(text(alter_query))
            db.commit()
            print("Successfully added missing columns.")
        else:
            print("All columns are already present.")
            
    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    upgrade()
