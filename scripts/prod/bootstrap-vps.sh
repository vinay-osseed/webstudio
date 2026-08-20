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

echo "Production edge: existing VPS Nginx + Certbot."
echo "Caddy is disabled by the caddy-edge Compose profile."
echo

if command -v getent >/dev/null 2>&1; then
  echo "Current DNS resolution:"
  getent ahostsv4 webstudio.agnsbroadband.in | head -3 || true
  getent ahostsv4 test.webstudio.agnsbroadband.in | head -3 || true
  echo
fi

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
    logs --tail=200 app postgrest db minio

  echo "ERROR: Builder did not become healthy." >&2
  exit 1
}

echo "PASS: Builder container is healthy."

if curl -fsS --max-time 5 http://127.0.0.1:3000/health | grep -qi '^ok$'; then
  echo "PASS: Builder is bound to host loopback on 127.0.0.1:3000."
else
  echo "ERROR: Builder is not reachable on host loopback." >&2
  exit 1
fi

echo
echo "Next:"
echo "  ./scripts/prod/configure-host-nginx.sh"
echo
echo "Builder after Nginx/Certbot:"
echo "  https://webstudio.agnsbroadband.in"
echo "Google callback:"
echo "  https://webstudio.agnsbroadband.in/auth/google/callback"
