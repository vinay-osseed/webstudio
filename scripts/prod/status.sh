#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

echo "============================================================"
echo "Containers"
echo "============================================================"

docker compose \
  --env-file .env.production \
  -f docker-compose.prod.yml \
  ps

echo
echo "============================================================"
echo "Health"
echo "============================================================"

printf 'Builder loopback: '

curl -sS \
  -o /dev/null \
  -w 'HTTP %{http_code}\n' \
  http://127.0.0.1:3000/health \
  || true

printf 'Builder public:   '

curl -sS \
  -o /dev/null \
  -w 'HTTP %{http_code}\n' \
  https://webstudio.agnsbroadband.in/health \
  || true

printf 'Publisher:        '

if docker compose \
  --env-file .env.production \
  -f docker-compose.prod.yml \
  exec -T publisher \
  wget -qO- http://127.0.0.1:4000/health \
  2>/dev/null \
  | grep -qi '^ok$'
then
  echo "OK"
else
  echo "NOT READY"
fi

echo
echo "============================================================"
echo "Export"
echo "============================================================"

./scripts/prod/export-site.sh status

echo
echo "============================================================"
echo "Nginx"
echo "============================================================"

systemctl \
  --no-pager \
  --full \
  status nginx \
  2>/dev/null \
  | sed -n '1,8p' \
  || true
