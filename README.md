# cs-homecoming-hackathon
BYU Homecoming Hackathon

## Projects

- [`frontend/`](frontend/): Orbit Flutter app for web and Android.
- [`transcription-poc/`](transcription-poc/): phone-side conversation transcription,
  PostgreSQL network data, Gemini summaries, and network search.

## Run the integrated app

Start PostgreSQL and the API:

```bash
cd transcription-poc
docker compose up -d postgres
cd backend
cp .env.example .env  # first run only; set GOOGLE_CLOUD_PROJECT
uv sync
uv run alembic upgrade head
uv run uvicorn main:app --reload
```

Then run Flutter web on the backend's allowed development origin:

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 5173 \
  --dart-define=ORBIT_API_URL=http://127.0.0.1:8000
```

For the Android emulator, use
`--dart-define=ORBIT_API_URL=http://10.0.2.2:8000`. A physical phone needs an
HTTPS URL reachable from that phone. Microphone access on web also requires
HTTPS except on `localhost`.

The Voice recap screen now streams 16 kHz PCM to the backend, displays interim
and final text live, saves final transcript segments to PostgreSQL, generates a
reviewable contact draft, and commits the reviewed person, notes, conversation,
and search embeddings to the database.
