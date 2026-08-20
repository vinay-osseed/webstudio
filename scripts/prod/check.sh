#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"

[[ -f "${ENV_FILE}" ]] || {
  echo "ERROR: ${ENV_FILE} is missing." >&2
  exit 1
}

[[ -f "${COMPOSE_FILE}" ]] || {
  echo "ERROR: ${COMPOSE_FILE} is missing." >&2
  exit 1
}

if grep -Eq '(^|=)(CHANGE_ME|change-me)' "${ENV_FILE}"; then
  echo "ERROR: ${ENV_FILE} still contains placeholder values." >&2
  exit 1
fi

if grep -Eq '^DEV_LOGIN=true$|^ALLOW_INSECURE_COOKIES=true$' "${ENV_FILE}"; then
  echo "ERROR: development-only authentication/cookie settings are present." >&2
  exit 1
fi

for var in GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET POSTGRES_PASSWORD PGRST_JWT_SECRET AUTH_SECRET AUTH_WS_CLIENT_SECRET MINIO_ROOT_PASSWORD ACME_EMAIL; do
  if ! grep -Eq "^${var}=.+$" "${ENV_FILE}"; then
    echo "ERROR: ${var} is missing from ${ENV_FILE}." >&2
    exit 1
  fi
done

if command -v docker >/dev/null 2>&1; then
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    config --quiet
fi

if git ls-files --error-unmatch "${ENV_FILE}" >/dev/null 2>&1; then
  echo "ERROR: ${ENV_FILE} is tracked by Git." >&2
  exit 1
fi

if git diff --check; then
  :
else
  exit 1
fi

echo "PASS: production configuration checks."
