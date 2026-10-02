"""Drop-in OpenAI Agents API client for the Orbit chat backend.

The backend can keep one OrbitAgent per conversation and stream reply()
into the same shape the Flutter app already expects: chunks of assistant text.

No HTTP server lives here. Import OrbitAgent from the route that owns chat.
"""

from __future__ import annotations

import os
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

from openai import OpenAI

from .prompts import (
    FIND_EVENTS_TASK,
    INSTRUCTIONS,
    MODEL,
    REASONING_EFFORT,
    SUGGESTED_PROMPTS,
)

_KEY_NAMES = ("OPENAI_API_KEY", "openai_api")


@dataclass
class SearchLocation:
    """Bias web search toward a place. Override this from the user's city."""

    city: str = "Provo"
    region: str = "Utah"
    country: str = "US"
    timezone: str = "America/Denver"

    @property
    def label(self) -> str:
        return f"{self.city}, {self.region}"


def load_api_key() -> str:
    """Read the key from the environment or the repo .env. Never log the value."""
    for name in _KEY_NAMES:
        value = os.environ.get(name)
        if value and value.strip():
            return value.strip().strip('"').strip("'")

    for path in (Path.cwd() / ".env", Path(__file__).resolve().parents[1] / ".env"):
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            if name.strip() in _KEY_NAMES and value.strip():
                return value.strip().strip('"').strip("'")

    raise RuntimeError("No OpenAI API key found. Set OPENAI_API_KEY or openai_api in .env.")


def suggested_prompts() -> list[str]:
    return list(SUGGESTED_PROMPTS)


class OrbitAgent:
    """One Agents API session. Reuse the instance for follow-up messages."""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        instructions: str = INSTRUCTIONS,
        location: SearchLocation | None = None,
        model: str = MODEL,
        reasoning_effort: str = REASONING_EFFORT,
        client: OpenAI | None = None,
    ) -> None:
        self.instructions = instructions
        self.location = location or SearchLocation()
        self.model = model
        self.reasoning_effort = reasoning_effort
        self.session_id: str | None = None
        self.client = client or OpenAI(api_key=api_key or load_api_key(), timeout=300.0)

    def reply(self, history: list[dict], *, context: str | None = None) -> Iterator[str]:
        """Stream the assistant reply for the latest user message in history.

        history items match the Flutter ChatMessage json: {role, text}.
        The session remembers earlier turns, so later calls only send the
        newest user message.
        """
        user_turns = [item for item in history if item.get("role") == "user" and str(item.get("text", "")).strip()]
        if not user_turns:
            raise ValueError("history needs a user message")

        latest = str(user_turns[-1]["text"]).strip()
        if self.session_id is None and len(history) > 1:
            earlier = "\n".join(
                f"{item.get('role', 'user')}: {item.get('text', '')}" for item in history[:-1]
            )
            latest = f"Conversation so far:\n{earlier}\n\nLatest message:\n{latest}"
        yield from self.send(latest, context=None if self.session_id else context)

    def send(self, text: str, *, context: str | None = None) -> Iterator[str]:
        """Stream one user message. Creates the session on the first call."""
        message = self._prepare(text)
        if context and context.strip() and self.session_id is None:
            message = f"The user's network, for context:\n{context.strip()}\n\n{message}"
        if self.session_id is None:
            yield from self._start(message)
            return
        yield from self._continue(message)

    def close(self) -> None:
        """Delete the hosted session. Safe to call more than once."""
        if not self.session_id:
            return
        session_id = self.session_id
        self.session_id = None
        self.client.beta.agents.sessions.delete(session_id)

    def _prepare(self, text: str) -> str:
        if _is_find_events(text):
            return f"{text.strip()}\n\n{FIND_EVENTS_TASK.format(place=self.location.label)}"
        return text.strip()

    def _agent(self) -> dict:
        return {
            "model": self.model,
            "instructions": self.instructions,
            "reasoning": {"effort": self.reasoning_effort},
            "tools": [
                {
                    "type": "web_search",
                    "mode": "live",
                    "context_size": "medium",
                    "location": {
                        "country": self.location.country,
                        "region": self.location.region,
                        "city": self.location.city,
                        "timezone": self.location.timezone,
                    },
                }
            ],
        }

    def _start(self, message: str) -> Iterator[str]:
        # environment.type "none": answer and search the web, no code sandbox.
        with self.client.beta.agents.sessions.create(
            agent=self._agent(),
            environment={"type": "none"},
            input=message,
            stream=True,
        ) as events:
            yield from self._consume(events)

    def _continue(self, message: str) -> Iterator[str]:
        assert self.session_id is not None
        # Open the stream first so early events are not missed.
        with self.client.beta.agents.sessions.events.stream(self.session_id) as events:
            self.client.beta.agents.sessions.events.create(
                self.session_id,
                idempotency_key=str(uuid.uuid4()),
                events=[
                    {
                        "type": "agent.session.input.message",
                        "input": [
                            {
                                "role": "user",
                                "content": [{"type": "input_text", "text": message}],
                            }
                        ],
                    }
                ],
            )
            yield from self._consume(events)

    def _consume(self, events) -> Iterator[str]:
        seen: dict[tuple[str, int], str] = {}
        current_item: str | None = None
        for event in events:
            session_id = getattr(event, "session_id", None)
            if session_id:
                self.session_id = session_id
            elif getattr(event, "type", None) == "agent.session.created":
                created = getattr(event, "session", None)
                if created is not None and getattr(created, "id", None):
                    self.session_id = created.id

            event_type = getattr(event, "type", "")
            if event_type == "agent.session.turn.output_text.delta":
                piece = _new_text(seen, event.item_id, event.content_index, event.delta, append=True)
                if piece:
                    if current_item not in (None, event.item_id):
                        piece = "\n\n" + piece
                    current_item = event.item_id
                    yield piece
            elif event_type == "agent.session.turn.output_text.done":
                piece = _new_text(seen, event.item_id, event.content_index, event.text, append=False)
                if piece:
                    if current_item not in (None, event.item_id):
                        piece = "\n\n" + piece
                    current_item = event.item_id
                    yield piece
            elif event_type == "agent.session.turn.completed":
                if getattr(event.turn, "subagent_id", None) is None:
                    return
            elif event_type == "agent.session.turn.failed":
                if getattr(event.turn, "subagent_id", None) is None:
                    raise RuntimeError(f"Agent turn failed: {_turn_error(event)}")
            elif event_type == "agent.session.turn.cancelled":
                if getattr(event.turn, "subagent_id", None) is None:
                    raise RuntimeError("Agent turn was cancelled")
            elif event_type in {"agent.session.failed", "agent.session.environment.failed"}:
                raise RuntimeError(f"Agent session failed: {event_type}")
            elif event_type == "error":
                message = getattr(getattr(event, "error", None), "message", None) or event_type
                raise RuntimeError(message)
        if not seen:
            raise RuntimeError("Stream closed before the agent finished.")


def _is_find_events(text: str) -> bool:
    normalized = " ".join(text.lower().replace("?", "").split())
    return normalized in {"find events near me", "find events nearby"}


def _new_text(seen: dict[tuple[str, int], str], item_id: str, content_index: int, text: str, *, append: bool) -> str:
    key = (item_id, content_index)
    have = seen.get(key, "")
    if append:
        seen[key] = have + text
        return text
    if text.startswith(have):
        extra = text[len(have) :]
        seen[key] = text
        return extra
    if not have:
        seen[key] = text
        return text
    return ""


def _turn_error(event) -> str:
    turn = getattr(event, "turn", None)
    error = getattr(turn, "error", None)
    return getattr(error, "message", None) or "unknown error"
