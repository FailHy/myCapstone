"""
migrate_v2_fix_constraints.py
==============================
Migration v2 — Perbaiki CHECK constraint pada classification_results.

MASALAH YANG DIPERBAIKI:
  1. classification_results_classification_status_check
     Constraint lama hanya mengizinkan: correct | incorrect | partial
     Backend mengirim nilai aktual dari XGBoost: body_swing, elbow_swing,
     not_full_up, too_fast, correct, invalid, unknown
     Akibatnya: semua INSERT non-correct gagal secara senyap (di-rollback
     tanpa crash), hanya row 'correct' yang tersimpan di DB.

  2. failure_type VARCHAR(50) → VARCHAR(100)
     ORM model mendefinisikan String(100) tapi DB column saat ini VARCHAR(50).
     Diperpanjang agar sesuai ORM model dan tidak truncate feedback_text panjang.

IDEMPOTENT: aman dijalankan berulang kali.

Cara jalankan:
    cd myproject
    source venv/bin/activate
    python migrate_v2_fix_constraints.py
"""

import sys
import os

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from sqlalchemy import text
from backend.core.database import SessionLocal

# Label yang diizinkan — harus mencakup semua nilai yang bisa dikirim backend
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
]

CONSTRAINT_NAME = "classification_results_classification_status_check"


def run_migration():
    db = SessionLocal()
    try:
        print("=== Migration v2: Fix classification_results constraints ===\n")

        # -----------------------------------------------------------------------
        # 1. Cek apakah constraint lama masih ada
        # -----------------------------------------------------------------------
        result = db.execute(text("""
            SELECT check_clause
            FROM information_schema.check_constraints
            WHERE constraint_name = :name
        """), {"name": CONSTRAINT_NAME})
        existing_clause = result.scalar()

        if existing_clause:
            print(f"  [FOUND] Constraint lama:\n    {existing_clause}")
            print(f"  [DROP]  Menghapus constraint lama...")
            db.execute(text(f"""
                ALTER TABLE classification_results
                DROP CONSTRAINT IF EXISTS {CONSTRAINT_NAME}
            """))
            print(f"  [OK]    Constraint lama dihapus.\n")
        else:
            print(f"  [SKIP]  Constraint lama tidak ditemukan (sudah dihapus sebelumnya).\n")

        # -----------------------------------------------------------------------
        # 2. Tambahkan constraint baru yang mencakup semua label XGBoost
        # -----------------------------------------------------------------------
        values_sql = ", ".join(f"'{v}'" for v in ALLOWED_STATUSES)
        new_constraint_sql = f"""
            ALTER TABLE classification_results
            ADD CONSTRAINT {CONSTRAINT_NAME}
            CHECK (classification_status IN ({values_sql}))
        """
        print(f"  [ADD]   Menambahkan constraint baru...")
        print(f"          Allows: {ALLOWED_STATUSES}")
        db.execute(text(new_constraint_sql))
        print(f"  [OK]    Constraint baru berhasil ditambahkan.\n")

        # -----------------------------------------------------------------------
        # 3. Perbaiki failure_type: VARCHAR(50) → VARCHAR(100)
        # -----------------------------------------------------------------------
        result2 = db.execute(text("""
            SELECT character_maximum_length
            FROM information_schema.columns
            WHERE table_name = 'classification_results'
              AND column_name = 'failure_type'
        """))
        current_len = result2.scalar()

        if current_len is not None and current_len < 100:
            print(f"  [ALTER] failure_type: VARCHAR({current_len}) → VARCHAR(100)")
            db.execute(text("""
                ALTER TABLE classification_results
                ALTER COLUMN failure_type TYPE VARCHAR(100)
            """))
            print(f"  [OK]    failure_type diperlebar ke VARCHAR(100).\n")
        else:
            print(f"  [SKIP]  failure_type sudah VARCHAR({current_len or '?'}) — tidak perlu diubah.\n")

        # -----------------------------------------------------------------------
        # 4. Commit semua perubahan
        # -----------------------------------------------------------------------
        db.commit()
        print("✅ Migration v2 selesai — semua perubahan berhasil di-commit.\n")

        # -----------------------------------------------------------------------
        # 5. Verifikasi akhir
        # -----------------------------------------------------------------------
        print("=== Verifikasi akhir ===")
        r_verify = db.execute(text("""
            SELECT constraint_name, check_clause
            FROM information_schema.check_constraints
            WHERE constraint_name = :name
        """), {"name": CONSTRAINT_NAME})
        row = r_verify.fetchone()
        if row:
            print(f"  Constraint name  : {row[0]}")
            print(f"  Constraint clause: {row[1]}")
        else:
            print("  ⚠️  Constraint tidak ditemukan setelah migration!")

    except Exception as e:
        db.rollback()
        print(f"\n❌ Migration gagal: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    run_migration()
