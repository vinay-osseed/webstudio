#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

compose() {
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.local.yml \
    "$@"
}

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: Docker is required." >&2
  exit 1
}

mkdir -p prod-state

timestamp="$(date +%Y%m%d-%H%M%S)"
tmp="$(mktemp -d -t agns-webstudio-state.XXXXXX)"
trap 'rm -rf "${tmp}"' EXIT

compose up -d db postgrest minio app >/dev/null

echo "Dumping PostgreSQL..."
compose exec -T db \
  pg_dump \
    -U postgres \
    -d webstudio \
    -Fc \
    --no-owner \
    --no-acl \
  > "${tmp}/webstudio.dump"

minio_id="$(compose ps -q minio)"
app_id="$(compose ps -q app)"

[[ -n "${minio_id}" && -n "${app_id}" ]] || {
  echo "ERROR: Could not resolve local MinIO/App containers." >&2
  exit 1
}

mkdir -p "${tmp}/minio-data" "${tmp}/uploads"

echo "Copying MinIO assets..."
docker cp "${minio_id}:/data/." "${tmp}/minio-data/"

echo "Copying Builder uploads..."
docker cp "${app_id}:/app/public/s/uploads/." "${tmp}/uploads/" 2>/dev/null || true

cat > "${tmp}/MANIFEST.txt" <<EOF
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source: local AGNS Webstudio
Contains: PostgreSQL project data, MinIO assets, Builder uploads
Contains secrets: no
EOF

bundle="prod-state/agns-webstudio-state-${timestamp}.tar.gz"

tar -C "${tmp}" -czf "${bundle}" .

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${bundle}" > "${bundle}.sha256"
else
  sha256sum "${bundle}" > "${bundle}.sha256"
fi

echo "Created ${bundle}"
echo "Transfer this bundle to the VPS and pass it to scripts/prod/bootstrap-vps.sh --state."
