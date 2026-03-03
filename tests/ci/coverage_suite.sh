#!/usr/bin/env bash
# tests/ci/coverage_suite.sh - Run full shell coverage suite and merge kcov output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="/tmp/sbx-kcov"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
KCOV_BIN="${KCOV_BIN:-}"
INCLUDE_DOCKER=0

usage() {
  cat <<USAGE
Usage: coverage_suite.sh [--out-dir /tmp/sbx-kcov] [--summary-file <path>] [--kcov-bin /path/to/kcov] [--include-docker]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --summary-file)
      SUMMARY_FILE="$2"
      shift 2
      ;;
    --kcov-bin)
      KCOV_BIN="$2"
      shift 2
      ;;
    --include-docker)
      INCLUDE_DOCKER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

summary() {
  local line="$1"
  if [[ -n "$SUMMARY_FILE" ]]; then
    echo "$line" >> "$SUMMARY_FILE"
  fi
}

if [[ -z "$KCOV_BIN" ]]; then
  KCOV_BIN="$(command -v kcov || true)"
fi

if [[ -z "$KCOV_BIN" ]] || [[ ! -x "$KCOV_BIN" ]]; then
  echo "Error: kcov not available. Install first or pass --kcov-bin." >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

run_case() {
  local name="$1"
  shift
  local case_dir="$OUT_DIR/raw-$name"
  echo "Running kcov case: $name"
  "$SCRIPT_DIR/tests/ci/run_with_kcov.sh" "$case_dir" --kcov-bin "$KCOV_BIN" -- "$@"
}

run_case "reality" bash "$SCRIPT_DIR/tests/test_reality.sh"
run_case "bootstrap" bash "$SCRIPT_DIR/tests/unit/test_bootstrap_constants.sh"
run_case "integration" bash "$SCRIPT_DIR/tests/ci/integration_checks.sh"
run_case "advanced" bash "$SCRIPT_DIR/tests/ci/advanced_features_checks.sh"

if [[ "$INCLUDE_DOCKER" -eq 1 ]]; then
  run_case "docker" bash "$SCRIPT_DIR/tests/integration/test_docker_lifecycle_smoke.sh"
else
  echo "Skipping docker lifecycle smoke in coverage suite (covered by dedicated CI job)."
fi

MERGED_DIR="$OUT_DIR/merged"
"$KCOV_BIN" --merge "$MERGED_DIR" "$OUT_DIR"/raw-*

if [[ ! -f "$MERGED_DIR/cobertura.xml" ]]; then
  echo "Error: merged cobertura.xml not found in $MERGED_DIR" >&2
  exit 1
fi

summary "## kcov Coverage"
summary ""
summary "- Coverage XML: `$MERGED_DIR/cobertura.xml`"
summary "- Coverage HTML: `$MERGED_DIR/index.html`"
summary ""

echo "COVERAGE_XML=$MERGED_DIR/cobertura.xml"
echo "COVERAGE_HTML=$MERGED_DIR/index.html"
