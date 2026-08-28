"""Apply only missing MaatriWatch schema phases to the configured Postgres DB.

This is intentionally small for the hackathon demo: it inspects the schema,
then applies 001 through 005 in order as needed. It never prints the
connection URL or values from .env.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from psycopg import connect
from psycopg.errors import OperationalError
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[1]
load_dotenv(ROOT_DIR / ".env")


def table_exists(cursor, table: str) -> bool:
    cursor.execute("SELECT to_regclass(%s) IS NOT NULL AS present", (f"public.{table}",))
    return bool(cursor.fetchone()["present"])


def column_exists(cursor, table: str, column: str) -> bool:
    cursor.execute(
        """SELECT EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = %s AND column_name = %s
           ) AS present""",
        (table, column),
    )
    return bool(cursor.fetchone()["present"])


def apply_file(connection, filename: str) -> None:
    sql = (ROOT_DIR / "db" / "migrations" / filename).read_text(encoding="utf-8")
    with connection.cursor() as cursor:
        cursor.execute(sql)
    connection.commit()
    print(f"Applied {filename}")


def main() -> int:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("DATABASE_URL is not set.", file=sys.stderr)
        return 1
    try:
        with connect(database_url, row_factory=dict_row) as connection:
            with connection.cursor() as cursor:
                initial_missing = not table_exists(cursor, "hospitals")
                phase_two_missing = not initial_missing and not column_exists(cursor, "vital_readings", "source_event_id")
                phase_three_missing = not initial_missing and not column_exists(cursor, "alerts", "updated_at")
                phase_four_missing = not initial_missing and not table_exists(cursor, "patient_consents")
                phase_five_missing = not initial_missing and not column_exists(cursor, "vital_readings", "ambient_temperature_c")
            if initial_missing:
                apply_file(connection, "001_initial_schema.sql")
                phase_two_missing = True
                phase_three_missing = True
                phase_four_missing = True
                phase_five_missing = True
            if phase_two_missing:
                apply_file(connection, "002_ingestion_alerting.sql")
            if phase_three_missing:
                apply_file(connection, "003_clinician_dashboard.sql")
            if phase_four_missing:
                apply_file(connection, "004_patient_safety_workflows.sql")
            if phase_five_missing:
                apply_file(connection, "005_environmental_context.sql")
    except OperationalError:
        print("Could not connect to Postgres. Check DATABASE_URL without printing it.", file=sys.stderr)
        return 1
    except Exception:
        print("Migration failed. Inspect the target schema before retrying.", file=sys.stderr)
        return 1
    print("MaatriWatch schema is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
