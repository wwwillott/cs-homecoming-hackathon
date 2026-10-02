#!/bin/sh
set -eu

echo "Running database migrations…"
uv run alembic upgrade head

echo "Starting API on 0.0.0.0:${PORT:-8000}"
exec uv run uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
