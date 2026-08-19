#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(
  git rev-parse \
    --show-toplevel
)"

cd "${ROOT}"

PREVIEW_CONTAINER="agns-local-preview"

BUILDER_URL="https://webstudio.localhost"
PREVIEW_URL="http://agns.localhost:4173"

compose() {
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.local.yml \
    "$@"
}

start_preview() {
  docker rm \
    -f \
    "${PREVIEW_CONTAINER}" \
    >/dev/null 2>&1 \
    || true

  docker run \
    -d \
    --name "${PREVIEW_CONTAINER}" \
    --restart unless-stopped \
    -p "127.0.0.1:4173:80" \
    -v "${ROOT}/site/agns:/usr/share/nginx/html:ro" \
    nginx:alpine \
    >/dev/null
}

resolve_agns_project_id() {
  local password
  local rows

  password="$(
    sed -n 's/^POSTGRES_PASSWORD=//p' .env \
      | tail -1
  )"

  [[ -n "${password}" ]] || {
    echo "ERROR: POSTGRES_PASSWORD is missing from .env." >&2
    return 1
  }

  rows="$(mktemp -t agns-projects.XXXXXX)"

  compose exec \
    -T \
    -e "PGPASSWORD=${password}" \
    db \
    psql \
    -U postgres \
    -d webstudio \
    -tA \
    -c 'SELECT row_to_json(p)::text FROM "Project" p;' \
    > "${rows}"

  PROJECT_ROWS="${rows}" python3 - <<'PYPROJECT'
from pathlib import Path
import json
import os

wanted = "AGNS XSTREAM FIBERNET"
matches = []

for raw in Path(os.environ["PROJECT_ROWS"]).read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue

    row = json.loads(raw)

    strings = [
        value.strip()
        for value in row.values()
        if isinstance(value, str)
    ]

    if wanted in strings:
        matches.append(row)

if len(matches) != 1:
    raise SystemExit(
        f"Expected exactly one {wanted!r} project; found {len(matches)}."
    )

value = matches[0].get("id")

if not isinstance(value, str) or not value:
    raise SystemExit("Matched project has no usable id.")

print(value)
PYPROJECT

  local status=$?
  rm -f "${rows}"
  return "${status}"
}

case "${1:-status}" in

  start)
    compose up -d

    start_preview

    echo "Webstudio: ${BUILDER_URL}"
    echo "Static preview: ${PREVIEW_URL}"
    ;;

  stop)
    docker rm \
      -f \
      "${PREVIEW_CONTAINER}" \
      >/dev/null 2>&1 \
      || true

    compose stop
    ;;

  restart)
    "$0" stop
    "$0" start
    ;;

  build)
    compose up -d \
      postgrest \
      app \
      local-proxy \
      publisher

    AGNS_PROJECT_ID="$(
      resolve_agns_project_id
    )"

    [[ -n "${AGNS_PROJECT_ID}" ]] || {
      echo "ERROR: AGNS project ID could not be resolved." >&2
      exit 1
    }

    AGNS_PROJECT_ID="${AGNS_PROJECT_ID}" \
      node \
      scripts/automation/agns-local-import.mjs
    ;;

  status)
    printf 'Webstudio: '

    curl \
      -fsS \
      -o /dev/null \
      -w 'HTTP %{http_code}\n' \
      "${BUILDER_URL}/health" \
      || true

    printf 'Static preview: '

    curl \
      -fsS \
      -o /dev/null \
      -w 'HTTP %{http_code}\n' \
      "${PREVIEW_URL}" \
      || true

    compose ps
    ;;

  logs)
    compose logs \
      --tail=150 \
      -f \
      app \
      local-proxy \
      postgrest \
      db
    ;;

  url)
    echo "${BUILDER_URL}"
    ;;

  project-url)
    AGNS_PROJECT_ID="$(
      resolve_agns_project_id
    )"

    [[ -n "${AGNS_PROJECT_ID}" ]] || {
      echo "ERROR: AGNS project ID could not be resolved." >&2
      exit 1
    }

    echo "https://p-${AGNS_PROJECT_ID}.webstudio.localhost/"
    ;;

  preview-url)
    echo "${PREVIEW_URL}"
    ;;

  home)
    AGNS_PROJECT_ID="$(
      resolve_agns_project_id
    )"

    [[ -n "${AGNS_PROJECT_ID}" ]] || {
      echo "ERROR: AGNS project ID could not be resolved." >&2
      exit 1
    }

    open "https://p-${AGNS_PROJECT_ID}.webstudio.localhost/"
    ;;

  secret)
    sed -n \
      's/^AUTH_SECRET=//p' \
      .env
    ;;

  open)
    AGNS_PROJECT_ID="$(
      resolve_agns_project_id
    )"

    [[ -n "${AGNS_PROJECT_ID}" ]] || {
      echo "ERROR: AGNS project ID could not be resolved." >&2
      exit 1
    }

    open "https://p-${AGNS_PROJECT_ID}.webstudio.localhost/"
    ;;

  *)
    echo "Usage:"
    echo "  ./scripts/agns-local.sh start"
    echo "  ./scripts/agns-local.sh stop"
    echo "  ./scripts/agns-local.sh restart"
    echo "  ./scripts/agns-local.sh build"
    echo "  ./scripts/agns-local.sh status"
    echo "  ./scripts/agns-local.sh logs"
    echo "  ./scripts/agns-local.sh url"
    echo "  ./scripts/agns-local.sh project-url"
    echo "  ./scripts/agns-local.sh preview-url"
    echo "  ./scripts/agns-local.sh home"
    echo "  ./scripts/agns-local.sh secret"
    echo "  ./scripts/agns-local.sh open"
    exit 1
    ;;

esac
