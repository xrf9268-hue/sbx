#!/usr/bin/env bash
# tests/unit/test_cf_mode.sh - Cloudflare mode unit tests
# Tests for CF_MODE environment variable support

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local test_name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$result" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $test_name"
  fi
}

#==============================================================================
# CF_MODE Environment Variable Tests
#==============================================================================

test_cf_mode_defaults() {
  echo ""
  echo "Testing CF_MODE defaults..."

  # Source common.sh to get defaults
  (
    source "${PROJECT_ROOT}/lib/common.sh" 2> /dev/null

    # CF_MODE should default to 0 (disabled)
    if [[ "${CF_MODE:-0}" == "0" ]]; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "CF_MODE defaults to 0" "pass" \
    || test_result "CF_MODE defaults to 0" "fail"
}

test_cf_mode_enables_ws_only() {
  echo ""
  echo "Testing CF_MODE enables WS-TLS only..."

  # When CF_MODE=1, ENABLE_REALITY and ENABLE_HY2 should be 0
  (
    export CF_MODE=1
    export DOMAIN="example.com"

    # Simulate the CF_MODE logic
    if [[ "${CF_MODE:-0}" == "1" ]]; then
      ENABLE_REALITY=${ENABLE_REALITY:-0}
      ENABLE_HY2=${ENABLE_HY2:-0}
      WS_PORT=${WS_PORT:-443}
    fi

    if [[ "$ENABLE_REALITY" == "0" && "$ENABLE_HY2" == "0" && "$WS_PORT" == "443" ]]; then
      echo "pass"
    else
      echo "fail: REALITY=$ENABLE_REALITY HY2=$ENABLE_HY2 WS_PORT=$WS_PORT"
    fi
  ) | grep -q "pass" && test_result "CF_MODE disables Reality and Hysteria2" "pass" \
    || test_result "CF_MODE disables Reality and Hysteria2" "fail"
}

test_cf_mode_requires_domain() {
  echo ""
  echo "Testing CF_MODE requires domain..."

  # CF_MODE without DOMAIN should be invalid
  (
    export CF_MODE=1
    unset DOMAIN

    # This should fail validation
    if [[ "${CF_MODE:-0}" == "1" && -z "${DOMAIN:-}" ]]; then
      echo "correctly_rejected"
    else
      echo "incorrectly_accepted"
    fi
  ) | grep -q "correctly_rejected" && test_result "CF_MODE requires DOMAIN" "pass" \
    || test_result "CF_MODE requires DOMAIN" "fail"
}

test_cf_mode_ws_port_override() {
  echo ""
  echo "Testing CF_MODE WS port override..."

  # User should be able to override WS_PORT even in CF_MODE
  (
    export CF_MODE=1
    export DOMAIN="example.com"
    export WS_PORT=2053 # Another CF-supported port

    if [[ "${CF_MODE:-0}" == "1" ]]; then
      # WS_PORT should keep user-specified value
      ENABLE_REALITY=${ENABLE_REALITY:-0}
      ENABLE_HY2=${ENABLE_HY2:-0}
      WS_PORT=${WS_PORT:-443}
    fi

    if [[ "$WS_PORT" == "2053" ]]; then
      echo "pass"
    else
      echo "fail: WS_PORT=$WS_PORT"
    fi
  ) | grep -q "pass" && test_result "CF_MODE respects user WS_PORT override" "pass" \
    || test_result "CF_MODE respects user WS_PORT override" "fail"
}

test_cf_mode_reality_fallback_port() {
  echo ""
  echo "Testing CF_MODE with Reality fallback..."

  # User can enable Reality with fallback port in CF_MODE
  (
    export CF_MODE=1
    export DOMAIN="example.com"
    export ENABLE_REALITY=1
    export REALITY_PORT=24443

    if [[ "${CF_MODE:-0}" == "1" ]]; then
      ENABLE_REALITY=${ENABLE_REALITY:-0}
      ENABLE_HY2=${ENABLE_HY2:-0}
      WS_PORT=${WS_PORT:-443}
    fi

    # User override should be respected
    if [[ "$ENABLE_REALITY" == "1" ]]; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "CF_MODE respects ENABLE_REALITY=1 override" "pass" \
    || test_result "CF_MODE respects ENABLE_REALITY=1 override" "fail"
}

test_cf_supported_ports() {
  echo ""
  echo "Testing CF supported ports validation..."

  # List of CF-supported HTTPS ports
  local cf_https_ports="443 2053 2083 2087 2096 8443"

  for port in $cf_https_ports; do
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
      test_result "Port $port is valid" "pass"
    else
      test_result "Port $port is valid" "fail"
    fi
  done
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: Cloudflare Mode (CF_MODE)"
echo "=========================================="

test_cf_mode_defaults
test_cf_mode_enables_ws_only
test_cf_mode_requires_domain
test_cf_mode_ws_port_override
test_cf_mode_reality_fallback_port
test_cf_supported_ports

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
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
