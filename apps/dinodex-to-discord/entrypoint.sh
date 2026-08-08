#!/usr/bin/env bash
set -euo pipefail

ITEMS_FILE="${DINODEX_ITEMS_FILE:-/data/dinodex_items.json}"

mkdir -p "$(dirname "$ITEMS_FILE")"

if [[ -s "$ITEMS_FILE" ]]; then
  echo "Using dinodex data at $ITEMS_FILE" >&2
else
  echo "WARNING: no dinodex data found at $ITEMS_FILE." >&2
  echo "This image no longer bundles dinodex_extract.sh — mount or copy a" >&2
  echo "dinodex_items.json to that path (see DINODEX_ITEMS_FILE). The web UI" >&2
  echo "will start, but /api/creatures and /api/run will fail until it exists." >&2
fi

exec gunicorn \
  --bind "0.0.0.0:${PORT:-8080}" \
  --workers "${WEB_WORKERS:-2}" \
  --timeout "${GUNICORN_TIMEOUT:-200}" \
  --chdir /app \
  server:app
