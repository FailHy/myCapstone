"""
migrate_v3_add_uncertain.py
============================
Migration v3 — Tambahkan label 'uncertain' ke CHECK constraint
classification_results_classification_status_check.

MASALAH YANG DIPERBAIKI:
  Label 'uncertain' dapat muncul sebagai smoothed_prediction dari
  PredictionSmoother. Meskipun classification_status (raw prediction)
  saat ini tidak menghasilkan 'uncertain', constraint diperluas secara
  defensif untuk mencegah IntegrityError di masa depan.

  Evidence runtime (2026-07-09):
    IntegrityError: (psycopg2.errors.CheckViolation)
    Failing row contains (..., uncertain, ...)
    Constraint: classification_results_classification_status_check

IDEMPOTENT: aman dijalankan berulang kali.

Cara jalankan:
    cd myproject
    source venv/bin/activate
    python migrate_v3_add_uncertain.py
"""

import sys
import os

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from sqlalchemy import text
from backend.core.database import SessionLocal

CONSTRAINT_NAME = "classification_results_classification_status_check"

ALLOWED_STATUSES = [
    "correct",
    "incorrect",
    "partial",
    "body_swing",
    "elbow_swing",
    "not_full_up",
    "too_fast",
    "invalid",
    "unknown",
    "uncertain",   # ← ditambahkan v3
]


def run_migration():
    db = SessionLocal()
    try:
        print("=== Migration v3: Add 'uncertain' to CHECK constraint ===\n")

        # Cek clause constraint saat ini
        result = db.execute(text("""
            SELECT check_clause
            FROM information_schema.check_constraints
            WHERE constraint_name = :name
        """), {"name": CONSTRAINT_NAME})
        existing_clause = result.scalar()

        if existing_clause and "'uncertain'" in existing_clause:
            print("  [SKIP] 'uncertain' sudah ada di constraint. Tidak perlu diubah.")
            return

        if existing_clause:
            print(f"  [FOUND] Constraint saat ini:\n    {existing_clause}")
            db.execute(text(f"""
                ALTER TABLE classification_results
                DROP CONSTRAINT IF EXISTS {CONSTRAINT_NAME}
            """))
            print("  [DROP] Constraint lama dihapus.")
        else:
            print("  [INFO] Constraint tidak ditemukan, akan dibuat baru.")

        values_sql = ", ".join(f"'{v}'" for v in ALLOWED_STATUSES)
        db.execute(text(f"""
            ALTER TABLE classification_results
            ADD CONSTRAINT {CONSTRAINT_NAME}
            CHECK (classification_status IN ({values_sql}))
        """))
        print(f"  [ADD]  Constraint baru ditambahkan.")
        print(f"         Allows: {ALLOWED_STATUSES}")

        db.commit()
        print("\n✅ Migration v3 selesai.\n")

        # Verifikasi
        r = db.execute(text("""
            SELECT check_clause FROM information_schema.check_constraints
            WHERE constraint_name = :name
        """), {"name": CONSTRAINT_NAME})
        clause = r.scalar()
        print(f"=== Verifikasi ===\n  {clause}\n")

    except Exception as e:
        db.rollback()
        print(f"\n❌ Migration gagal: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    run_migration()
