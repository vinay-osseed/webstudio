#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

docker compose \
  --env-file .env.production \
  -f docker-compose.prod.yml \
  ps

echo
printf 'Loopback Builder: '
curl -sS \
  -o /dev/null \
  -w 'HTTP %{http_code}\n' \
  http://127.0.0.1:3000/health \
  || true

echo
systemctl --no-pager --full status nginx 2>/dev/null \
  | sed -n '1,8p' \
  || true
