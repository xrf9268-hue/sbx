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

summary() {
  local line="$1"
  if [[ -n "$SUMMARY_FILE" ]]; then
    echo "$line" >> "$SUMMARY_FILE"
  fi
}

run_case() {
  local name="$1"
  shift
  local case_dir="$OUT_DIR/raw-$name"
  echo "Running kcov case: $name"
  "$SCRIPT_DIR/tests/ci/run_with_kcov.sh" "$case_dir" --kcov-bin "$KCOV_BIN" -- "$@"
}

resolve_coverage_report_dir() {
  local merged_dir="$1"

  if [[ -f "$merged_dir/cobertura.xml" ]]; then
    echo "$merged_dir"
    return 0
  fi

  if [[ -f "$merged_dir/kcov-merged/cobertura.xml" ]]; then
    echo "$merged_dir/kcov-merged"
    return 0
  fi

  local resolved_xml
  resolved_xml="$(find "$merged_dir" -maxdepth 4 -type f -name 'cobertura.xml' | head -n 1 || true)"
  if [[ -n "$resolved_xml" ]]; then
    dirname "$resolved_xml"
    return 0
  fi

  return 1
}

normalize_report_layout() {
  local report_dir="$1"
  echo "$report_dir"
}

main() {
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

  if [[ -z "$KCOV_BIN" ]]; then
    KCOV_BIN="$(command -v kcov || true)"
  fi

  if [[ -z "$KCOV_BIN" ]] || [[ ! -x "$KCOV_BIN" ]]; then
    echo "Error: kcov not available. Install first or pass --kcov-bin." >&2
    exit 1
  fi

  rm -rf "$OUT_DIR"
  mkdir -p "$OUT_DIR"

  run_case "reality" "$SCRIPT_DIR/tests/test_reality.sh"
  run_case "bootstrap" "$SCRIPT_DIR/tests/unit/test_bootstrap_constants.sh"
  run_case "integration" "$SCRIPT_DIR/tests/ci/integration_checks.sh"
  run_case "advanced" "$SCRIPT_DIR/tests/ci/advanced_features_checks.sh"

  if [[ "$INCLUDE_DOCKER" -eq 1 ]]; then
    run_case "docker" "$SCRIPT_DIR/tests/integration/test_docker_lifecycle_smoke.sh"
  else
    echo "Skipping docker lifecycle smoke in coverage suite (covered by dedicated CI job)."
  fi

  local merged_dir report_dir normalized_dir coverage_xml coverage_html
  merged_dir="$OUT_DIR/merged"
  "$KCOV_BIN" --merge "$merged_dir" "$OUT_DIR"/raw-*

  report_dir="$(resolve_coverage_report_dir "$merged_dir" || true)"
  if [[ -z "$report_dir" ]]; then
    echo "Error: merged cobertura.xml not found under $merged_dir" >&2
    echo "Debug: merged directory contents:" >&2
    find "$merged_dir" -maxdepth 4 -type f >&2 || true
    exit 1
  fi

  normalized_dir="$(normalize_report_layout "$report_dir")"
  coverage_xml="$normalized_dir/cobertura.xml"
  coverage_html="$normalized_dir/index.html"

  summary "## kcov Coverage"
  summary ""
  summary "- Coverage XML: \`$coverage_xml\`"
  summary "- Coverage HTML: \`$coverage_html\`"
  summary ""

  echo "COVERAGE_XML=$coverage_xml"
  echo "COVERAGE_HTML=$coverage_html"
  echo "COVERAGE_DIR=$normalized_dir"
}

if [[ "${COVERAGE_SUITE_LIBRARY_MODE:-0}" != "1" ]]; then
  main "$@"
fi
