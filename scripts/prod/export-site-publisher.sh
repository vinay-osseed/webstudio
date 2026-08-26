#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE="${ENV_FILE:-.env.production}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

SOURCE_DIR="${SOURCE_DIR:-${ROOT}/exports/agns-source}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT}/exports/artifacts}"
LATEST_STATIC="${LATEST_STATIC:-${ROOT}/exports/latest-static}"

NODE_IMAGE="${NODE_IMAGE:-node:22-alpine}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -f "${ENV_FILE}" ]] || die "${ENV_FILE} is missing."
[[ -f "${COMPOSE_FILE}" ]] || die "${COMPOSE_FILE} is missing."

mkdir -p \
  "${SOURCE_DIR}" \
  "${ARTIFACT_DIR}"

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

publisher_container() {
  local container

  container="$(compose ps -q publisher)"

  [[ -n "${container}" ]] || \
    die "Publisher container is not running."

  printf '%s\n' "${container}"
}

publisher_image() {
  docker inspect \
    -f '{{.Image}}' \
    "$(publisher_container)"
}

require_builder() {
  curl \
    -fsS \
    http://127.0.0.1:3000/health \
    | grep -qi '^ok$' \
    || die "Webstudio Builder is not healthy."
}

require_publisher() {
  compose exec -T publisher \
    wget -qO- http://127.0.0.1:4000/health \
    | grep -qi '^ok$' \
    || die "Webstudio Publisher is not healthy."
}

require_publisher_cli() {
  local image

  image="$(publisher_image)"

  docker run \
    --rm \
    --entrypoint sh \
    "${image}" \
    -lc 'command -v webstudio >/dev/null && test -x "$(command -v webstudio)"' \
    || die "Bundled Webstudio CLI was not found in Publisher image."
}

run_publisher_cli() {
  local mode="$1"
  shift

  local image
  local tty=()

  image="$(publisher_image)"

  if [[ "${mode}" == "interactive" ]]; then
    tty=(-it)
  fi

  docker run \
    --rm \
    "${tty[@]}" \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/.home \
    -v "${SOURCE_DIR}:/work" \
    -w /work \
    --entrypoint sh \
    "${image}" \
    -lc 'mkdir -p "$HOME" && exec webstudio "$@"' \
    sh \
    "$@"
}

run_node() {
  local command="$1"

  docker run \
    --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/.home \
    -e npm_config_cache=/work/.npm-cache \
    -v "${SOURCE_DIR}:/work" \
    -w /work \
    "${NODE_IMAGE}" \
    sh -lc "${command}"
}

require_link() {
  [[ -f "${SOURCE_DIR}/.webstudio/config.json" ]] || {
    echo "ERROR: Webstudio export workspace is not linked." >&2
    echo >&2
    echo "Run:" >&2
    echo "  ./scripts/prod/export-site-publisher.sh link" >&2
    exit 1
  }
}

link_project() {
  require_builder
  require_publisher
  require_publisher_cli

  echo "Linking AGNS Webstudio project."
  echo
  echo "Create a fresh Share link with Build access."
  echo "Paste it only when Webstudio prompts for it."
  echo

  run_publisher_cli interactive link

  require_link

  echo
  echo "PASS: Webstudio project linked."
}

export_ssg() {
  require_builder
  require_publisher
  require_publisher_cli
  require_link

  echo "Refreshing Webstudio editable project session..."

  run_publisher_cli batch meta.index >/dev/null

  echo
  echo "Starting Webstudio export."
  echo "Choose:"
  echo
  echo "  Static Site Generation (SSG)"
  echo

  run_publisher_cli interactive

  [[ -f "${SOURCE_DIR}/package.json" ]] || \
    die "SSG export did not create package.json."

  [[ -d "${SOURCE_DIR}/pages" ]] || \
    die "SSG export did not create pages/."

  [[ -d "${SOURCE_DIR}/public" ]] || \
    die "SSG export did not create public/."

  echo
  echo "PASS: Webstudio SSG source exported."
  echo "Source:"
  echo "  ${SOURCE_DIR}"
}

build_static() {
  local stamp
  local static_index
  local static_dir
  local tarball

  export_ssg

  echo
  echo "Installing generated project dependencies..."

  run_node \
    'npm install --no-audit --no-fund'

  echo
  echo "Building final static site..."

  run_node \
    'npm run build'

  static_index="$(
    find "${SOURCE_DIR}" \
      -path '*/node_modules' -prune -o \
      -type f \
      -name index.html \
      -print \
      | grep -E '/dist/index\.html$|/build/client/index\.html$' \
      | head -1 \
      || true
  )"

  if [[ -z "${static_index}" ]]; then
    static_index="$(
      find "${SOURCE_DIR}" \
        -path '*/node_modules' -prune -o \
        -type f \
        -name index.html \
        -print \
        | head -1 \
        || true
    )"
  fi

  [[ -n "${static_index}" ]] || \
    die "Build completed but no index.html was found."

  static_dir="$(dirname "${static_index}")"

  rm -rf "${LATEST_STATIC}"
  mkdir -p "${LATEST_STATIC}"

  cp -a \
    "${static_dir}/." \
    "${LATEST_STATIC}/"

  stamp="$(date +%Y%m%d-%H%M%S)"
  tarball="${ARTIFACT_DIR}/agns-static-${stamp}.tar.gz"

  tar \
    -C "${static_dir}" \
    -czf "${tarball}" \
    .

  [[ -s "${LATEST_STATIC}/index.html" ]] || \
    die "latest-static/index.html is missing."

  echo
  echo "PASS: final static build."
  echo "Static:"
  echo "  ${LATEST_STATIC}"
  echo "Artifact:"
  echo "  ${tarball}"
}

status() {
  local image

  echo "AGNS Webstudio export status"
  echo

  printf 'Builder:   '
  if curl -fsS http://127.0.0.1:3000/health 2>/dev/null \
    | grep -qi '^ok$'
  then
    echo "OK"
  else
    echo "DOWN"
  fi

  printf 'Publisher: '
  if compose exec -T publisher \
    wget -qO- http://127.0.0.1:4000/health \
    2>/dev/null \
    | grep -qi '^ok$'
  then
    echo "OK"
  else
    echo "DOWN"
  fi

  if image="$(publisher_image 2>/dev/null)"; then
    echo "CLI image: ${image}"

    printf 'CLI path:  '

    docker run \
      --rm \
      --entrypoint sh \
      "${image}" \
      -lc 'printf "%s -> %s\n" "$(command -v webstudio)" "$(readlink -f "$(command -v webstudio)")"' \
      2>/dev/null \
      || echo "NOT FOUND"
  else
    echo "CLI image: unavailable"
  fi

  echo "Source:    ${SOURCE_DIR}"

  if [[ -f "${SOURCE_DIR}/.webstudio/config.json" ]]; then
    echo "Link:      configured"
  else
    echo "Link:      NOT CONFIGURED"
  fi

  if [[ -f "${SOURCE_DIR}/package.json" ]]; then
    echo "SSG:       generated"
  else
    echo "SSG:       not generated"
  fi

  if [[ -s "${LATEST_STATIC}/index.html" ]]; then
    echo "Static:    available"
  else
    echo "Static:    not built"
  fi
}

ACTION="${1:-status}"

case "${ACTION}" in
  status)
    status
    ;;

  link)
    link_project
    ;;

  export|ssg)
    export_ssg
    ;;

  static|build)
    build_static
    ;;

  *)
    cat >&2 <<USAGE
Usage:
  $0 status
  $0 link
  $0 export
  $0 static

Actions:
  status  Check Builder, Publisher, bundled CLI and export state.
  link    One-time Webstudio Share-link setup.
  export  Export latest Webstudio project as SSG source.
  static  Export SSG source, install dependencies and build static HTML.

Aliases:
  ssg   -> export
  build -> static
USAGE
    exit 1
    ;;
esac
