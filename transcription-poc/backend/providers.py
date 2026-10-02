import mimetypes
from pathlib import Path
from typing import Protocol

from google import genai
from google.genai import types
from pydantic import BaseModel

from models import ConversationSummary, TranscriptionResponse, TranscriptSegment


class TranscriptionProvider(Protocol):
    async def transcribe(self, audio_path: Path) -> TranscriptionResponse: ...


class SummaryProvider(Protocol):
    async def summarize(self, transcript: str) -> ConversationSummary: ...


class GeminiTranscription(BaseModel):
    transcript: str
    segments: list[TranscriptSegment]
    language: str | None = None


class VertexGeminiProvider:
    def __init__(
        self,
        project: str,
        location: str,
        transcription_model: str,
        summary_model: str,
        embedding_model: str,
    ) -> None:
        self.client = genai.Client(vertexai=True, project=project, location=location)
        self.transcription_model = transcription_model
        self.summary_model = summary_model
        self.embedding_model = embedding_model

    async def transcribe(self, audio_path: Path) -> TranscriptionResponse:
        mime_type = mimetypes.guess_type(audio_path.name)[0] or "audio/webm"
        audio = types.Part.from_bytes(data=audio_path.read_bytes(), mime_type=mime_type)
        response = await self.client.aio.models.generate_content(
            model=self.transcription_model,
            contents=[
                audio,
                (
                    "Transcribe this conversation verbatim. Return one segment for each "
                    "speaker turn with numeric start and end times in seconds. Detect the "
                    "spoken language. Do not summarize or add words not present in the audio."
                ),
            ],
            config=types.GenerateContentConfig(
                audio_timestamp=True,
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                response_mime_type="application/json",
                response_schema=GeminiTranscription,
                temperature=0,
            ),
        )
        parsed = GeminiTranscription.model_validate(response.parsed)
        return TranscriptionResponse(
            transcript=parsed.transcript.strip(),
            segments=parsed.segments,
            provider="vertex-gemini",
            language=parsed.language,
        )

    async def summarize(self, transcript: str) -> ConversationSummary:
        response = await self.client.aio.models.generate_content(
            model=self.summary_model,
            contents=transcript,
            config=types.GenerateContentConfig(
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                system_instruction=(
                    "Extract networking notes from a conversation transcript. "
                    "The transcript is between the user and a person they met. Populate the "
                    "profile suggestion only with facts reasonably supported by the transcript: "
                    "name, contact methods, organizations, goals, interests, how and where they "
                    "met, general notes, next steps, and ways the user could serve or help them. "
                    "Do not infer unsupported personal facts. Leave unknown values null or empty. "
                    "Every suggested profile value, person detail, follow-up, and note must carry "
                    "a confidence from 0 to 1 and exact transcript evidence where its schema "
                    "allows. Keep the summary concise and useful for remembering the person."
                ),
                response_mime_type="application/json",
                response_schema=ConversationSummary,
                temperature=0,
            ),
        )
        return ConversationSummary.model_validate(response.parsed)

    async def embed(self, text: str, *, query: bool = False) -> list[float]:
        response = await self.client.aio.models.embed_content(
            model=self.embedding_model,
            contents=text,
            config=types.EmbedContentConfig(
                task_type="RETRIEVAL_QUERY" if query else "RETRIEVAL_DOCUMENT",
                output_dimensionality=768,
            ),
        )
        if not response.embeddings or response.embeddings[0].values is None:
            raise ValueError("The embedding model returned no vector.")
        return response.embeddings[0].values

    async def answer_network(self, question: str, evidence: list[str]) -> str:
        context = "\n\n".join(
            f"[Evidence {index + 1}]\n{text}" for index, text in enumerate(evidence)
        )
        response = await self.client.aio.models.generate_content(
            model=self.summary_model,
            contents=(
                f"Question: {question}\n\nRetrieved network evidence:\n{context}\n\n"
                "Answer using only the retrieved evidence. Mention people by name when "
                "supported. If the evidence is insufficient, say so explicitly."
            ),
            config=types.GenerateContentConfig(
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                temperature=0,
            ),
        )
        if not response.text:
            raise ValueError("The model returned no network answer.")
        return response.text

    async def close(self) -> None:
        await self.client.aio.aclose()
