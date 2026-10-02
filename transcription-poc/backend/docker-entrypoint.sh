#!/bin/sh
set -eu

# Render/etc.: paste the full service-account JSON into GOOGLE_SERVICE_ACCOUNT_JSON.
if [ -n "${GOOGLE_SERVICE_ACCOUNT_JSON:-}" ]; then
  creds_path=/tmp/gcp-sa.json
  printf '%s\n' "$GOOGLE_SERVICE_ACCOUNT_JSON" > "$creds_path"
  export GOOGLE_APPLICATION_CREDENTIALS="$creds_path"
fi

echo "Running database migrations…"
uv run alembic upgrade head

echo "Starting API on 0.0.0.0:${PORT:-8000}"
exec uv run uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
