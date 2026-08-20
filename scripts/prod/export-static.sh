#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

case "${1:-all}" in
  link)
    exec ./scripts/prod/export-site.sh link
    ;;

  sync)
    exec ./scripts/prod/export-site.sh sync
    ;;

  status)
    exec ./scripts/prod/export-site.sh status
    ;;

  build|all|static|ssg|download)
    exec ./scripts/prod/export-site.sh static
    ;;

  clean)
    exec ./scripts/prod/export-site.sh clean
    ;;

  *)
    echo "Usage: $0 {status|link|sync|build|all|clean}" >&2
    exit 1
    ;;
esac
