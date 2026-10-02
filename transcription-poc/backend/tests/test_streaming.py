import asyncio
from typing import Any, cast
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from google.cloud.speech_v2.types import cloud_speech
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

import streaming_transcription
from database.models import TranscriptionSessionStatus, User
from main import Settings, create_app
from streaming_transcription import (
    AudioChunk,
    GoogleSpeechStreamer,
    TranscriptEvent,
    decode_audio_frame,
    merge_transcript_delta,
)
from transcription_store import (
    canonical_transcript,
    create_or_resume_session,
    mark_session,
    persist_final_segment,
)

TEST_DATABASE_URL = "postgresql+psycopg://network:network@localhost:5432/network_test"


class FakeTransport:
    def close(self) -> None:
        return None


class FakeSpeechClient:
    transport = FakeTransport()

    async def streaming_recognize(self, requests: Any) -> Any:
        received = [request async for request in requests]
        assert received[0].streaming_config
        assert received[1].audio == b"\x00\x00" * 1_600

        async def responses() -> Any:
            yield cloud_speech.StreamingRecognizeResponse(
                results=[
                    cloud_speech.StreamingRecognitionResult(
                        alternatives=[
                            cloud_speech.SpeechRecognitionAlternative(
                                transcript="Hello there.",
                            )
                        ],
                        is_final=True,
                        result_end_offset={"seconds": 1},
                    )
                ]
            )

        return responses()


def test_pcm_frame_validation_and_sequence() -> None:
    frame = (42).to_bytes(4, "little") + b"\x00\x00" * 1_600
    assert decode_audio_frame(frame) == AudioChunk(42, b"\x00\x00" * 1_600)
    with pytest.raises(ValueError, match="complete 16-bit"):
        decode_audio_frame((1).to_bytes(4, "little") + b"\x00")


def test_rotation_overlap_deduplication() -> None:
    assert merge_transcript_delta("We discussed robotics", "robotics and school") == "and school"
    assert merge_transcript_delta("We discussed robotics.", "We discussed robotics.") == ""


@pytest.mark.asyncio
async def test_fake_stream_emits_protocol_events() -> None:
    queue: asyncio.Queue[AudioChunk] = asyncio.Queue()
    await queue.put(AudioChunk(7, b"\x00\x00" * 1_600))
    stopped = asyncio.Event()
    stopped.set()
    events: list[TranscriptEvent] = []
    streamer = GoogleSpeechStreamer(
        "test-project",
        client=cast(Any, FakeSpeechClient()),
    )

    async def emit(event: TranscriptEvent) -> None:
        events.append(event)

    await streamer.run(queue, stopped, emit)

    assert [event.type for event in events] == ["ack", "final", "complete"]
    assert events[0].sequence == 7
    assert events[1].text == "Hello there."


@pytest.mark.asyncio
async def test_segments_are_ordered_idempotent_and_resumable() -> None:
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    user_id = uuid4()
    try:
        async with factory() as db:
            db.add(User(id=user_id))
            await db.commit()
            transcription_session = await create_or_resume_session(db, user_id)
            session_id = transcription_session.id
            assert await persist_final_segment(
                db,
                session_id,
                sequence=2,
                text="second",
                start_seconds=1,
                end_seconds=2,
                provider_result_id="result-2",
            )
            assert await persist_final_segment(
                db,
                session_id,
                sequence=1,
                text="first",
                start_seconds=0,
                end_seconds=1,
                provider_result_id="result-1",
            )
            assert not await persist_final_segment(
                db,
                session_id,
                sequence=1,
                text="first",
                start_seconds=0,
                end_seconds=1,
                provider_result_id="result-1",
            )
            assert await canonical_transcript(db, session_id) == "first second"
            await mark_session(db, session_id, TranscriptionSessionStatus.INTERRUPTED)
            resumed = await create_or_resume_session(db, user_id, session_id=session_id)
            assert resumed.status == TranscriptionSessionStatus.ACTIVE
    finally:
        async with factory() as db:
            await db.execute(delete(User).where(User.id == user_id))
            await db.commit()
        await engine.dispose()


def test_websocket_event_protocol(monkeypatch: pytest.MonkeyPatch) -> None:
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)

    class FakeStreamer:
        def __init__(self, project_id: str, **_: Any) -> None:
            assert project_id == "test-project"

        async def run(
            self,
            audio_queue: asyncio.Queue[AudioChunk],
            stop_event: asyncio.Event,
            emit: Any,
        ) -> None:
            chunk = await audio_queue.get()
            await emit(TranscriptEvent(type="ack", sequence=chunk.sequence))
            await emit(
                TranscriptEvent(
                    type="final",
                    text="A test transcript.",
                    end_seconds=1,
                    provider_result_id="fake-result",
                )
            )
            await stop_event.wait()
            await emit(TranscriptEvent(type="complete", text="A test transcript."))

        async def close(self) -> None:
            return None

    monkeypatch.setattr(streaming_transcription, "GoogleSpeechStreamer", FakeStreamer)
    app = create_app(Settings(google_cloud_project="test-project"))
    with TestClient(app) as client:
        app.state.streaming_session_factory = factory
        with client.websocket_connect("/api/transcriptions/stream") as websocket:
            websocket.send_json({"type": "start"})
            ready = websocket.receive_json()
            websocket.send_bytes((3).to_bytes(4, "little") + b"\x00\x00" * 1_600)
            ack = websocket.receive_json()
            final = websocket.receive_json()
            websocket.send_json({"type": "stop"})
            complete = websocket.receive_json()

    assert ready["type"] == "ready"
    assert ready["session_id"]
    assert ack == {
        "type": "ack",
        "text": "",
        "start_seconds": 0,
        "end_seconds": 0,
        "sequence": 3,
    }
    assert final["type"] == "final"
    assert complete["type"] == "complete"
    asyncio.run(engine.dispose())
