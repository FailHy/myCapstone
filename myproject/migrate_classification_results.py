"""
migrate_classification_results.py
===================================
Migration script: tambahkan kolom baru ke tabel classification_results
yang sudah ada di PostgreSQL.

Kolom yang ditambahkan:
  - rep_number          INTEGER   — urutan rep dalam sesi
  - smoothed_prediction VARCHAR   — hasil majority vote smoother
  - feedback_text       VARCHAR   — string feedback untuk user
  - features            JSONB     — 12 fitur biomekanik per rep

Script ini IDEMPOTENT: aman dijalankan berulang kali.
Jika kolom sudah ada, perintah ALTER TABLE akan dilewati.

Cara jalankan:
    cd /path/to/myproject
    source venv/bin/activate
    python migrate_classification_results.py
"""

import sys
import os

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from sqlalchemy import text
from backend.core.database import SessionLocal


COLUMNS_TO_ADD = [
    # (nama_kolom, SQL_type, SQL_definition)
    ("rep_number",          "integer",          "INTEGER"),
    ("smoothed_prediction", "character varying", "VARCHAR(50)"),
    ("feedback_text",       "character varying", "VARCHAR(500)"),
    ("features",            "jsonb",             "JSONB"),
]


def run_migration():
    db = SessionLocal()
    try:
        print("=== Migration: classification_results ===\n")

        # Ambil kolom yang sudah ada
        result = db.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name = 'classification_results';"
        ))
        existing = {row[0] for row in result.fetchall()}
        print(f"Kolom yang sudah ada: {sorted(existing)}\n")

        added = []
        skipped = []

        for col_name, _, sql_type in COLUMNS_TO_ADD:
            if col_name in existing:
                skipped.append(col_name)
                print(f"  SKIP  : {col_name} — sudah ada")
            else:
                alter_sql = (
                    f"ALTER TABLE classification_results "
                    f"ADD COLUMN {col_name} {sql_type};"
                )
                print(f"  ADD   : {alter_sql}")
                db.execute(text(alter_sql))
                added.append(col_name)

        if added:
            db.commit()
            print(f"\n✅ Berhasil menambahkan {len(added)} kolom: {added}")
        else:
            print(f"\n✅ Tidak ada kolom baru — semua sudah ada ({skipped})")

    except Exception as e:
        db.rollback()
        print(f"\n❌ Migration gagal: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    run_migration()
