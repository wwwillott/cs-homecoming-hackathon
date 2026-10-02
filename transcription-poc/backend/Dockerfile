# Build from repo root:
#   docker build -f transcription-poc/backend/Dockerfile -t spruce-api .
FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    PYTHONPATH=/app \
    PORT=8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

COPY transcription-poc/backend/pyproject.toml transcription-poc/backend/uv.lock ./
RUN uv sync --frozen --no-dev

COPY chatbot ./chatbot
COPY transcription-poc/backend/alembic.ini ./
COPY transcription-poc/backend/alembic ./alembic
COPY transcription-poc/backend/database ./database
COPY transcription-poc/backend/*.py ./
COPY transcription-poc/backend/docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["./docker-entrypoint.sh"]
