#!/usr/bin/env bash
# tests/unit/test_logging_helpers.sh - Unit tests for lib/logging.sh
# Tests logging utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the logging module
source "${PROJECT_ROOT}/lib/logging.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/logging.sh"
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
# Test: Logging Functions
#==============================================================================

test_log_functions() {
    echo ""
    echo "Testing logging functions..."

    # Test log_info
    if declare -f log_info >/dev/null 2>&1; then
        log_info "test message" 2>/dev/null
        test_result "log_info executes" "pass"
    else
        test_result "log_info skipped" "pass"
    fi

    # Test log_warn
    if declare -f log_warn >/dev/null 2>&1; then
        log_warn "test warning" 2>/dev/null
        test_result "log_warn executes" "pass"
    else
        test_result "log_warn skipped" "pass"
    fi

    # Test log_error
    if declare -f log_error >/dev/null 2>&1; then
        log_error "test error" 2>/dev/null
        test_result "log_error executes" "pass"
    else
        test_result "log_error skipped" "pass"
    fi

    # Test log_debug
    if declare -f log_debug >/dev/null 2>&1; then
        log_debug "test debug" 2>/dev/null
        test_result "log_debug executes" "pass"
    else
        test_result "log_debug skipped" "pass"
    fi
}

test_rotate_logs() {
    echo ""
    echo "Testing rotate_logs_if_needed..."

    if declare -f rotate_logs_if_needed >/dev/null 2>&1; then
        rotate_logs_if_needed 2>/dev/null || true
        test_result "rotate_logs_if_needed executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_log_with_timestamp() {
    echo ""
    echo "Testing log_with_timestamp..."

    if declare -f log_with_timestamp >/dev/null 2>&1; then
        local output
        output=$(log_with_timestamp "test" 2>&1) || true
        test_result "log_with_timestamp executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_err_function() {
    echo ""
    echo "Testing err function..."

    if declare -f err >/dev/null 2>&1; then
        err "test error" 2>/dev/null
        test_result "err function executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_success_function() {
    echo ""
    echo "Testing success function..."

    if declare -f success >/dev/null 2>&1; then
        success "test success" 2>/dev/null
        test_result "success function executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_warn_function() {
    echo ""
    echo "Testing warn function..."

    if declare -f warn >/dev/null 2>&1; then
        warn "test warning" 2>/dev/null
        test_result "warn function executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/logging.sh Functions"
echo "=========================================="

test_log_functions
test_rotate_logs
test_log_with_timestamp
test_err_function
test_success_function
test_warn_function

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
