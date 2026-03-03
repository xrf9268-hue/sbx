#!/usr/bin/env bash
# tests/unit/test_coverage_gate.sh - Unit tests for tests/ci/coverage_gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_SCRIPT="$SCRIPT_DIR/tests/ci/coverage_gate.sh"

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

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local name="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail "$name (expected exit $expected, got $actual)"
  fi
}

create_xml() {
  local file="$1"
  local line_rate="$2"
  cat >"$file" <<EOF
<?xml version="1.0" ?>
<coverage line-rate="${line_rate}" branch-rate="0" version="1.9" timestamp="1234">
  <packages/>
</coverage>
EOF
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: coverage gate"
  echo "=========================================="

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

  # RED expectation for TDD: script must exist and execute.
  if [[ ! -x "$GATE_SCRIPT" ]]; then
    echo "  ✗ coverage gate script missing or not executable: $GATE_SCRIPT"
    echo ""
    echo "✗ Some tests failed"
    exit 1
  fi

  local xml_7999="$TMP_DIR/coverage-7999.xml"
  local xml_79995="$TMP_DIR/coverage-79995.xml"
  local xml_8000="$TMP_DIR/coverage-8000.xml"
  local xml_invalid="$TMP_DIR/coverage-invalid.xml"
  local metrics="$TMP_DIR/metrics.env"

  create_xml "$xml_7999" "0.7999"
  create_xml "$xml_79995" "0.79995"
  create_xml "$xml_8000" "0.8000"
  cat >"$xml_invalid" <<'EOF'
<?xml version="1.0" ?>
<coverage branch-rate="0" version="1.9" timestamp="1234">
  <packages/>
</coverage>
EOF

  set +e
  "$GATE_SCRIPT" --xml "$xml_7999" --min-percent 80 --metrics-file "$metrics" >/dev/null 2>&1
  assert_exit_code "1" "$?" "line-rate=0.7999 should fail gate"

  "$GATE_SCRIPT" --xml "$xml_79995" --min-percent 80 --metrics-file "$metrics" >/dev/null 2>&1
  assert_exit_code "1" "$?" "line-rate=0.79995 should fail gate before rounding"

  "$GATE_SCRIPT" --xml "$xml_8000" --min-percent 80 --metrics-file "$metrics" >/dev/null 2>&1
  assert_exit_code "0" "$?" "line-rate=0.8000 should pass gate"

  "$GATE_SCRIPT" --xml "$TMP_DIR/not-found.xml" --min-percent 80 --metrics-file "$metrics" >/dev/null 2>&1
  assert_exit_code "1" "$?" "missing xml should fail gate"

  "$GATE_SCRIPT" --xml "$xml_invalid" --min-percent 80 --metrics-file "$metrics" >/dev/null 2>&1
  assert_exit_code "1" "$?" "xml without line-rate should fail gate"
  set -e

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
