#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"

SOURCE_DIR="${ROOT}/exports/agns-source"
BUILD_ROOT="${ROOT}/exports/builds"
ARTIFACT_DIR="${ROOT}/exports/artifacts"

NODE_IMAGE="${NODE_IMAGE:-node:22-alpine}"

[[ -f "${ENV_FILE}" ]] || {
  echo "ERROR: ${ENV_FILE} is missing." >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

WEBSTUDIO_CLI_VERSION="${WEBSTUDIO_CLI_VERSION:?WEBSTUDIO_CLI_VERSION is missing from .env.production}"

mkdir -p \
  "${SOURCE_DIR}" \
  "${BUILD_ROOT}" \
  "${ARTIFACT_DIR}"

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

run_node() {
  local workdir="$1"
  shift

  docker run \
    --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/.home \
    -v "${workdir}:/work" \
    -w /work \
    "${NODE_IMAGE}" \
    sh -lc "$*"
}

run_cli() {
  local workdir="$1"
  shift

  run_node \
    "${workdir}" \
    "mkdir -p \"\$HOME\" && npx --yes webstudio@${WEBSTUDIO_CLI_VERSION} $*"
}

run_cli_interactive() {
  local workdir="$1"
  shift

  docker run \
    --rm \
    -it \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/.home \
    -v "${workdir}:/work" \
    -w /work \
    "${NODE_IMAGE}" \
    sh -lc \
    "mkdir -p \"\$HOME\" && npx --yes webstudio@${WEBSTUDIO_CLI_VERSION} $*"
}

require_builder() {
  curl \
    -fsS \
    http://127.0.0.1:3000/health \
    | grep -qi '^ok$' \
    || {
      echo "ERROR: Webstudio Builder is not healthy." >&2
      exit 1
    }
}

require_link() {
  if [[ -z "$(
    find "${SOURCE_DIR}" \
      -mindepth 1 \
      -maxdepth 2 \
      -type f \
      -print \
      -quit
  )" ]]; then
    echo "ERROR: Export workspace is not linked yet." >&2
    echo
    echo "Run:"
    echo "  ./scripts/prod/export-site.sh link"
    exit 1
  fi
}

sync_source() {
  require_builder
  require_link

  echo "Syncing latest Webstudio project data..."

  run_cli \
    "${SOURCE_DIR}" \
    sync
}

new_build_dir() {
  local kind="$1"
  local stamp="$2"
  local target="${BUILD_ROOT}/${stamp}-${kind}"

  mkdir -p "${target}"
  cp -a "${SOURCE_DIR}/." "${target}/"

  printf '%s\n' "${target}"
}

build_static() {
  local stamp="${1:-$(date +%Y%m%d-%H%M%S)}"
  local target
  local static_index
  local static_dir
  local tarball
  local latest_dir

  sync_source

  target="$(new_build_dir ssg "${stamp}")"

  echo "Generating Webstudio SSG project..."

  run_cli \
    "${target}" \
    "build --template ssg"

  [[ -f "${target}/package.json" ]] || {
    echo "ERROR: SSG export did not create package.json." >&2
    exit 1
  }

  echo "Installing generated SSG dependencies..."

  run_node \
    "${target}" \
    "npm install --no-audit --no-fund"

  echo "Producing final static HTML/CSS/JS..."

  run_node \
    "${target}" \
    "npm run build"

  static_index="$(
    find "${target}" \
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
      find "${target}" \
        -path '*/node_modules' -prune -o \
        -type f \
        -name index.html \
        -print \
        | head -1 \
        || true
    )"
  fi

  [[ -n "${static_index}" ]] || {
    echo "ERROR: Static build completed but no index.html was found." >&2
    exit 1
  }

  static_dir="$(dirname "${static_index}")"
  tarball="${ARTIFACT_DIR}/agns-static-${stamp}.tar.gz"

  tar \
    -C "${static_dir}" \
    -czf "${tarball}" \
    .

  latest_dir="${ROOT}/exports/latest-static"

  rm -rf "${latest_dir}"
  mkdir -p "${latest_dir}"
  cp -a "${static_dir}/." "${latest_dir}/"

  if command -v python3 >/dev/null 2>&1; then
    zipfile="${ARTIFACT_DIR}/agns-static-${stamp}.zip"

    (
      cd "${static_dir}"
      python3 -m zipfile \
        -c \
        "${zipfile}" \
        .
    )

    echo "ZIP:     ${zipfile}"
  fi

  echo "Static:  ${latest_dir}"
  echo "Tarball: ${tarball}"

  [[ -s "${latest_dir}/index.html" ]] || {
    echo "ERROR: latest-static/index.html is missing." >&2
    exit 1
  }

  echo "PASS: static export"
}

build_docker() {
  local stamp="${1:-$(date +%Y%m%d-%H%M%S)}"
  local target
  local tarball
  local latest_dir

  sync_source

  target="$(new_build_dir docker "${stamp}")"

  echo "Generating Webstudio Docker project..."

  run_cli \
    "${target}" \
    "build --template docker"

  [[ -f "${target}/Dockerfile" ]] || {
    echo "ERROR: Docker export did not create Dockerfile." >&2
    exit 1
  }

  [[ -f "${target}/package.json" ]] || {
    echo "ERROR: Docker export did not create package.json." >&2
    exit 1
  }

  tarball="${ARTIFACT_DIR}/agns-docker-${stamp}.tar.gz"

  tar \
    -C "${target}" \
    --exclude='./node_modules' \
    -czf "${tarball}" \
    .

  latest_dir="${ROOT}/exports/latest-docker"

  rm -rf "${latest_dir}"
  mkdir -p "${latest_dir}"
  cp -a "${target}/." "${latest_dir}/"
  rm -rf "${latest_dir}/node_modules"

  echo "Docker:  ${latest_dir}"
  echo "Tarball: ${tarball}"
  echo "PASS: Docker export"
}

status() {
  echo "Webstudio production export status"
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
    echo "NOT RUNNING / NOT READY"
  fi

  echo "CLI:       webstudio@${WEBSTUDIO_CLI_VERSION}"
  echo "Builder:   https://webstudio.agnsbroadband.in"
  echo "Source:    ${SOURCE_DIR}"

  if [[ -n "$(
    find "${SOURCE_DIR}" \
      -mindepth 1 \
      -maxdepth 2 \
      -type f \
      -print \
      -quit
  )" ]]; then
    echo "Link:      workspace contains Webstudio link/sync data"
  else
    echo "Link:      NOT LINKED"
  fi

  echo
  echo "Latest artifacts:"

  find "${ARTIFACT_DIR}" \
    -maxdepth 1 \
    -type f \
    -printf '  %TY-%Tm-%Td %TH:%TM  %p\n' \
    2>/dev/null \
    | sort \
    | tail -10 \
    || true
}

ACTION="${1:-status}"

case "${ACTION}" in
  status)
    status
    ;;

  link)
    require_builder

    echo "Create a Build-enabled Share link in the AGNS project:"
    echo "  https://webstudio.agnsbroadband.in"
    echo
    echo "Paste that Share link when Webstudio CLI asks for it."
    echo

    run_cli_interactive \
      "${SOURCE_DIR}" \
      link
    ;;

  sync)
    sync_source
    ;;

  static|ssg|download)
    build_static
    ;;

  docker)
    build_docker
    ;;

  all)
    stamp="$(date +%Y%m%d-%H%M%S)"
    build_static "${stamp}"
    build_docker "${stamp}"
    ;;

  template)
    template="${2:-}"

    [[ -n "${template}" ]] || {
      echo "Usage: $0 template TEMPLATE_NAME" >&2
      exit 1
    }

    sync_source

    stamp="$(date +%Y%m%d-%H%M%S)"
    target="$(new_build_dir "${template}" "${stamp}")"

    run_cli \
      "${target}" \
      "build --template ${template}"

    echo "Generated:"
    echo "  ${target}"
    ;;

  clean)
    rm -rf \
      "${BUILD_ROOT}" \
      "${ROOT}/exports/latest-static" \
      "${ROOT}/exports/latest-docker"

    mkdir -p \
      "${BUILD_ROOT}" \
      "${ARTIFACT_DIR}"

    echo "PASS: generated build directories cleaned"
    echo "Kept linked source workspace:"
    echo "  ${SOURCE_DIR}"
    echo "Kept packaged artifacts:"
    echo "  ${ARTIFACT_DIR}"
    ;;

  *)
    cat >&2 <<USAGE
Usage:
  $0 status
  $0 link
  $0 sync
  $0 static
  $0 docker
  $0 all
  $0 template TEMPLATE_NAME
  $0 clean

Aliases:
  download -> static
  ssg      -> static
USAGE
    exit 1
    ;;
esac
