"""Authenticated, non-diagnostic MaatriWatch support assistant.

The endpoint is deliberately stateless: it does not persist prompts or model
answers in the clinical database. It is supplementary education only and is
not a replacement for the clinician messaging workflow.
"""

from __future__ import annotations

import json
import threading
import time
from collections import defaultdict, deque
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from flask import Blueprint, abort, current_app, g, jsonify, request

from .auth import require_firebase_user
from .db import get_db
from .patient import _patient_for_actor


ai_chat_bp = Blueprint("ai_chat", __name__)

_LOCK = threading.Lock()
_REQUESTS: dict[str, deque[float]] = defaultdict(deque)
_URGENT_TERMS = (
    "suicide",
    "kill myself",
    "harm myself",
    "harm my baby",
    "chest pain",
    "trouble breathing",
    "cannot breathe",
    "heavy bleeding",
    "soaking a pad",
    "fainted",
    "unconscious",
)
_SYSTEM_INSTRUCTIONS = """You are MaatriCare, a supportive maternal-care education assistant.
Use calm, plain language. You are not a doctor and do not diagnose, prescribe,
interpret tests, calculate blood pressure, or decide whether a wearable reading is safe.
For symptoms, medicines, test results, or concerning wearable readings, encourage the
person to contact their assigned care team. For emergencies, self-harm thoughts,
heavy bleeding, chest pain, trouble breathing, fainting, or feeling unsafe, tell them to
seek emergency help immediately and not wait for chat. Keep answers brief, practical,
and do not claim to access their clinical record or live watch data."""


def _message_input(body: object) -> str:
    if not isinstance(body, dict):
        abort(400, description="A JSON request body is required")
    message = str(body.get("message", "")).strip()
    if not message:
        abort(400, description="message is required")
    if len(message) > 800:
        abort(400, description="message must not exceed 800 characters")
    return message


def _needs_urgent_help(message: str) -> bool:
    text = message.lower()
    return any(term in text for term in _URGENT_TERMS)


def _allow_request(actor_id: str, *, limit: int, window_seconds: int) -> bool:
    now = time.monotonic()
    with _LOCK:
        recent = _REQUESTS[actor_id]
        while recent and recent[0] <= now - window_seconds:
            recent.popleft()
        if len(recent) >= limit:
            return False
        recent.append(now)
        return True


def _output_text(value: object) -> str:
    if not isinstance(value, dict):
        return ""
    output = value.get("output")
    if not isinstance(output, list):
        return ""
    parts: list[str] = []
    for item in output:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if isinstance(content, dict) and content.get("type") == "output_text":
                text = content.get("text")
                if isinstance(text, str):
                    parts.append(text.strip())
    return "\n".join(part for part in parts if part).strip()


def _request_openai_answer(message: str) -> str:
    config = current_app.config
    key = str(config.get("OPENAI_API_KEY") or "").strip()
    if not key:
        abort(503, description="The MaatriCare assistant is not configured yet")
    body = json.dumps(
        {
            "model": config["OPENAI_CHAT_MODEL"],
            "instructions": _SYSTEM_INSTRUCTIONS,
            "input": message,
            "max_output_tokens": 350,
            "store": False,
        }
    ).encode("utf-8")
    api_request = Request(
        "https://api.openai.com/v1/responses",
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(api_request, timeout=config["OPENAI_CHAT_TIMEOUT_SECONDS"]) as response:
            result = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        current_app.logger.warning("MaatriCare API request failed with status %s", error.code)
        abort(503, description="The MaatriCare assistant is temporarily unavailable")
    except (URLError, TimeoutError, ValueError):
        current_app.logger.warning("MaatriCare API request could not be completed")
        abort(503, description="The MaatriCare assistant is temporarily unavailable")
    answer = _output_text(result)
    if not answer:
        abort(502, description="The MaatriCare assistant returned no answer")
    return answer[:2500]


@ai_chat_bp.post("/patient/assistant")
@require_firebase_user
def assistant_reply():
    message = _message_input(request.get_json(silent=True))
    # Confirm this actor owns an active patient record, but do not add their
    # profile, laboratory values, or telemetry to the model request.
    with get_db().cursor() as cursor:
        _patient_for_actor(cursor)
    if _needs_urgent_help(message):
        return jsonify(
            {
                "answer": "Please seek emergency help now and do not wait for an app reply. Contact local emergency services, go to the nearest emergency department, or ask someone you trust to stay with you.",
                "urgent": True,
                "source": "safety_response",
            }
        )
    if not _allow_request(
        str(g.actor["id"]),
        limit=current_app.config["OPENAI_CHAT_MAX_REQUESTS"],
        window_seconds=current_app.config["OPENAI_CHAT_WINDOW_SECONDS"],
    ):
        abort(429, description="Please wait before sending another assistant message")
    return jsonify(
        {
            "answer": _request_openai_answer(message),
            "urgent": False,
            "source": "maatricare_assistant",
        }
    )
