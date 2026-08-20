#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
[[ -f "${ENV_FILE}" ]] || {
  echo "ERROR: ${ENV_FILE} is missing. Run scripts/prod/generate-env.sh first." >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker is required." >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

vars=(
  BUILDER_IMAGE
  POSTGRES_IMAGE
  POSTGREST_IMAGE
  MINIO_IMAGE
  MINIO_MC_IMAGE
  CADDY_IMAGE
  NGINX_IMAGE
  ALPINE_IMAGE
)

for var in "${vars[@]}"; do
  value="${!var:-}"
  [[ -n "${value}" ]] || {
    echo "ERROR: ${var} is empty in ${ENV_FILE}." >&2
    exit 1
  }

  echo "Pinning ${var}..."
  docker pull "${value}" >/dev/null

  digest="$(
    docker image inspect \
      --format '{{index .RepoDigests 0}}' \
      "${value}"
  )"

  [[ -n "${digest}" && "${digest}" == *@sha256:* ]] || {
    echo "ERROR: Could not resolve immutable digest for ${value}." >&2
    exit 1
  }

  VAR_NAME="${var}" VAR_VALUE="${digest}" python3 - <<'PY'
from pathlib import Path
import os

path = Path('.env.production')
name = os.environ['VAR_NAME']
value = os.environ['VAR_VALUE']
lines = path.read_text().splitlines()
out = []
found = False

for line in lines:
    if line.startswith(f'{name}='):
        out.append(f'{name}={value}')
        found = True
    else:
        out.append(line)

if not found:
    out.append(f'{name}={value}')

path.write_text('\n'.join(out) + '\n')
PY

done

chmod 600 "${ENV_FILE}"
echo "PASS: production images are pinned to immutable digests."
