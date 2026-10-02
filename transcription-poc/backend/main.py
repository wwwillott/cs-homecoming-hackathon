import os
import tempfile
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import cast

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google.auth.exceptions import GoogleAuthError
from google.genai.errors import APIError
from pydantic_settings import BaseSettings, SettingsConfigDict

from agent_chat import build_registry
from agent_chat import router as assistant_router
from database.session import AsyncSessionFactory
from models import (
    CapabilitiesResponse,
    ConversationSummary,
    SummaryRequest,
    TranscriptionResponse,
)
from auth import router as auth_router
from network_api import router as network_router
from providers import (
    SummaryProvider,
    TranscriptionProvider,
    VertexGeminiProvider,
)
from streaming_transcription import router as streaming_router


class Settings(BaseSettings):
    google_cloud_project: str | None = None
    google_cloud_location: str = "global"
    google_speech_location: str = "us"
    gemini_transcription_model: str = "gemini-3.5-flash"
    gemini_summary_model: str = "gemini-3.5-flash"
    gemini_embedding_model: str = "gemini-embedding-2"
    cors_origins: str = (
        "http://localhost:5173,http://127.0.0.1:5173,"
        "https://spruce.my,https://www.spruce.my,"
        "http://spruce.my,http://www.spruce.my,"
        "https://wwwillott.github.io"
    )
    cors_origin_regex: str | None = (
        r"https?://(localhost|127\.0\.0\.1)(:\d+)?"
        r"|https?://(www\.)?spruce\.my"
        r"|https://[\w-]+\.github\.io"
    )
    max_upload_mb: int = 15
    openai_api_key: str | None = None
    openai_api: str | None = None

    model_config = SettingsConfigDict(
        env_file=(
            *(
                (str(Path(__file__).resolve().parents[2] / ".env"),)
                if len(Path(__file__).resolve().parents) > 2
                else ()
            ),
            ".env",
        ),
        extra="ignore",
    )

    @property
    def agents_api_key(self) -> str | None:
        return self.openai_api_key or self.openai_api

    @property
    def parsed_cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


def create_app(settings: Settings | None = None) -> FastAPI:
    active_settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.settings = active_settings
        app.state.streaming_session_factory = AsyncSessionFactory
        provider: VertexGeminiProvider | None = None
        if active_settings.google_cloud_project:
            provider = VertexGeminiProvider(
                project=active_settings.google_cloud_project,
                location=active_settings.google_cloud_location,
                transcription_model=active_settings.gemini_transcription_model,
                summary_model=active_settings.gemini_summary_model,
                embedding_model=active_settings.gemini_embedding_model,
            )
        app.state.transcription_provider = provider
        app.state.summary_provider = provider
        app.state.agent_registry = build_registry(active_settings.agents_api_key)
        try:
            yield
        finally:
            registry = app.state.agent_registry
            if registry is not None:
                registry.close_all()
            if provider is not None:
                await provider.close()

    app = FastAPI(
        title="Network Conversation Transcription API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=active_settings.parsed_cors_origins,
        allow_origin_regex=active_settings.cors_origin_regex,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(auth_router)
    app.include_router(network_router)
    app.include_router(streaming_router)
    app.include_router(assistant_router)

    @app.get("/api/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/api/capabilities", response_model=CapabilitiesResponse)
    async def capabilities(request: Request) -> CapabilitiesResponse:
        return CapabilitiesResponse(
            cloud_transcription=request.app.state.transcription_provider is not None,
            summarization=request.app.state.summary_provider is not None,
            max_upload_mb=request.app.state.settings.max_upload_mb,
        )

    @app.post("/api/transcriptions", response_model=TranscriptionResponse)
    async def transcribe(
        request: Request,
        audio: UploadFile = File(...),
    ) -> TranscriptionResponse:
        provider = cast(TranscriptionProvider | None, request.app.state.transcription_provider)
        if provider is None:
            raise HTTPException(
                status_code=503,
                detail="Cloud transcription is not configured. Set GOOGLE_CLOUD_PROJECT.",
            )

        suffix = Path(audio.filename or "recording.webm").suffix or ".webm"
        path: Path | None = None
        total_bytes = 0
        max_bytes = request.app.state.settings.max_upload_mb * 1024 * 1024

        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temporary:
                path = Path(temporary.name)
                while chunk := await audio.read(1024 * 1024):
                    total_bytes += len(chunk)
                    if total_bytes > max_bytes:
                        limit = request.app.state.settings.max_upload_mb
                        raise HTTPException(
                            status_code=413,
                            detail=f"Audio exceeds the {limit} MB limit.",
                        )
                    temporary.write(chunk)

            if total_bytes == 0:
                raise HTTPException(status_code=400, detail="The audio upload is empty.")

            return await provider.transcribe(path)
        except HTTPException:
            raise
        except (APIError, GoogleAuthError, OSError, ValueError) as error:
            raise HTTPException(status_code=502, detail=f"Transcription failed: {error}") from error
        finally:
            await audio.close()
            if path is not None:
                path.unlink(missing_ok=True)

    @app.post("/api/summaries", response_model=ConversationSummary)
    async def summarize(request: Request, payload: SummaryRequest) -> ConversationSummary:
        provider = cast(SummaryProvider | None, request.app.state.summary_provider)
        if provider is None:
            raise HTTPException(
                status_code=503,
                detail="Summarization is not configured. Set GOOGLE_CLOUD_PROJECT.",
            )
        try:
            return await provider.summarize(payload.transcript)
        except (APIError, GoogleAuthError, ValueError) as error:
            raise HTTPException(status_code=502, detail=f"Summarization failed: {error}") from error

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host=os.getenv("HOST", "127.0.0.1"), port=8000, reload=True)
