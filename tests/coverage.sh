#!/usr/bin/env bash
# tests/coverage.sh - Compatibility wrapper for kcov-based coverage suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUT_DIR="${COVERAGE_DIR:-/tmp/sbx-kcov}"

warn_deprecated() {
  echo "[DEPRECATED] tests/coverage.sh now forwards to tests/ci/coverage_suite.sh" >&2
}

usage() {
  cat <<USAGE
Usage: coverage.sh [command]

Commands:
  generate, report  Run kcov coverage suite (default)
  html              Run suite and print HTML report path
  analyze           Enforce gate on existing Cobertura XML
  clean             Remove coverage output directory

Environment:
  COVERAGE_DIR             Output directory (default: /tmp/sbx-kcov)
  MIN_COVERAGE_PERCENT     Gate threshold for analyze (default: 80)
USAGE
}

command_name="${1:-generate}"

case "$command_name" in
  generate|report)
    warn_deprecated
    bash "$SCRIPT_DIR/tests/ci/coverage_suite.sh" --out-dir "$DEFAULT_OUT_DIR"
    ;;
  html)
    warn_deprecated
    bash "$SCRIPT_DIR/tests/ci/coverage_suite.sh" --out-dir "$DEFAULT_OUT_DIR"
    echo "HTML coverage report: $DEFAULT_OUT_DIR/merged/index.html"
    ;;
  analyze)
    warn_deprecated
    min_percent="${MIN_COVERAGE_PERCENT:-80}"
    xml_path="$DEFAULT_OUT_DIR/merged/kcov-merged/cobertura.xml"
    if [[ ! -f "$xml_path" ]]; then
      xml_path="$DEFAULT_OUT_DIR/merged/cobertura.xml"
    fi
    bash "$SCRIPT_DIR/tests/ci/coverage_gate.sh" \
      --xml "$xml_path" \
      --min-percent "$min_percent"
    ;;
  clean)
    rm -rf "$DEFAULT_OUT_DIR"
    echo "Removed coverage directory: $DEFAULT_OUT_DIR"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage >&2
    exit 1
    ;;
esac
