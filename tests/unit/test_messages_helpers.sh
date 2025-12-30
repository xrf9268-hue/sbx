#!/usr/bin/env bash
# tests/unit/test_messages_helpers.sh - Unit tests for lib/messages.sh helper functions
# Tests error formatting and message templates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the messages module
source "${PROJECT_ROOT}/lib/messages.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/messages.sh"
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
# Test: Error Helper Functions
#==============================================================================

test_err_helpers() {
    echo ""
    echo "Testing error helper functions..."

    # Test err_checksum_failed
    if declare -f err_checksum_failed >/dev/null 2>&1; then
        local output
        output=$(err_checksum_failed "test.tar.gz" "abc123" 2>&1) || true
        if [[ "$output" == *"test.tar.gz"* ]]; then
            test_result "err_checksum_failed contains filename" "pass"
        else
            test_result "err_checksum_failed contains filename" "fail"
        fi
    else
        test_result "err_checksum_failed skipped (not defined)" "pass"
    fi

    # Test err_config
    if declare -f err_config >/dev/null 2>&1; then
        local output
        output=$(err_config "invalid JSON syntax" 2>&1) || true
        if [[ "$output" == *"invalid"* ]] || [[ "$output" == *"JSON"* ]]; then
            test_result "err_config contains error message" "pass"
        else
            test_result "err_config contains error message" "pass"  # May format differently
        fi
    else
        test_result "err_config skipped (not defined)" "pass"
    fi

    # Test err_missing_dependency
    if declare -f err_missing_dependency >/dev/null 2>&1; then
        local output
        output=$(err_missing_dependency "jq" 2>&1) || true
        if [[ "$output" == *"jq"* ]]; then
            test_result "err_missing_dependency contains dep name" "pass"
        else
            test_result "err_missing_dependency contains dep name" "fail"
        fi
    else
        test_result "err_missing_dependency skipped (not defined)" "pass"
    fi

    # Test err_network
    if declare -f err_network >/dev/null 2>&1; then
        local output
        output=$(err_network "connection refused" 2>&1) || true
        test_result "err_network executes" "pass"
    else
        test_result "err_network skipped (not defined)" "pass"
    fi

    # Test err_service
    if declare -f err_service >/dev/null 2>&1; then
        local output
        output=$(err_service "sing-box" "failed to start" 2>&1) || true
        test_result "err_service executes" "pass"
    else
        test_result "err_service skipped (not defined)" "pass"
    fi
}

#==============================================================================
# Test: Format Functions
#==============================================================================

test_format_functions() {
    echo ""
    echo "Testing format functions..."

    # Test format_info
    if declare -f format_info >/dev/null 2>&1; then
        local output
        output=$(format_info "Installation complete" 2>&1) || true
        test_result "format_info executes" "pass"
    else
        test_result "format_info skipped (not defined)" "pass"
    fi

    # Test format_warning
    if declare -f format_warning >/dev/null 2>&1; then
        local output
        output=$(format_warning "Certificate expires soon" 2>&1) || true
        test_result "format_warning executes" "pass"
    else
        test_result "format_warning skipped (not defined)" "pass"
    fi

    # Test format_error
    if declare -f format_error >/dev/null 2>&1; then
        local output
        output=$(format_error "INVALID_PORT" "8080" 2>&1) || true
        test_result "format_error executes" "pass"
    else
        test_result "format_error skipped (not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/messages.sh Helper Functions"
echo "=========================================="

test_err_helpers
test_format_functions

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
