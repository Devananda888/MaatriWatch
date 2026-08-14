"""Small process worker for durable Firebase RTDB projection retries."""

from __future__ import annotations

import os
import time

from . import create_app
from .outbox import deliver_pending_outbox


def main():
    app = create_app()
    poll_seconds = max(1, int(os.getenv("REALTIME_OUTBOX_POLL_SECONDS", "5")))
    batch_size = app.config["REALTIME_OUTBOX_BATCH_SIZE"]
    while True:
        with app.app_context():
            result = deliver_pending_outbox(batch_size)
            if result["delivered"] or result["pending"]:
                app.logger.info("Realtime outbox processed", extra=result)
        time.sleep(poll_seconds)


if __name__ == "__main__":
    main()
