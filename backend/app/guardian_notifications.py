"""Optional, consented WhatsApp notification adapter for an urgent support request."""

from __future__ import annotations

import base64
import re
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


_E164 = re.compile(r"^\+[1-9]\d{7,14}$")


def send_guardian_support_request(config: dict[str, Any], *, phone: str | None, patient_name: str) -> str:
    """Send a deliberately minimal message and return a non-secret status.

    This adapter is intentionally best-effort: the clinical alert is committed
    before this function runs. Production WhatsApp use also needs an opted-in
    guardian and an approved Twilio template where required by WhatsApp.
    """

    account_sid = str(config.get("TWILIO_ACCOUNT_SID") or "").strip()
    auth_token = str(config.get("TWILIO_AUTH_TOKEN") or "").strip()
    sender = str(config.get("TWILIO_WHATSAPP_FROM") or "").strip()
    if not account_sid or not auth_token or not sender:
        return "not_configured"
    if not sender.startswith("whatsapp:+") or not _E164.fullmatch(sender.removeprefix("whatsapp:")):
        return "failed"
    if not phone or not _E164.fullmatch(phone.strip()):
        return "failed"

    message = (
        f"MaatriWatch: {patient_name} requested urgent support. "
        "Please contact them now and follow the agreed care plan."
    )
    payload = urlencode({"From": sender, "To": f"whatsapp:{phone.strip()}", "Body": message}).encode()
    authorization = base64.b64encode(f"{account_sid}:{auth_token}".encode()).decode()
    req = Request(
        f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json",
        data=payload,
        headers={"Authorization": f"Basic {authorization}", "Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=int(config.get("TWILIO_TIMEOUT_SECONDS", 10))) as response:
            return "sent" if 200 <= response.status < 300 else "failed"
    except (HTTPError, URLError, TimeoutError, ValueError):
        return "failed"
