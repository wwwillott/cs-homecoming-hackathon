from pathlib import Path

from fastapi.testclient import TestClient

from main import Settings, create_app
from models import (
    ConversationSummary,
    Evidence,
    FollowUp,
    SuggestedNote,
    TranscriptionResponse,
    TranscriptSegment,
)


class FakeTranscriptionProvider:
    received_path: Path | None = None

    async def transcribe(self, audio_path: Path) -> TranscriptionResponse:
        assert audio_path.exists()
        self.received_path = audio_path
        return TranscriptionResponse(
            transcript="We both enjoy robotics.",
            segments=[
                TranscriptSegment(
                    start_seconds=0,
                    end_seconds=2.5,
                    text="We both enjoy robotics.",
                )
            ],
            provider="fake",
            language="en",
        )


class FakeSummaryProvider:
    async def summarize(self, transcript: str) -> ConversationSummary:
        return ConversationSummary(
            summary="The pair connected over robotics.",
            connection_points=["Robotics"],
            follow_ups=[
                FollowUp(
                    action="Share the robotics club link.",
                    owner="user",
                    evidence=[Evidence(excerpt="I'll send you the robotics club link.")],
                )
            ],
            suggested_notes=[
                SuggestedNote(
                    text="Interested in robotics.",
                    evidence=[Evidence(excerpt="I really enjoy robotics.")],
                )
            ],
        )


def test_health_and_unconfigured_capabilities() -> None:
    app = create_app(Settings(google_cloud_project=None))
    with TestClient(app) as client:
        assert client.get("/api/health").json() == {"status": "ok"}
        assert client.get("/api/capabilities").json() == {
            "cloud_transcription": False,
            "summarization": False,
            "max_upload_mb": 15,
        }


def test_transcription_normalizes_response_and_removes_temporary_file() -> None:
    app = create_app(Settings(google_cloud_project=None))
    provider = FakeTranscriptionProvider()

    with TestClient(app) as client:
        app.state.transcription_provider = provider
        response = client.post(
            "/api/transcriptions",
            files={"audio": ("conversation.webm", b"audio bytes", "audio/webm")},
        )

    assert response.status_code == 200
    assert response.json()["transcript"] == "We both enjoy robotics."
    assert response.json()["provider"] == "fake"
    assert provider.received_path is not None
    assert not provider.received_path.exists()


def test_empty_upload_is_rejected() -> None:
    app = create_app(Settings(google_cloud_project=None))
    with TestClient(app) as client:
        app.state.transcription_provider = FakeTranscriptionProvider()
        response = client.post(
            "/api/transcriptions",
            files={"audio": ("conversation.webm", b"", "audio/webm")},
        )

    assert response.status_code == 400
    assert response.json()["detail"] == "The audio upload is empty."


def test_summary_returns_structured_notes() -> None:
    app = create_app(Settings(google_cloud_project=None))
    with TestClient(app) as client:
        app.state.summary_provider = FakeSummaryProvider()
        response = client.post(
            "/api/summaries",
            json={"transcript": "I really enjoy robotics. I'll send you the robotics club link."},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["connection_points"] == ["Robotics"]
    assert body["follow_ups"][0]["owner"] == "user"
    assert body["suggested_notes"][0]["evidence"][0]["excerpt"] == ("I really enjoy robotics.")


def test_blank_summary_is_rejected() -> None:
    app = create_app(Settings(google_cloud_project=None))
    with TestClient(app) as client:
        app.state.summary_provider = FakeSummaryProvider()
        response = client.post("/api/summaries", json={"transcript": "   "})

    assert response.status_code == 422
