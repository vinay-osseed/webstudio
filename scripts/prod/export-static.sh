#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ACTION="${1:-all}"
WORKDIR="${ROOT}/exports/agns-static"
NODE_IMAGE="${NODE_IMAGE:-node:22-alpine}"

mkdir -p "${WORKDIR}"

run_cli() {
  docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/home \
    -v "${WORKDIR}:/work" \
    -w /work \
    "${NODE_IMAGE}" \
    sh -lc "mkdir -p \"\$HOME\" && npx --yes webstudio@latest $*"
}

case "${ACTION}" in
  link)
    echo "Paste a Build-enabled Share link from https://webstudio.agnsbroadband.in when prompted."
    run_cli link
    ;;
  sync)
    run_cli sync
    ;;
  build)
    run_cli build --template ssg
    ;;
  all)
    echo "This assumes the export workspace was linked once with:"
    echo "  ./scripts/prod/export-static.sh link"
    run_cli sync
    run_cli build --template ssg
    echo "Static export workspace: ${WORKDIR}"
    ;;
  *)
    echo "Usage: $0 {link|sync|build|all}" >&2
    exit 1
    ;;
esac
