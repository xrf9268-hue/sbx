#!/usr/bin/env bash
# tests/unit/test_install_protocol_validation.sh
# Regression tests for install.sh protocol validation paths.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test harness behavior checks.
set +e
set -o pipefail

# Source installer functions without executing main().
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install.sh" 2>/dev/null || {
  echo "ERROR: Failed to load install.sh"
  exit 1
}

# Disable cleanup traps from sourced modules to keep test control flow.
trap - EXIT INT TERM HUP QUIT ERR RETURN
set +e

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local name="$1"
  local status="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${status}" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${name}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${name}"
  fi
}

run_validate() {
  local reality_only="$1"
  local enable_reality="$2"
  local enable_ws="$3"
  local enable_hy2="$4"

  (
    REALITY_ONLY_MODE="${reality_only}"
    ENABLE_REALITY="${enable_reality}"
    ENABLE_WS="${enable_ws}"
    ENABLE_HY2="${enable_hy2}"
    _validate_protocol_config
  ) >/dev/null 2>&1
}

test_reality_only_valid() {
  run_validate "1" "1" "1" "1"
  if [[ $? -eq 0 ]]; then
    test_result "Reality-only mode accepts ENABLE_REALITY=1" "pass"
  else
    test_result "Reality-only mode accepts ENABLE_REALITY=1" "fail"
  fi
}

test_reality_only_invalid() {
  run_validate "1" "0" "1" "1"
  if [[ $? -ne 0 ]]; then
    test_result "Reality-only mode rejects ENABLE_REALITY=0" "pass"
  else
    test_result "Reality-only mode rejects ENABLE_REALITY=0" "fail"
  fi
}

test_domain_mode_invalid_all_disabled() {
  run_validate "0" "0" "0" "0"
  if [[ $? -ne 0 ]]; then
    test_result "Domain mode rejects all protocols disabled" "pass"
  else
    test_result "Domain mode rejects all protocols disabled" "fail"
  fi
}

test_domain_mode_valid_any_enabled() {
  run_validate "0" "0" "1" "0"
  if [[ $? -eq 0 ]]; then
    test_result "Domain mode accepts one enabled protocol" "pass"
  else
    test_result "Domain mode accepts one enabled protocol" "fail"
  fi
}

echo ""
echo "=========================================="
echo "Running test suite: install.sh Protocol Validation"
echo "=========================================="

test_reality_only_valid
test_reality_only_invalid
test_domain_mode_invalid_all_disabled
test_domain_mode_valid_any_enabled

echo ""
echo "=========================================="
echo "           Test Summary"
echo "=========================================="
echo "Total tests:  ${TESTS_RUN}"
echo "Passed:       ${TESTS_PASSED}"
echo "Failed:       ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
