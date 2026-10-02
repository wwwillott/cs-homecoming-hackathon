import asyncio
from typing import cast
from uuid import UUID, uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from database.models import TranscriptionSessionStatus
from database.session import get_session
from main import Settings, create_app
from models import (
    ConversationSummary,
    Evidence,
    PersonProfileSuggestion,
    SuggestedText,
)
from transcription_store import (
    create_or_resume_session,
    mark_session,
    persist_final_segment,
)

TEST_DATABASE_URL = "postgresql+psycopg://network:network@localhost:5432/network_test"


def database_client() -> TestClient:
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    app = create_app(Settings(google_cloud_project=None))

    async def override_session():  # type: ignore[no-untyped-def]
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    return TestClient(app)


class FakeNetworkProvider:
    embedding_model = "fake-embedding"

    async def summarize(self, transcript: str) -> ConversationSummary:
        return ConversationSummary(
            summary="Met Maya and discussed robotics.",
            connection_points=["Robotics"],
            profile_suggestion=PersonProfileSuggestion(
                interests=[
                    SuggestedText(
                        value="Robotics",
                        confidence=0.98,
                        evidence=[Evidence(excerpt="I enjoy robotics.")],
                    )
                ],
                next_steps=[
                    SuggestedText(
                        value="Send the club demo",
                        confidence=0.95,
                        evidence=[Evidence(excerpt="Send me the club demo.")],
                    )
                ],
            ),
        )

    async def embed(self, text: str, *, query: bool = False) -> list[float]:
        value = 0.2 if query else 0.1
        return [value] * 768

    async def answer_network(self, question: str, evidence: list[str]) -> str:
        return f"Maya is relevant based on {len(evidence)} approved record(s)."


async def seed_completed_session(user_id: UUID) -> UUID:
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with factory() as db:
            transcription_session = await create_or_resume_session(db, user_id)
            await persist_final_segment(
                db,
                transcription_session.id,
                sequence=1,
                text="I enjoy robotics.",
                start_seconds=0,
                end_seconds=2,
            )
            await persist_final_segment(
                db,
                transcription_session.id,
                sequence=2,
                text="Send me the club demo.",
                start_seconds=2,
                end_seconds=4,
            )
            await mark_session(
                db,
                transcription_session.id,
                TranscriptionSessionStatus.COMPLETED,
            )
            return transcription_session.id
    finally:
        await engine.dispose()


def test_people_connections_and_user_isolation() -> None:
    user_id = str(uuid4())
    other_user_id = str(uuid4())
    headers = {"X-User-Id": user_id}

    with database_client() as client:
        maya = client.post(
            "/api/people",
            headers=headers,
            json={
                "name": "Maya",
                "contact_methods": [
                    {
                        "kind": "email",
                        "value": "maya@example.com",
                        "is_primary": True,
                    }
                ],
                "organizations": [{"name": "Robotics Club", "kind": "group", "role": "Lead"}],
                "interests": ["Robotics"],
            },
        )
        leo = client.post(
            "/api/people",
            headers=headers,
            json={"name": "Leo", "goals": ["Build warehouse robots"]},
        )
        assert maya.status_code == 201
        assert leo.status_code == 201

        connection = client.post(
            "/api/connections",
            headers=headers,
            json={
                "person_a_id": maya.json()["id"],
                "person_b_id": leo.json()["id"],
                "label": "Met at conference",
            },
        )
        assert connection.status_code == 201

        network = client.get("/api/network", headers=headers)
        assert network.status_code == 200
        assert len(network.json()["nodes"]) == 2
        assert len(network.json()["edges"]) == 1

        isolated = client.get("/api/people", headers={"X-User-Id": other_user_id})
        assert isolated.status_code == 200
        assert isolated.json() == []


def test_conversation_approval_persists_and_indexes_profile() -> None:
    headers = {"X-User-Id": str(uuid4())}

    with database_client() as client:
        cast(FastAPI, client.app).state.summary_provider = FakeNetworkProvider()
        person = client.post("/api/people", headers=headers, json={"name": "Maya"})
        assert person.status_code == 201

        conversation = client.post(
            "/api/conversations",
            headers=headers,
            json={
                "person_id": person.json()["id"],
                "transcript": "I enjoy robotics. Send me the club demo.",
                "provider": "browser-whisper",
            },
        )
        assert conversation.status_code == 201
        summary = conversation.json()["summary"]
        assert summary["profile_suggestion"]["interests"][0]["value"] == "Robotics"

        approved = client.post(
            f"/api/suggestions/{conversation.json()['suggestion_id']}/approve",
            headers=headers,
            json={"profile": summary["profile_suggestion"]},
        )
        assert approved.status_code == 200
        assert approved.json()["interests"] == ["Robotics"]

        answer = client.post(
            "/api/network/ask",
            headers=headers,
            json={"question": "Who should I ask about robotics?"},
        )
        assert answer.status_code == 200
        assert answer.json()["citations"][0]["person_name"] == "Maya"


def test_completed_streaming_session_promotes_canonical_transcript() -> None:
    user_id = uuid4()
    headers = {"X-User-Id": str(user_id)}

    with database_client() as client:
        cast(FastAPI, client.app).state.summary_provider = FakeNetworkProvider()
        person = client.post("/api/people", headers=headers, json={"name": "Maya"})
        assert person.status_code == 201

        async def seed_session() -> UUID:
            engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
            factory = async_sessionmaker(engine, expire_on_commit=False)
            try:
                async with factory() as db:
                    transcription_session = await create_or_resume_session(
                        db,
                        user_id,
                        person_id=UUID(person.json()["id"]),
                    )
                    await persist_final_segment(
                        db,
                        transcription_session.id,
                        sequence=1,
                        text="I enjoy robotics.",
                        start_seconds=0,
                        end_seconds=2,
                    )
                    await persist_final_segment(
                        db,
                        transcription_session.id,
                        sequence=2,
                        text="Send me the club demo.",
                        start_seconds=2,
                        end_seconds=4,
                    )
                    await mark_session(
                        db,
                        transcription_session.id,
                        TranscriptionSessionStatus.COMPLETED,
                    )
                    return transcription_session.id
            finally:
                await engine.dispose()

        session_id = asyncio.run(seed_session())
        conversation = client.post(
            "/api/conversations",
            headers=headers,
            json={
                "person_id": person.json()["id"],
                "transcription_session_id": str(session_id),
            },
        )

        assert conversation.status_code == 201
        assert conversation.json()["transcript"] == ("I enjoy robotics. Send me the club demo.")


def test_flutter_recap_draft_and_commit_flow() -> None:
    user_id = uuid4()
    headers = {"X-User-Id": str(user_id)}

    with database_client() as client:
        cast(FastAPI, client.app).state.summary_provider = FakeNetworkProvider()
        session_id = asyncio.run(seed_completed_session(user_id))

        draft = client.post(
            f"/api/transcription-sessions/{session_id}/draft",
            headers=headers,
        )
        assert draft.status_code == 200
        assert draft.json()["sessionId"] == str(session_id)
        assert draft.json()["transcript"] == ("I enjoy robotics. Send me the club demo.")

        committed = client.post(
            f"/api/transcription-sessions/{session_id}/commit",
            headers=headers,
            json={
                "contact": {
                    "name": "Maya",
                    "company": "Robotics Club",
                    "title": "Lead",
                    "email": "maya@example.com",
                    "strength": 8,
                    "tags": ["Robotics"],
                    "notes": "Send the club demo.",
                    "howICanHelp": "Share the demo.",
                }
            },
        )
        assert committed.status_code == 200
        person = client.get(
            f"/api/people/{committed.json()['person_id']}",
            headers=headers,
        )
        assert person.status_code == 200
        assert person.json()["name"] == "Maya"
        assert person.json()["organizations"][0]["name"] == "Robotics Club"
