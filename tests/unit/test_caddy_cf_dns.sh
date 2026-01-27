#!/usr/bin/env bash
# tests/unit/test_caddy_cf_dns.sh - Caddy with Cloudflare DNS plugin tests
# Tests for caddy_install_with_cf_dns() and caddy_setup_dns_challenge()

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
# Test: caddy_install_with_cf_dns function exists
#==============================================================================

test_caddy_install_with_cf_dns_exists() {
  echo ""
  echo "Testing caddy_install_with_cf_dns function exists..."

  (
    source "${PROJECT_ROOT}/lib/caddy.sh" 2> /dev/null
    if declare -f caddy_install_with_cf_dns > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "caddy_install_with_cf_dns function exists" "pass" \
    || test_result "caddy_install_with_cf_dns function exists" "fail"
}

#==============================================================================
# Test: caddy_setup_dns_challenge function exists
#==============================================================================

test_caddy_setup_dns_challenge_exists() {
  echo ""
  echo "Testing caddy_setup_dns_challenge function exists..."

  (
    source "${PROJECT_ROOT}/lib/caddy.sh" 2> /dev/null
    if declare -f caddy_setup_dns_challenge > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "caddy_setup_dns_challenge function exists" "pass" \
    || test_result "caddy_setup_dns_challenge function exists" "fail"
}

#==============================================================================
# Test: caddy_create_service_with_env function exists
#==============================================================================

test_caddy_create_service_with_env_exists() {
  echo ""
  echo "Testing caddy_create_service_with_env function exists..."

  (
    source "${PROJECT_ROOT}/lib/caddy.sh" 2> /dev/null
    if declare -f caddy_create_service_with_env > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "caddy_create_service_with_env function exists" "pass" \
    || test_result "caddy_create_service_with_env function exists" "fail"
}

#==============================================================================
# Test: CF_DNS_CADDY_DOWNLOAD_URL constant pattern exists
#==============================================================================

test_cf_dns_caddy_download_url_pattern() {
  echo ""
  echo "Testing Caddy CF DNS download uses caddyserver.com API..."

  # Check if the caddy.sh file contains reference to caddyserver.com/api/download
  if grep -q "caddyserver.com/api/download" "${PROJECT_ROOT}/lib/caddy.sh"; then
    test_result "Caddy CF DNS uses caddyserver.com API" "pass"
  else
    test_result "Caddy CF DNS uses caddyserver.com API" "fail"
  fi
}

#==============================================================================
# Test: caddy_setup_dns_challenge generates valid Caddyfile structure
#==============================================================================

test_caddyfile_dns_challenge_structure() {
  echo ""
  echo "Testing Caddyfile DNS challenge structure..."

  # Check if caddy.sh contains the dns cloudflare directive pattern
  if grep -q "dns cloudflare" "${PROJECT_ROOT}/lib/caddy.sh"; then
    test_result "Caddyfile contains 'dns cloudflare' directive" "pass"
  else
    test_result "Caddyfile contains 'dns cloudflare' directive" "fail"
  fi
}

#==============================================================================
# Test: caddy_create_service_with_env includes Environment directive
#==============================================================================

test_systemd_service_has_environment() {
  echo ""
  echo "Testing systemd service includes Environment directive..."

  # Check if caddy.sh contains Environment directive in service template
  if grep -q 'Environment=' "${PROJECT_ROOT}/lib/caddy.sh"; then
    test_result "Systemd service has Environment directive" "pass"
  else
    test_result "Systemd service has Environment directive" "fail"
  fi
}

#==============================================================================
# Test: certificate.sh supports cf_dns CERT_MODE
#==============================================================================

test_certificate_supports_cf_dns_mode() {
  echo ""
  echo "Testing certificate.sh supports cf_dns CERT_MODE..."

  # Check if certificate.sh has cf_dns case
  if grep -q 'cf_dns)' "${PROJECT_ROOT}/lib/certificate.sh"; then
    test_result "certificate.sh has cf_dns case" "pass"
  else
    test_result "certificate.sh has cf_dns case" "fail"
  fi
}

#==============================================================================
# Test: caddy_install_with_cf_dns includes plugin module
#==============================================================================

test_caddy_cf_dns_includes_plugin() {
  echo ""
  echo "Testing caddy_install_with_cf_dns includes cloudflare plugin..."

  # Check if caddy.sh includes caddy-dns/cloudflare module reference
  if grep -q "caddy-dns/cloudflare" "${PROJECT_ROOT}/lib/caddy.sh"; then
    test_result "Includes caddy-dns/cloudflare module" "pass"
  else
    test_result "Includes caddy-dns/cloudflare module" "fail"
  fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: Caddy CF DNS Plugin"
echo "=========================================="

test_caddy_install_with_cf_dns_exists
test_caddy_setup_dns_challenge_exists
test_caddy_create_service_with_env_exists
test_cf_dns_caddy_download_url_pattern
test_caddyfile_dns_challenge_structure
test_systemd_service_has_environment
test_certificate_supports_cf_dns_mode
test_caddy_cf_dns_includes_plugin

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
