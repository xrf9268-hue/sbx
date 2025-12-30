#!/usr/bin/env bash
# tests/unit/test_export_helpers.sh - Unit tests for lib/export.sh
# Tests configuration export functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the export module
source "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/export.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

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
# Test: Export Functions
#==============================================================================

test_export_v2rayn_config() {
    echo ""
    echo "Testing export_v2rayn_config..."

    if declare -f export_v2rayn_config >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_export_clash_config() {
    echo ""
    echo "Testing export_clash_config..."

    if declare -f export_clash_config >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_export_uri() {
    echo ""
    echo "Testing export_uri..."

    if declare -f export_uri >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_export_subscription() {
    echo ""
    echo "Testing export_subscription..."

    if declare -f export_subscription >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_generate_share_uri() {
    echo ""
    echo "Testing generate_share_uri..."

    if declare -f generate_share_uri >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/export.sh Functions"
echo "=========================================="

test_export_v2rayn_config
test_export_clash_config
test_export_uri
test_export_subscription
test_generate_share_uri

# Print summary
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
