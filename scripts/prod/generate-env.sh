#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

OUT=".env.production"

if [[ -e "${OUT}" ]]; then
  echo "ERROR: ${OUT} already exists. Refusing to overwrite it." >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || {
  echo "ERROR: openssl is required." >&2
  exit 1
}

read -r -p "ACME email [admin@agnsbroadband.in]: " ACME_EMAIL_INPUT
ACME_EMAIL_INPUT="${ACME_EMAIL_INPUT:-admin@agnsbroadband.in}"

read -r -p "Google OAuth Client ID: " GOOGLE_CLIENT_ID_INPUT
[[ -n "${GOOGLE_CLIENT_ID_INPUT}" ]] || {
  echo "ERROR: Google OAuth Client ID is required." >&2
  exit 1
}

read -r -s -p "Google OAuth Client Secret: " GOOGLE_CLIENT_SECRET_INPUT
printf '\n'
[[ -n "${GOOGLE_CLIENT_SECRET_INPUT}" ]] || {
  echo "ERROR: Google OAuth Client Secret is required." >&2
  exit 1
}

POSTGRES_PASSWORD_VALUE="$(openssl rand -hex 32)"
PGRST_JWT_SECRET_VALUE="$(openssl rand -hex 64)"
AUTH_SECRET_VALUE="$(openssl rand -hex 32)"
AUTH_WS_CLIENT_SECRET_VALUE="$(openssl rand -hex 32)"
MINIO_ROOT_PASSWORD_VALUE="$(openssl rand -hex 32)"

umask 077

cat > "${OUT}" <<EOF
ACME_EMAIL=${ACME_EMAIL_INPUT}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID_INPUT}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET_INPUT}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD_VALUE}
PGRST_JWT_SECRET=${PGRST_JWT_SECRET_VALUE}
AUTH_SECRET=${AUTH_SECRET_VALUE}
AUTH_WS_CLIENT_ID=agns-webstudio-cli
AUTH_WS_CLIENT_SECRET=${AUTH_WS_CLIENT_SECRET_VALUE}
MINIO_ROOT_USER=webstudio
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD_VALUE}
FEATURES=*
USER_PLAN=Pro
MAX_ASSETS_PER_PROJECT=250
S3_REGION=us-east-1
S3_BUCKET=webstudio-assets
BUILDER_IMAGE=ghcr.io/webstudio-community/builder:latest
POSTGRES_IMAGE=postgres:15.19-alpine
POSTGREST_IMAGE=postgrest/postgrest:v12.2.0
MINIO_IMAGE=minio/minio:latest
MINIO_MC_IMAGE=minio/mc:latest
CADDY_IMAGE=caddy:2.10.2-alpine
NGINX_IMAGE=nginx:1.29-alpine
ALPINE_IMAGE=alpine:3.22
EOF

chmod 600 "${OUT}"

echo "Created ${OUT} with fresh production secrets."
echo "The secret values were not printed."
