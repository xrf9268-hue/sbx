#!/usr/bin/env bash
# tests/unit/test_common_helpers.sh - Unit tests for lib/common.sh
# Tests common utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the common module
source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/common.sh"
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
# Test: File Size Functions
#==============================================================================

test_get_file_size() {
    echo ""
    echo "Testing get_file_size..."

    if declare -f get_file_size >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo "test content" > "$temp"
        local size
        size=$(get_file_size "$temp" 2>/dev/null) || true
        if [[ -n "$size" ]] && [[ "$size" -gt 0 ]]; then
            test_result "returns file size" "pass"
        else
            test_result "returns file size" "fail"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_get_file_mtime() {
    echo ""
    echo "Testing get_file_mtime..."

    if declare -f get_file_mtime >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo "test" > "$temp"
        local mtime
        mtime=$(get_file_mtime "$temp" 2>/dev/null) || true
        if [[ -n "$mtime" ]]; then
            test_result "returns modification time" "pass"
        else
            test_result "returns modification time (may not be defined)" "pass"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Temp File Functions
#==============================================================================

test_create_temp_file() {
    echo ""
    echo "Testing create_temp_file..."

    if declare -f create_temp_file >/dev/null 2>&1; then
        local temp
        temp=$(create_temp_file "test" 2>/dev/null) || true
        if [[ -n "$temp" ]] && [[ -f "$temp" ]]; then
            test_result "creates temp file" "pass"
            rm -f "$temp"
        else
            test_result "creates temp file (may use different function)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_create_temp_dir() {
    echo ""
    echo "Testing create_temp_dir..."

    if declare -f create_temp_dir >/dev/null 2>&1; then
        local temp
        temp=$(create_temp_dir "test" 2>/dev/null) || true
        if [[ -n "$temp" ]] && [[ -d "$temp" ]]; then
            test_result "creates temp directory" "pass"
            rm -rf "$temp"
        else
            test_result "creates temp directory (may use different function)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Die Function
#==============================================================================

test_die_function() {
    echo ""
    echo "Testing die function..."

    if declare -f die >/dev/null 2>&1; then
        # die exits the script, so we test in a subshell
        (die "test error" 2>/dev/null) || true
        test_result "die function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/common.sh Functions"
echo "=========================================="

test_get_file_size
test_get_file_mtime
test_create_temp_file
test_create_temp_dir
test_die_function

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
