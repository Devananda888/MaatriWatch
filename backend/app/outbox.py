"""Durable Firebase projection delivery via a Postgres transactional outbox."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from flask import current_app
from psycopg.types.json import Jsonb

from .db import get_db
from .firebase import publish_realtime_projection


def enqueue_projection(cursor, *, topic: str, payload: dict, idempotency_key: str):
    """Queue a projection in the same transaction as the clinical state change."""
    cursor.execute(
        """INSERT INTO realtime_outbox (topic, payload, idempotency_key)
           VALUES (%s, %s, %s)
           ON CONFLICT (idempotency_key) DO UPDATE
           SET idempotency_key = EXCLUDED.idempotency_key
           RETURNING id""",
        (topic, Jsonb(payload), idempotency_key),
    )
    return cursor.fetchone()["id"]


def deliver_outbox_ids(outbox_ids: list) -> dict[str, int]:
    """Best-effort immediate delivery; failed messages remain durably pending."""
    if not outbox_ids:
        return {"delivered": 0, "pending": 0}
    connection = get_db()
    worker_id = f"request-{uuid4()}"
    claimed = _claim_specific(connection, outbox_ids, worker_id)
    delivered = 0
    for item in claimed:
        if _deliver_claimed(connection, item, worker_id):
            delivered += 1
    return {"delivered": delivered, "pending": _not_delivered_count(connection, outbox_ids)}


def deliver_pending_outbox(limit: int = 100) -> dict[str, int]:
    """Run from the Flask CLI or a separate process to retry Firebase delivery."""
    connection = get_db()
    worker_id = f"worker-{uuid4()}"
    claimed = _claim_next(connection, limit, worker_id)
    delivered = 0
    for item in claimed:
        if _deliver_claimed(connection, item, worker_id):
            delivered += 1
    return {"delivered": delivered, "pending": len(claimed) - delivered}


def _claim_specific(connection, outbox_ids: list, worker_id: str) -> list[dict]:
    with connection.cursor() as cursor:
        cursor.execute(
            """UPDATE realtime_outbox
               SET delivery_status = 'processing', locked_at = now(), locked_by = %s,
                   attempts = attempts + 1
               WHERE id = ANY(%s)
                 AND delivery_status = 'pending'
                 AND available_at <= now()
               RETURNING id, topic, payload, attempts""",
            (worker_id, outbox_ids),
        )
        rows = cursor.fetchall()
    connection.commit()
    return rows


def _claim_next(connection, limit: int, worker_id: str) -> list[dict]:
    # A worker may have died after claiming a row. A ten-minute lease makes it
    # retryable without allowing two healthy workers to deliver it together.
    with connection.cursor() as cursor:
        cursor.execute(
            """WITH candidates AS (
                   SELECT id
                   FROM realtime_outbox
                   WHERE (delivery_status = 'pending' AND available_at <= now())
                      OR (delivery_status = 'processing' AND locked_at < now() - interval '10 minutes')
                   ORDER BY available_at, created_at
                   FOR UPDATE SKIP LOCKED
                   LIMIT %s
               )
               UPDATE realtime_outbox outbox
               SET delivery_status = 'processing', locked_at = now(), locked_by = %s,
                   attempts = outbox.attempts + 1
               FROM candidates
               WHERE outbox.id = candidates.id
               RETURNING outbox.id, outbox.topic, outbox.payload, outbox.attempts""",
            (limit, worker_id),
        )
        rows = cursor.fetchall()
    connection.commit()
    return rows


def _not_delivered_count(connection, outbox_ids: list) -> int:
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT count(*) AS count
               FROM realtime_outbox
               WHERE id = ANY(%s) AND delivery_status <> 'delivered'""",
            (outbox_ids,),
        )
        return cursor.fetchone()["count"]


def _deliver_claimed(connection, item: dict, worker_id: str) -> bool:
    try:
        publish_realtime_projection(item["topic"], item["payload"])
    except Exception as error:  # Firebase/network failure must never lose the clinical event.
        current_app.logger.exception("Realtime projection delivery failed", extra={"outbox_id": str(item["id"])})
        retry_after = datetime.now(timezone.utc) + timedelta(seconds=_retry_delay(item["attempts"]))
        with connection.cursor() as cursor:
            cursor.execute(
                """UPDATE realtime_outbox
                   SET delivery_status = 'pending', locked_at = NULL, locked_by = NULL,
                       available_at = %s, last_error = %s
                   WHERE id = %s AND delivery_status = 'processing' AND locked_by = %s""",
                (retry_after, str(error)[:1000], item["id"], worker_id),
            )
        connection.commit()
        return False

    with connection.cursor() as cursor:
        cursor.execute(
            """UPDATE realtime_outbox
               SET delivery_status = 'delivered', delivered_at = now(), locked_at = NULL,
                   locked_by = NULL, last_error = NULL
               WHERE id = %s AND delivery_status = 'processing' AND locked_by = %s""",
            (item["id"], worker_id),
        )
    connection.commit()
    return True


def _retry_delay(attempts: int) -> int:
    return min(3600, 30 * (2 ** max(0, min(attempts - 1, 7))))
