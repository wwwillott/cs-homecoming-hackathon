# Conversation transcription proof of concept

This folder demonstrates the complete test flow:

1. Record microphone audio in a phone or desktop browser.
2. Stream 16 kHz mono PCM to Google Cloud Speech-to-Text and see live text.
3. Edit the transcript.
4. Save final segments to PostgreSQL and generate structured networking notes.

Streaming audio stays in memory and is never saved. The diagnostic cloud-file route
uses a temporary file while receiving the upload and deletes it before the request
completes.

## Components

- `test-client/`: deliberately minimal Vite/TypeScript test page.
- `test-client/src/transcription/local-transcriber.ts`: reusable browser-facing API.
- `test-client/src/transcription/local-whisper.worker.ts`: Transformers.js Whisper worker.
- `backend/`: FastAPI streaming, persistence, cloud fallback, and summary service.

The local path uses `onnx-community/whisper-tiny.en`. It prefers WebGPU and falls
back to WebAssembly. The first run downloads and caches model assets in the browser.
Tiny English is appropriate for proving the flow, not for final transcription quality.

## Start the backend

Requirements: Python 3.12+, [uv](https://docs.astral.sh/uv/), a Google Cloud project
with Vertex AI and Speech-to-Text enabled, and [Application Default Credentials](https://docs.cloud.google.com/docs/authentication/provide-credentials-adc).

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
gcloud services enable aiplatform.googleapis.com speech.googleapis.com \
  --project YOUR_PROJECT_ID

cd transcription-poc
docker compose up -d postgres

cd transcription-poc/backend
cp .env.example .env
# Set GOOGLE_CLOUD_PROJECT in .env
uv sync
uv run alembic upgrade head
uv run uvicorn main:app --reload
```

`GOOGLE_SPEECH_LOCATION=us` is the default because Chirp 3 is available in the
`us` and `eu` multi-regions, not the `global` location.

The API runs at `http://127.0.0.1:8000`. Interactive API documentation is available
at `http://127.0.0.1:8000/docs`.

The local database uses PostgreSQL with pgvector at
`postgresql://network:network@localhost:5432/network`. Development API requests
default to user `00000000-0000-0000-0000-000000000001`; pass another UUID in
`X-User-Id` to exercise network isolation. This header is intentionally a temporary
development identity, not production authentication.

Endpoints:

- `GET /api/health`
- `GET /api/capabilities`
- `POST /api/transcriptions` with multipart field `audio`
- `WS /api/transcriptions/stream` for live LINEAR16 audio and transcript events
- `POST /api/transcription-sessions/{id}/draft` to generate a Flutter review draft
- `POST /api/transcription-sessions/{id}/commit` to save the reviewed person and conversation
- `POST /api/summaries` with JSON `{ "transcript": "..." }`
- `/api/people` for people and nested profile data
- `/api/connections` and `/api/network` for graph edges and visualization
- `/api/conversations` and suggestion approval for transcript-backed profile updates
- `/api/network/ask` and `/api/network/introduction-suggestions` for semantic retrieval

`gemini-3.5-flash` is the default Vertex AI model for cloud transcription and
structured summaries. Override `GEMINI_TRANSCRIPTION_MODEL` or
`GEMINI_SUMMARY_MODEL` in `.env`.

## Start the test client

Requirements: a current Node.js release.

```bash
cd transcription-poc/test-client
npm install
npm run dev
```

Open `http://localhost:5173`. Vite proxies `/api` to the local backend, so no client
API URL is needed during development. Set `VITE_API_URL` when deploying the client
and API on different origins.

Choose a transcription route:

- **Cloud streaming** (default): live long-form transcription through Speech-to-Text.
- **On-device batch**: diagnostic Whisper path that never uploads audio.
- **Cloud file**: diagnostic upload path using Gemini.

Then follow **Record → Stop → inspect/edit transcript → Summarize**.

The production integration is the Flutter app in `../frontend`. Its Voice recap
screen uses the same WebSocket protocol and then commits the reviewed draft
through the transcription-session draft/commit endpoints. See the repository
README for Flutter web and Android startup commands.

The browser sends roughly 100 ms (3,200-byte) PCM chunks. The backend rotates the
inner Google gRPC stream after 4.5 minutes, replays one second of overlap, and
deduplicates overlap text while leaving the browser WebSocket open. Every final
segment is persisted immediately; stopping assembles the canonical transcript from
those segments.

During a short WebSocket interruption, the browser retains up to 60 seconds of
unacknowledged audio in memory and replays it after reconnecting. If that bound is
exceeded—or the page or backend process terminates—speech may be lost. The UI shows
an explicit gap warning and the session records the gap.

Google Cloud bills streaming recognition from the start of each request. At the
currently published standard rate of about $0.016/minute, one hour is approximately
$0.96; verify current Speech-to-Text V2 pricing and your Cloud credits before use.

## Testing on a phone

Microphone access requires a secure context. `localhost` qualifies on the development
computer, but a phone opening a LAN IP over plain HTTP usually does not. Expose the
Vite port through an HTTPS development tunnel or deploy the test client to an HTTPS
preview environment. Keep the backend running locally; Vite's `/api` proxy forwards
requests when the tunnel targets port 5173.

Mobile WebGPU support varies. The on-device diagnostic mode can be much slower than
real time on phones; cloud streaming is the intended long-form path.

## Verification

```bash
cd transcription-poc/backend
uv run ruff check .
uv run ruff format --check .
uv run mypy .
uv run pytest

cd ../test-client
npm run build
npm test
```

## Database

The schema is standard PostgreSQL and can move to a free hosted PostgreSQL provider
later by changing `DATABASE_URL` and running `uv run alembic upgrade head`.

Useful local commands:

```bash
# Stop without deleting data
docker compose stop postgres

# Reset all local database data
docker compose down -v
docker compose up -d postgres
cd backend && uv run alembic upgrade head
```
