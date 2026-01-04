#!/usr/bin/env bash
# Unit tests for caddy module functions
# Tests: caddy_create_service, caddy_setup_auto_tls, caddy_wait_for_cert,
#        caddy_setup_cert_sync, caddy_create_renewal_hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test environment flag
export SBX_TEST_MODE=1

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Load required modules
source lib/common.sh 2> /dev/null || {
    echo "✗ Failed to load lib/common.sh"
    exit 1
}

source lib/caddy.sh 2> /dev/null || {
    echo "✗ Failed to load lib/caddy.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo ""
    echo "Test $((TOTAL_TESTS + 1)): $test_name"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if $test_func 2> /dev/null; then
        echo "✓ PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
  else
        echo "✗ FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
  fi
}

echo "=== Caddy Module Functions Unit Tests ==="

#==============================================================================
# Tests for caddy_create_service()
#==============================================================================

test_caddy_create_service_exists() {
    type caddy_create_service > /dev/null 2>&1
}

test_caddy_create_service_defined() {
    grep -q "caddy_create_service()" lib/caddy.sh
}

#==============================================================================
# Tests for caddy_setup_auto_tls()
#==============================================================================

test_caddy_setup_auto_tls_exists() {
    type caddy_setup_auto_tls > /dev/null 2>&1
}

test_caddy_setup_auto_tls_defined() {
    grep -q "caddy_setup_auto_tls()" lib/caddy.sh
}

#==============================================================================
# Tests for caddy_wait_for_cert()
#==============================================================================

test_caddy_wait_for_cert_exists() {
    type caddy_wait_for_cert > /dev/null 2>&1
}

test_caddy_wait_for_cert_defined() {
    grep -q "caddy_wait_for_cert()" lib/caddy.sh
}

#==============================================================================
# Tests for caddy_setup_cert_sync()
#==============================================================================

test_caddy_setup_cert_sync_exists() {
    type caddy_setup_cert_sync > /dev/null 2>&1
}

test_caddy_setup_cert_sync_defined() {
    grep -q "caddy_setup_cert_sync()" lib/caddy.sh
}

#==============================================================================
# Tests for caddy_create_renewal_hook()
#==============================================================================

test_caddy_create_renewal_hook_exists() {
    type caddy_create_renewal_hook > /dev/null 2>&1
}

test_caddy_create_renewal_hook_defined() {
    grep -q "caddy_create_renewal_hook()" lib/caddy.sh
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing caddy_create_service..."
run_test "Function exists" test_caddy_create_service_exists
run_test "Defined in caddy module" test_caddy_create_service_defined

echo ""
echo "Testing caddy_setup_auto_tls..."
run_test "Function exists" test_caddy_setup_auto_tls_exists
run_test "Defined in caddy module" test_caddy_setup_auto_tls_defined

echo ""
echo "Testing caddy_wait_for_cert..."
run_test "Function exists" test_caddy_wait_for_cert_exists
run_test "Defined in caddy module" test_caddy_wait_for_cert_defined

echo ""
echo "Testing caddy_setup_cert_sync..."
run_test "Function exists" test_caddy_setup_cert_sync_exists
run_test "Defined in caddy module" test_caddy_setup_cert_sync_defined

echo ""
echo "Testing caddy_create_renewal_hook..."
run_test "Function exists" test_caddy_create_renewal_hook_exists
run_test "Defined in caddy module" test_caddy_create_renewal_hook_defined

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "------------------------------------------"
echo "Total:   $TOTAL_TESTS"
echo "Passed:  $PASSED_TESTS"
echo "Failed:  $FAILED_TESTS"
echo "=========================================="

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi

exit 0
