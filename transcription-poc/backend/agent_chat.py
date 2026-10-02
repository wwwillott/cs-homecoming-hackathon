"""OpenAI Agents API chat for the in-app assistant."""

from __future__ import annotations

import json
import logging
import sys
import threading
from collections.abc import Iterator
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from chatbot.orbit_agent import OrbitAgent, load_api_key  # noqa: E402
from chatbot.prompts import SUGGESTED_PROMPTS  # noqa: E402

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api")


class AssistantMessage(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=8_000)


class AssistantChatRequest(BaseModel):
    messages: list[AssistantMessage] = Field(min_length=1, max_length=40)
    session_id: str | None = Field(default=None, max_length=200)
    context: str | None = Field(default=None, max_length=6_000)


class AssistantPromptsResponse(BaseModel):
    prompts: list[str]


class AgentRegistry:
    """Keeps one Agents API session per chat until the app asks to delete it."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key
        self._agents: dict[str, OrbitAgent] = {}
        self._turns: dict[int, threading.Lock] = {}
        self._guard = threading.Lock()

    def open(self, session_id: str | None) -> OrbitAgent:
        if session_id:
            with self._guard:
                existing = self._agents.get(session_id)
            if existing is not None:
                return existing
        return OrbitAgent(api_key=self._api_key)

    def turn_lock(self, agent: OrbitAgent) -> threading.Lock:
        with self._guard:
            return self._turns.setdefault(id(agent), threading.Lock())

    def remember(self, agent: OrbitAgent) -> None:
        if not agent.session_id:
            return
        with self._guard:
            self._agents[agent.session_id] = agent

    def close(self, session_id: str) -> None:
        with self._guard:
            agent = self._agents.pop(session_id, None)
            if agent is not None:
                self._turns.pop(id(agent), None)
        if agent is not None:
            agent.close()

    def close_all(self) -> None:
        with self._guard:
            agents = list(self._agents.values())
            self._agents.clear()
            self._turns.clear()
        for agent in agents:
            try:
                agent.close()
            except Exception:
                logger.exception("failed to delete an agent session")


def build_registry(explicit_key: str | None) -> AgentRegistry | None:
    key = (explicit_key or "").strip()
    if not key:
        try:
            key = load_api_key()
        except RuntimeError:
            return None
    return AgentRegistry(key)


def _sse(payload: dict[str, object]) -> bytes:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n".encode()


def _registry(request: Request) -> AgentRegistry:
    registry = getattr(request.app.state, "agent_registry", None)
    if not isinstance(registry, AgentRegistry):
        raise HTTPException(
            status_code=503,
            detail="The AI assistant is not configured. Set openai_api in the repo .env.",
        )
    return registry


@router.get("/assistant/prompts", response_model=AssistantPromptsResponse)
async def assistant_prompts() -> AssistantPromptsResponse:
    return AssistantPromptsResponse(prompts=list(SUGGESTED_PROMPTS))


@router.post("/assistant/chat")
async def assistant_chat(payload: AssistantChatRequest, request: Request) -> StreamingResponse:
    registry = _registry(request)
    history = [message.model_dump() for message in payload.messages]

    def generate() -> Iterator[bytes]:
        agent = registry.open(payload.session_id)
        with registry.turn_lock(agent):
            try:
                for chunk in agent.reply(history, context=payload.context):
                    registry.remember(agent)
                    if chunk:
                        yield _sse({"delta": chunk, "session_id": agent.session_id})
                registry.remember(agent)
                yield _sse({"done": True, "session_id": agent.session_id})
            except Exception:
                logger.exception("assistant turn failed")
                registry.remember(agent)
                yield _sse({"error": "The assistant could not finish that reply."})

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.delete("/assistant/sessions/{session_id}", status_code=204)
async def delete_assistant_session(session_id: str, request: Request) -> None:
    registry = getattr(request.app.state, "agent_registry", None)
    if isinstance(registry, AgentRegistry):
        registry.close(session_id)
