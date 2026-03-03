#!/usr/bin/env bash
# tests/unit/test_install_sni_validation.sh
# Unit tests for install.sh SNI selection/validation flow.

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

test_reality_disabled_skips_sni_probe() {
  (
    ENABLE_REALITY=0
    unset SNI SNI_DOMAIN
    select_reality_sni_domain() { return 99; }
    _configure_reality_sni
    [[ $? -eq 0 ]] && [[ "${SNI}" == "${SNI_DEFAULT}" ]]
  ) >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    test_result "Reality disabled skips SNI probe and keeps default" "pass"
  else
    test_result "Reality disabled skips SNI probe and keeps default" "fail"
  fi
}

test_explicit_sni_selected() {
  (
    ENABLE_REALITY=1
    SNI_DOMAIN="edge.example.com"
    unset SNI
    select_reality_sni_domain() {
      [[ "$1" == "edge.example.com" ]] || return 1
      echo "edge.example.com"
      return 0
    }
    _configure_reality_sni
    [[ $? -eq 0 ]] && [[ "${SNI}" == "edge.example.com" ]]
  ) >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    test_result "Explicit SNI_DOMAIN is selected when validation succeeds" "pass"
  else
    test_result "Explicit SNI_DOMAIN is selected when validation succeeds" "fail"
  fi
}

test_auto_fallback_sni_selected() {
  (
    ENABLE_REALITY=1
    unset SNI SNI_DOMAIN SNI_FALLBACK_DOMAINS
    select_reality_sni_domain() {
      [[ "$1" == "www.microsoft.com" ]] || return 1
      echo "www.apple.com"
      return 0
    }
    _configure_reality_sni
    [[ $? -eq 0 ]] && [[ "${SNI}" == "www.apple.com" ]]
  ) >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    test_result "Auto mode can switch to fallback SNI" "pass"
  else
    test_result "Auto mode can switch to fallback SNI" "fail"
  fi
}

test_explicit_sni_failure_aborts() {
  (
    ENABLE_REALITY=1
    SNI_DOMAIN="blocked.example.com"
    unset SNI
    select_reality_sni_domain() { return 1; }
    _configure_reality_sni
  ) >/dev/null 2>&1

  if [[ $? -ne 0 ]]; then
    test_result "Explicit SNI_DOMAIN failure aborts material generation" "pass"
  else
    test_result "Explicit SNI_DOMAIN failure aborts material generation" "fail"
  fi
}

test_auto_mode_all_fail_keeps_default() {
  (
    ENABLE_REALITY=1
    unset SNI SNI_DOMAIN SNI_FALLBACK_DOMAINS
    select_reality_sni_domain() { return 1; }
    _configure_reality_sni
    [[ $? -eq 0 ]] && [[ "${SNI}" == "${SNI_DEFAULT}" ]]
  ) >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    test_result "Auto mode keeps default SNI when all probes fail" "pass"
  else
    test_result "Auto mode keeps default SNI when all probes fail" "fail"
  fi
}

echo ""
echo "=========================================="
echo "Running test suite: install.sh SNI Validation"
echo "=========================================="

test_reality_disabled_skips_sni_probe
test_explicit_sni_selected
test_auto_fallback_sni_selected
test_explicit_sni_failure_aborts
test_auto_mode_all_fail_keeps_default

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
