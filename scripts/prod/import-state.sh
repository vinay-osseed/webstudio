#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

BUNDLE="${1:-}"
[[ -f "${BUNDLE}" ]] || {
  echo "ERROR: State bundle not found: ${BUNDLE}" >&2
  exit 1
}

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"

tmp="$(mktemp -d -t agns-webstudio-import.XXXXXX)"
trap 'rm -rf "${tmp}"' EXIT

tar -xzf "${BUNDLE}" -C "${tmp}"

[[ -s "${tmp}/webstudio.dump" ]] || {
  echo "ERROR: State bundle has no webstudio.dump." >&2
  exit 1
}

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

compose pull
compose up -d db minio

for _ in $(seq 1 60); do
  if compose exec -T db pg_isready -U postgres -d webstudio >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

existing="$(
  compose exec -T db \
    psql -U postgres -d webstudio -tA \
    -c 'SELECT CASE WHEN to_regclass('"'"'public."Project"'"'"') IS NULL THEN 0 ELSE (SELECT count(*) FROM "Project") END;' \
    2>/dev/null \
    || echo 0
)"

if [[ "${existing}" =~ ^[0-9]+$ ]] && (( existing > 0 )); then
  echo "ERROR: Production database already contains ${existing} project(s)." >&2
  echo "Refusing destructive state import." >&2
  exit 1
fi

compose stop app postgrest migrate db-setup minio-init 2>/dev/null || true

echo "Restoring PostgreSQL..."
compose exec -T db \
  pg_restore \
    -U postgres \
    -d webstudio \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
  < "${tmp}/webstudio.dump"

compose stop minio

echo "Restoring MinIO assets..."
docker run --rm \
  -v agns-webstudio-minio:/data \
  "${ALPINE_IMAGE}" \
  sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} +'

if [[ -d "${tmp}/minio-data" ]]; then
  tar -C "${tmp}/minio-data" -czf - . \
    | docker run --rm -i \
        -v agns-webstudio-minio:/data \
        "${ALPINE_IMAGE}" \
        sh -c 'tar -xzf - -C /data'
fi

echo "Restoring Builder uploads..."
docker run --rm \
  -v agns-webstudio-uploads:/data \
  "${ALPINE_IMAGE}" \
  sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} +'

if [[ -d "${tmp}/uploads" ]]; then
  tar -C "${tmp}/uploads" -czf - . \
    | docker run --rm -i \
        -v agns-webstudio-uploads:/data \
        "${ALPINE_IMAGE}" \
        sh -c 'tar -xzf - -C /data'
fi

compose up -d

echo "PASS: local Webstudio project state restored to production volumes."
