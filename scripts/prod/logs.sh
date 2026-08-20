#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

exec docker compose \
  --env-file .env.production \
  -f docker-compose.prod.yml \
  logs -f --tail=200 \
  app postgrest db minio
