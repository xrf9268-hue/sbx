#!/usr/bin/env bash
# tests/ci/run_with_kcov.sh - Execute one command under kcov

set -euo pipefail

usage() {
  cat <<USAGE
Usage: run_with_kcov.sh <output_dir> [--kcov-bin /path/to/kcov] -- <command...>
USAGE
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 1
fi

OUTPUT_DIR="$1"
shift

KCOV_BIN="${KCOV_BIN:-}"
if [[ "$1" == "--kcov-bin" ]]; then
  KCOV_BIN="$2"
  shift 2
fi

if [[ "$1" != "--" ]]; then
  usage >&2
  exit 1
fi
shift

if [[ $# -eq 0 ]]; then
  echo "Error: missing command after --" >&2
  usage >&2
  exit 1
fi

if [[ -z "$KCOV_BIN" ]]; then
  KCOV_BIN="$(command -v kcov || true)"
fi

if [[ -z "$KCOV_BIN" ]] || [[ ! -x "$KCOV_BIN" ]]; then
  echo "Error: kcov binary not found. Set KCOV_BIN or install kcov first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$OUTPUT_DIR"

"$KCOV_BIN" \
  --verify \
  --bash-method=DEBUG \
  --include-pattern="$SCRIPT_DIR/lib/,$SCRIPT_DIR/install.sh,lib/,install.sh" \
  --exclude-pattern="$SCRIPT_DIR/tests,$SCRIPT_DIR/docs,$SCRIPT_DIR/.git,tests/,docs/,.git/" \
  "$OUTPUT_DIR" \
  "$@"
