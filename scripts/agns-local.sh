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
    compose up -d

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
    if [[ -s .local/agns-local-project-url.txt ]]; then
      cat \
        .local/agns-local-project-url.txt
    fi
    ;;

  preview-url)
    echo "${PREVIEW_URL}"
    ;;

  secret)
    sed -n \
      's/^AUTH_SECRET=//p' \
      .env
    ;;

  open)
    open "${BUILDER_URL}"

    if [[ -s .local/agns-local-project-url.txt ]]; then
      open "$(
        cat \
          .local/agns-local-project-url.txt
      )"
    fi
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
    echo "  ./scripts/agns-local.sh secret"
    echo "  ./scripts/agns-local.sh open"
    exit 1
    ;;

esac
