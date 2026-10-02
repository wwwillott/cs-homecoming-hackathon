import asyncio
import contextlib
import hashlib
import json
import os
import time
from collections import deque
from collections.abc import AsyncIterator, Awaitable, Callable
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from google.api_core.client_options import ClientOptions
from google.cloud import speech_v2
from google.cloud.speech_v2.types import cloud_speech

from database.models import TranscriptionSessionStatus
from transcription_store import (
    canonical_transcript,
    create_or_resume_session,
    mark_session,
    next_segment_sequence,
    persist_final_segment,
    record_gap,
)

MAX_AUDIO_BYTES = 25_000
DEFAULT_STREAM_SECONDS = 270
OVERLAP_CHUNKS = 10

router = APIRouter()


@dataclass(frozen=True)
class AudioChunk:
    sequence: int
    pcm: bytes


@dataclass(frozen=True)
class TranscriptEvent:
    type: str
    text: str = ""
    start_seconds: float = 0
    end_seconds: float = 0
    sequence: int | None = None
    message: str | None = None
    session_id: str | None = None
    provider_result_id: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            key: value
            for key, value in {
                "type": self.type,
                "text": self.text,
                "start_seconds": self.start_seconds,
                "end_seconds": self.end_seconds,
                "sequence": self.sequence,
                "message": self.message,
                "session_id": self.session_id,
                "provider_result_id": self.provider_result_id,
            }.items()
            if value is not None
        }


def merge_transcript_delta(committed: str, candidate: str) -> str:
    """Return only words not already committed at the rotation boundary."""
    candidate_words = candidate.strip().split()
    committed_words = committed.strip().split()
    if not candidate_words:
        return ""
    max_overlap = min(30, len(candidate_words), len(committed_words))
    for size in range(max_overlap, 0, -1):
        left = [word.casefold().strip(".,!?") for word in committed_words[-size:]]
        right = [word.casefold().strip(".,!?") for word in candidate_words[:size]]
        if left == right:
            return " ".join(candidate_words[size:]).strip()
    if candidate.strip().casefold() == committed.strip().casefold():
        return ""
    return candidate.strip()


class GoogleSpeechStreamer:
    def __init__(
        self,
        project_id: str,
        *,
        location: str = "global",
        language_code: str = "en-US",
        model: str = "chirp_3",
        stream_seconds: int = DEFAULT_STREAM_SECONDS,
        initial_committed: str = "",
        client: speech_v2.SpeechAsyncClient | None = None,
    ) -> None:
        self.project_id = project_id
        self.location = location
        self.language_code = language_code
        self.model = model
        self.stream_seconds = stream_seconds
        self.initial_committed = initial_committed
        self.client = client or speech_v2.SpeechAsyncClient(
            client_options=ClientOptions(
                api_endpoint=f"{location}-speech.googleapis.com",
                quota_project_id=project_id,
            )
        )

    def config_request(self) -> cloud_speech.StreamingRecognizeRequest:
        recognition_config = cloud_speech.RecognitionConfig(
            explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
                encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
                sample_rate_hertz=16_000,
                audio_channel_count=1,
            ),
            language_codes=[self.language_code],
            model=self.model,
            features=cloud_speech.RecognitionFeatures(
                enable_automatic_punctuation=True,
            ),
        )
        return cloud_speech.StreamingRecognizeRequest(
            recognizer=(f"projects/{self.project_id}/locations/{self.location}/recognizers/_"),
            streaming_config=cloud_speech.StreamingRecognitionConfig(
                config=recognition_config,
                streaming_features=cloud_speech.StreamingRecognitionFeatures(
                    interim_results=True,
                    enable_voice_activity_events=True,
                ),
            ),
        )

    async def run(
        self,
        audio_queue: asyncio.Queue[AudioChunk],
        stop_event: asyncio.Event,
        emit: Callable[[TranscriptEvent], Awaitable[None]],
    ) -> None:
        overlap: deque[AudioChunk] = deque(maxlen=OVERLAP_CHUNKS)
        committed = self.initial_committed
        last_final_end = 0.0
        total_audio_seconds = 0.0
        session_index = 0

        while not stop_event.is_set() or not audio_queue.empty():
            session_index += 1
            if session_index > 1:
                await emit(
                    TranscriptEvent(
                        type="reconnecting",
                        message="Rotating the cloud speech stream.",
                    )
                )
            replay = list(overlap)
            replay_seconds = sum(len(chunk.pcm) / 2 / 16_000 for chunk in replay)
            session_offset = max(0.0, total_audio_seconds - replay_seconds)
            session_started = time.monotonic()

            async def requests() -> AsyncIterator[cloud_speech.StreamingRecognizeRequest]:
                nonlocal total_audio_seconds
                yield self.config_request()
                for chunk in replay:
                    yield cloud_speech.StreamingRecognizeRequest(audio=chunk.pcm)

                while time.monotonic() - session_started < self.stream_seconds:
                    if stop_event.is_set() and audio_queue.empty():
                        return
                    try:
                        chunk = await asyncio.wait_for(audio_queue.get(), timeout=0.25)
                    except TimeoutError:
                        continue
                    overlap.append(chunk)
                    total_audio_seconds += len(chunk.pcm) / 2 / 16_000
                    yield cloud_speech.StreamingRecognizeRequest(audio=chunk.pcm)
                    await emit(TranscriptEvent(type="ack", sequence=chunk.sequence))

            responses = await self.client.streaming_recognize(requests=requests())
            async for response in responses:
                for result in response.results:
                    if not result.alternatives:
                        continue
                    text = result.alternatives[0].transcript.strip()
                    if not text:
                        continue
                    duration = result.result_end_offset
                    relative_end = duration.total_seconds()
                    end_seconds = session_offset + relative_end
                    if result.is_final:
                        delta = merge_transcript_delta(committed, text)
                        if not delta:
                            continue
                        committed = f"{committed} {delta}".strip()
                        result_id = hashlib.sha256(
                            f"{session_index}:{text}:{end_seconds:.3f}".encode()
                        ).hexdigest()
                        await emit(
                            TranscriptEvent(
                                type="final",
                                text=delta,
                                start_seconds=last_final_end,
                                end_seconds=end_seconds,
                                provider_result_id=result_id,
                            )
                        )
                        last_final_end = max(last_final_end, end_seconds)
                    else:
                        await emit(
                            TranscriptEvent(
                                type="interim",
                                text=text,
                                end_seconds=end_seconds,
                            )
                        )

        await emit(TranscriptEvent(type="complete", text=committed))

    async def close(self) -> None:
        result = self.client.transport.close()  # type: ignore[no-untyped-call]
        if result is not None:
            await result


def decode_audio_frame(data: bytes) -> AudioChunk:
    if len(data) < 5:
        raise ValueError("Audio frame must include a sequence and PCM payload.")
    sequence = int.from_bytes(data[:4], "little", signed=False)
    pcm = data[4:]
    if len(pcm) > MAX_AUDIO_BYTES:
        raise ValueError(f"Audio frame exceeds {MAX_AUDIO_BYTES} bytes.")
    if len(pcm) % 2:
        raise ValueError("LINEAR16 audio must contain complete 16-bit samples.")
    return AudioChunk(sequence=sequence, pcm=pcm)


@router.websocket("/api/transcriptions/stream")
async def stream_transcription(websocket: WebSocket) -> None:
    await websocket.accept()
    project_id = websocket.app.state.settings.google_cloud_project
    if not project_id:
        await websocket.send_json(
            TranscriptEvent(type="error", message="Google Cloud is not configured.").as_dict()
        )
        await websocket.close(code=1011)
        return

    session_factory = websocket.app.state.streaming_session_factory
    try:
        initial = await websocket.receive_json()
        if initial.get("type") != "start":
            raise ValueError("The first message must be a start event.")
        user_id = UUID(
            websocket.query_params.get("user_id")
            or os.getenv("DEVELOPMENT_USER_ID", "00000000-0000-0000-0000-000000000001")
        )
        requested_session_id = UUID(initial["session_id"]) if initial.get("session_id") else None
        person_id = UUID(initial["person_id"]) if initial.get("person_id") else None
        async with session_factory() as db:
            transcription_session = await create_or_resume_session(
                db,
                user_id,
                session_id=requested_session_id,
                person_id=person_id,
            )
            final_sequence = await next_segment_sequence(db, transcription_session.id)
            existing_transcript = await canonical_transcript(db, transcription_session.id)
    except (HTTPException, ValueError, KeyError, json.JSONDecodeError) as error:
        message = error.detail if isinstance(error, HTTPException) else str(error)
        await websocket.send_json(TranscriptEvent(type="error", message=message).as_dict())
        await websocket.close(code=1008)
        return

    audio_queue: asyncio.Queue[AudioChunk] = asyncio.Queue(maxsize=300)
    outgoing: asyncio.Queue[TranscriptEvent] = asyncio.Queue()
    stop_event = asyncio.Event()
    streamer = GoogleSpeechStreamer(
        project_id=project_id,
        location=websocket.app.state.settings.google_speech_location,
        initial_committed=existing_transcript,
    )

    async def emit(event: TranscriptEvent) -> None:
        nonlocal final_sequence
        if event.type == "final":
            async with session_factory() as db:
                inserted = await persist_final_segment(
                    db,
                    transcription_session.id,
                    sequence=final_sequence,
                    text=event.text,
                    start_seconds=event.start_seconds,
                    end_seconds=event.end_seconds,
                    provider_result_id=event.provider_result_id,
                )
            if inserted:
                final_sequence += 1
            else:
                return
        await outgoing.put(event)

    async def receive_audio() -> None:
        try:
            while not stop_event.is_set():
                message = await websocket.receive()
                if message["type"] == "websocket.disconnect":
                    stop_event.set()
                    return
                if data := message.get("bytes"):
                    await audio_queue.put(decode_audio_frame(data))
                    continue
                text = message.get("text")
                if text == "stop":
                    stop_event.set()
                    return
                if text:
                    payload = json.loads(text)
                    if payload.get("type") == "stop":
                        stop_event.set()
                        return
                    if payload.get("type") == "gap":
                        async with session_factory() as db:
                            await record_gap(
                                db,
                                transcription_session.id,
                                int(payload.get("count", 1)),
                            )
                        await outgoing.put(
                            TranscriptEvent(
                                type="gap",
                                message="Audio was dropped from the reconnect buffer.",
                            )
                        )
        except (WebSocketDisconnect, ValueError) as error:
            await outgoing.put(TranscriptEvent(type="error", message=str(error)))
            stop_event.set()

    await websocket.send_json(
        TranscriptEvent(
            type="ready",
            text=existing_transcript,
            session_id=str(transcription_session.id),
        ).as_dict()
    )
    receiver = asyncio.create_task(receive_audio())

    async def recognize() -> None:
        try:
            await streamer.run(audio_queue, stop_event, emit)
        except Exception as error:
            await outgoing.put(TranscriptEvent(type="error", message=str(error)))

    recognizer = asyncio.create_task(recognize())
    final_status = TranscriptionSessionStatus.INTERRUPTED
    try:
        while True:
            event = await outgoing.get()
            await websocket.send_json(event.as_dict())
            if event.type == "complete":
                final_status = TranscriptionSessionStatus.COMPLETED
                break
            if event.type == "error":
                final_status = TranscriptionSessionStatus.ERROR
                break
    except WebSocketDisconnect:
        stop_event.set()
    finally:
        stop_event.set()
        receiver.cancel()
        recognizer.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await receiver
        with contextlib.suppress(asyncio.CancelledError):
            await recognizer
        await streamer.close()
        async with session_factory() as db:
            await mark_session(db, transcription_session.id, final_status)
