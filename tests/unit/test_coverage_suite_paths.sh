#!/usr/bin/env bash
# tests/unit/test_coverage_suite_paths.sh - Unit tests for coverage_suite merged path resolution

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_SCRIPT="$PROJECT_ROOT/tests/ci/coverage_suite.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TMP_DIR=""

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  ✓ $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  ✗ $1"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" == "$actual" ]]; then
    pass "$message"
  else
    fail "$message (expected: $expected, got: $actual)"
  fi
}

write_xml() {
  local file="$1"
  cat >"$file" <<'EOF_XML'
<?xml version="1.0" ?>
<coverage line-rate="0.80" branch-rate="0" version="1.9" timestamp="1234">
  <packages/>
</coverage>
EOF_XML
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: coverage suite paths"
  echo "=========================================="

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

  # shellcheck disable=SC1090
  COVERAGE_SUITE_LIBRARY_MODE=1 source "$SUITE_SCRIPT"

  local merged_top="$TMP_DIR/merged-top"
  mkdir -p "$merged_top"
  write_xml "$merged_top/cobertura.xml"
  assert_equals \
    "$merged_top" \
    "$(resolve_coverage_report_dir "$merged_top")" \
    "resolves top-level cobertura.xml"

  local merged_nested="$TMP_DIR/merged-nested"
  mkdir -p "$merged_nested/kcov-merged"
  write_xml "$merged_nested/kcov-merged/cobertura.xml"
  assert_equals \
    "$merged_nested/kcov-merged" \
    "$(resolve_coverage_report_dir "$merged_nested")" \
    "resolves nested kcov-merged/cobertura.xml"

  cat >"$merged_nested/kcov-merged/index.html" <<'EOF_HTML'
<html><body>kcov</body></html>
EOF_HTML
  local normalized_dir
  normalized_dir="$(normalize_report_layout "$merged_nested/kcov-merged")"
  assert_equals "$merged_nested/kcov-merged" "$normalized_dir" "keeps resolved report directory"

  local merged_none="$TMP_DIR/merged-none"
  mkdir -p "$merged_none"
  local not_found=""
  set +e
  not_found="$(resolve_coverage_report_dir "$merged_none" 2>/dev/null)"
  local status=$?
  set -e
  if [[ $status -ne 0 && -z "$not_found" ]]; then
    pass "fails when cobertura.xml is absent"
  else
    fail "fails when cobertura.xml is absent (status=$status, value=$not_found)"
  fi

  echo ""
  echo "=========================================="
  echo "           Test Summary"
  echo "=========================================="
  echo "Total tests:  $TESTS_RUN"
  echo "Passed:       $TESTS_PASSED"
  echo "Failed:       $TESTS_FAILED"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "✓ All tests passed!"
    return 0
  fi

  echo ""
  echo "✗ Some tests failed"
  return 1
}

main "$@"
