#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"

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

mkdir -p backups

timestamp="$(date +%Y%m%d-%H%M%S)"
tmp="$(mktemp -d -t agns-webstudio-backup.XXXXXX)"
trap 'rm -rf "${tmp}"' EXIT

compose exec -T db \
  pg_dump -U postgres -d webstudio -Fc --no-owner --no-acl \
  > "${tmp}/webstudio.dump"

docker run --rm \
  -v agns-webstudio-minio:/data:ro \
  "${ALPINE_IMAGE}" \
  sh -c 'tar -czf - -C /data .' \
  > "${tmp}/minio-data.tar.gz"

docker run --rm \
  -v agns-webstudio-uploads:/data:ro \
  "${ALPINE_IMAGE}" \
  sh -c 'tar -czf - -C /data .' \
  > "${tmp}/uploads.tar.gz"

bundle="backups/agns-webstudio-prod-${timestamp}.tar.gz"
tar -C "${tmp}" -czf "${bundle}" .

echo "Created ${bundle}"
