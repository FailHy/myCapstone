import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.getcwd(), '../myproject')))
from sqlalchemy import text
from backend.core.database import SessionLocal
from backend.api.main import app

def clean():
    db = SessionLocal()
    try:
        # Drop columns added earlier
        cols_to_drop = ["total_reps", "correct_reps", "accuracy", "exercise_type"]
        for col in cols_to_drop:
            try:
                db.execute(text(f"ALTER TABLE training_sessions DROP COLUMN IF EXISTS {col};"))
            except Exception as e:
                print(f"Skipping {col}: {e}")
        db.commit()
        print("Dropped temporary columns.")

        # Seed exercises
        from models.exercise import Exercise
        ex1 = db.query(Exercise).filter(Exercise.name == "biceps").first()
        if not ex1:
            db.add(Exercise(name="biceps", category="Strength", description="Biceps Curl"))
        ex2 = db.query(Exercise).filter(Exercise.name == "triceps").first()
        if not ex2:
            db.add(Exercise(name="triceps", category="Strength", description="Triceps Extension"))
        db.commit()
        print("Seeded exercises.")
    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    clean()
