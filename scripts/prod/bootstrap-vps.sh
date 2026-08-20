#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"
STATE_BUNDLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      STATE_BUNDLE="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      echo "Usage: $0 [--state /path/to/webstudio-state-....tar.gz]" >&2
      exit 1
      ;;
  esac
done

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: Docker is required on the VPS." >&2
  exit 1
}

docker compose version >/dev/null 2>&1 || {
  echo "ERROR: Docker Compose v2 is required." >&2
  exit 1
}

[[ -f "${ENV_FILE}" ]] || {
  echo "ERROR: ${ENV_FILE} is missing. Run scripts/prod/generate-env.sh first." >&2
  exit 1
}

./scripts/prod/check.sh

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ "${BUILDER_IMAGE}" != *@sha256:* ]]; then
  echo "Production images are not pinned yet. Pinning them now..."
  ./scripts/prod/pin-images.sh
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

printf '%s\n' \
  "DNS required before HTTPS can succeed:" \
  "  A  webstudio.agnsbroadband.in    -> VPS IPv4" \
  "  A  *.webstudio.agnsbroadband.in  -> VPS IPv4" \
  "Do not point agnsbroadband.in at this VPS; the public site is hosted separately."

if command -v getent >/dev/null 2>&1; then
  echo
  echo "Current DNS resolution:"
  getent ahostsv4 webstudio.agnsbroadband.in | head -3 || true
  getent ahostsv4 test.webstudio.agnsbroadband.in | head -3 || true
fi

docker run --rm \
  -e "ACME_EMAIL=${ACME_EMAIL}" \
  -v "${ROOT}/deploy/prod/Caddyfile:/etc/caddy/Caddyfile:ro" \
  "${CADDY_IMAGE}" \
  caddy validate \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile

if [[ -n "${STATE_BUNDLE}" ]]; then
  ./scripts/prod/import-state.sh "${STATE_BUNDLE}"
else
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    pull

  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    up -d
fi

ready=0
for _ in $(seq 1 90); do
  if docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    exec -T app \
    wget -qO- http://127.0.0.1:3000/health \
    | grep -qi '^ok$'; then
    ready=1
    break
  fi
  sleep 2
done

[[ "${ready}" == "1" ]] || {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    logs --tail=200 app postgrest db caddy
  echo "ERROR: Builder did not become healthy." >&2
  exit 1
}

echo "PASS: Builder container is healthy."

if curl -fsS --max-time 20 https://webstudio.agnsbroadband.in/health | grep -qi '^ok$'; then
  echo "PASS: public HTTPS builder is healthy."
else
  echo "WARNING: internal Builder is healthy, but public HTTPS is not ready yet."
  echo "Check DNS for webstudio.agnsbroadband.in and ports 80/443 on the VPS firewall."
fi

echo
echo "Builder: https://webstudio.agnsbroadband.in"
echo "Google callback: https://webstudio.agnsbroadband.in/auth/google/callback"
echo "Project canvases: https://p-<project-id>.webstudio.agnsbroadband.in"
