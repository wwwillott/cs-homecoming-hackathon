"""Drop-in OpenAI Agents API client for the Orbit chat backend.

The backend can keep one OrbitAgent per conversation and stream reply()
into the same shape the Flutter app already expects: chunks of assistant text.

No HTTP server lives here. Import OrbitAgent from the route that owns chat.
"""

from __future__ import annotations

import os
import re
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


_STATE_TIMEZONES = {
    "al": "America/Chicago",
    "alabama": "America/Chicago",
    "ak": "America/Anchorage",
    "alaska": "America/Anchorage",
    "az": "America/Phoenix",
    "arizona": "America/Phoenix",
    "ar": "America/Chicago",
    "arkansas": "America/Chicago",
    "ca": "America/Los_Angeles",
    "california": "America/Los_Angeles",
    "co": "America/Denver",
    "colorado": "America/Denver",
    "ct": "America/New_York",
    "connecticut": "America/New_York",
    "de": "America/New_York",
    "delaware": "America/New_York",
    "fl": "America/New_York",
    "florida": "America/New_York",
    "ga": "America/New_York",
    "georgia": "America/New_York",
    "hi": "Pacific/Honolulu",
    "hawaii": "Pacific/Honolulu",
    "id": "America/Boise",
    "idaho": "America/Boise",
    "il": "America/Chicago",
    "illinois": "America/Chicago",
    "in": "America/Indiana/Indianapolis",
    "indiana": "America/Indiana/Indianapolis",
    "ia": "America/Chicago",
    "iowa": "America/Chicago",
    "ks": "America/Chicago",
    "kansas": "America/Chicago",
    "ky": "America/New_York",
    "kentucky": "America/New_York",
    "la": "America/Chicago",
    "louisiana": "America/Chicago",
    "me": "America/New_York",
    "maine": "America/New_York",
    "md": "America/New_York",
    "maryland": "America/New_York",
    "ma": "America/New_York",
    "massachusetts": "America/New_York",
    "mi": "America/Detroit",
    "michigan": "America/Detroit",
    "mn": "America/Chicago",
    "minnesota": "America/Chicago",
    "ms": "America/Chicago",
    "mississippi": "America/Chicago",
    "mo": "America/Chicago",
    "missouri": "America/Chicago",
    "mt": "America/Denver",
    "montana": "America/Denver",
    "ne": "America/Chicago",
    "nebraska": "America/Chicago",
    "nv": "America/Los_Angeles",
    "nevada": "America/Los_Angeles",
    "nh": "America/New_York",
    "new hampshire": "America/New_York",
    "nj": "America/New_York",
    "new jersey": "America/New_York",
    "nm": "America/Denver",
    "new mexico": "America/Denver",
    "ny": "America/New_York",
    "new york": "America/New_York",
    "nc": "America/New_York",
    "north carolina": "America/New_York",
    "nd": "America/Chicago",
    "north dakota": "America/Chicago",
    "oh": "America/New_York",
    "ohio": "America/New_York",
    "ok": "America/Chicago",
    "oklahoma": "America/Chicago",
    "or": "America/Los_Angeles",
    "oregon": "America/Los_Angeles",
    "pa": "America/New_York",
    "pennsylvania": "America/New_York",
    "ri": "America/New_York",
    "rhode island": "America/New_York",
    "sc": "America/New_York",
    "south carolina": "America/New_York",
    "sd": "America/Chicago",
    "south dakota": "America/Chicago",
    "tn": "America/Chicago",
    "tennessee": "America/Chicago",
    "tx": "America/Chicago",
    "texas": "America/Chicago",
    "ut": "America/Denver",
    "utah": "America/Denver",
    "vt": "America/New_York",
    "vermont": "America/New_York",
    "va": "America/New_York",
    "virginia": "America/New_York",
    "wa": "America/Los_Angeles",
    "washington": "America/Los_Angeles",
    "wv": "America/New_York",
    "west virginia": "America/New_York",
    "wi": "America/Chicago",
    "wisconsin": "America/Chicago",
    "wy": "America/Denver",
    "wyoming": "America/Denver",
    "dc": "America/New_York",
    "district of columbia": "America/New_York",
}


@dataclass
class SearchLocation:
    """Bias web search toward the city and state saved in Settings."""

    city: str = ""
    region: str = ""
    country: str = ""
    timezone: str = ""
    university: str = ""

    @classmethod
    def from_place(cls, *, city: str = "", state: str = "", university: str = "") -> SearchLocation:
        city = city.strip()
        state = state.strip()
        university = university.strip()
        timezone = _STATE_TIMEZONES.get(state.casefold(), "")
        country = "US" if city or state else ""
        return cls(
            city=city,
            region=state,
            country=country,
            timezone=timezone,
            university=university,
        )

    @property
    def label(self) -> str:
        where = ", ".join(part for part in (self.city, self.region) if part)
        if self.university and where:
            return f"{where}, around {self.university}"
        if self.university:
            return self.university
        return where or "them"

    def context_line(self) -> str:
        notes: list[str] = []
        where = ", ".join(part for part in (self.city, self.region) if part)
        if where:
            notes.append(f"The user is in {where}.")
        if self.university:
            notes.append(f"Their university is {self.university}.")
        if not notes:
            return "The user has not set a city, state, or university in Settings."
        return " ".join(notes)

    def web_search_location(self) -> dict[str, str]:
        fields = {
            "country": self.country,
            "region": self.region,
            "city": self.city,
            "timezone": self.timezone,
        }
        return {key: value for key, value in fields.items() if value}


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
        self.location = location if location is not None else SearchLocation()
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
        if self.session_id is None:
            message = f"{self.location.context_line()}\n\n{message}"
            if context and context.strip():
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
        place = _find_events_place(text)
        if place is not None:
            task = FIND_EVENTS_TASK.format(place=place or self.location.label)
            if self.location.university:
                task += f" Prefer events at or near {self.location.university}."
            return f"{text.strip()}\n\n{task}"
        if _is_find_alumni(text):
            school = self.location.university or "their university"
            return (
                f"{text.strip()}\n\n"
                f"Search the live web for alumni of {school} near {self.location.label}. "
                "Use the company or field named in the request. "
                "Return real people, alumni groups, or company pages with source links."
            )
        return text.strip()

    def _agent(self) -> dict:
        web_search: dict[str, object] = {
            "type": "web_search",
            "mode": "live",
            "context_size": "medium",
        }
        place = self.location.web_search_location()
        if place:
            web_search["location"] = place
        return {
            "model": self.model,
            "instructions": self.instructions,
            "reasoning": {"effort": self.reasoning_effort},
            "tools": [web_search],
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


def _find_events_place(text: str) -> str | None:
    """The place named in an events request, "" for near me, or None if it isn't one."""
    normalized = " ".join(text.replace("?", "").split())
    if normalized.lower() == "find events nearby":
        return ""
    match = re.fullmatch(r"find events near (.+)", normalized, flags=re.IGNORECASE)
    if match is None:
        return None
    place = match.group(1).strip(" .")
    return "" if place.lower() == "me" else place


def _is_find_alumni(text: str) -> bool:
    return text.lower().lstrip().startswith("find alumni")


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
