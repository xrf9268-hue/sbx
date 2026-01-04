#!/usr/bin/env bash
# Unit tests for version functions in lib/version.sh
# Tests: get_singbox_version, version_meets_minimum

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

source lib/version.sh 2> /dev/null || {
    echo "✗ Failed to load lib/version.sh"
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

echo "=== Version Functions Unit Tests ==="

#==============================================================================
# Tests for version_meets_minimum()
#==============================================================================

test_version_meets_minimum_equal() {
    version_meets_minimum "1.8.0" "1.8.0"
}

test_version_meets_minimum_greater() {
    version_meets_minimum "1.12.0" "1.8.0"
}

test_version_meets_minimum_greater_minor() {
    version_meets_minimum "1.9.0" "1.8.0"
}

test_version_meets_minimum_greater_patch() {
    version_meets_minimum "1.8.5" "1.8.0"
}

test_version_meets_minimum_less_fails() {
    ! version_meets_minimum "1.7.0" "1.8.0"
}

test_version_meets_minimum_less_minor_fails() {
    ! version_meets_minimum "1.7.9" "1.8.0"
}

test_version_meets_minimum_with_v_prefix() {
    version_meets_minimum "v1.12.0" "v1.8.0"
}

test_version_meets_minimum_mixed_v_prefix() {
    version_meets_minimum "v1.12.0" "1.8.0"
}

test_version_meets_minimum_empty_fails() {
    ! version_meets_minimum "" "1.8.0"
}

test_version_meets_minimum_both_empty_fails() {
    ! version_meets_minimum "" ""
}

test_version_meets_minimum_prerelease() {
    # Pre-release version should still work for comparison
    version_meets_minimum "1.12.0-beta.1" "1.8.0"
}

#==============================================================================
# Tests for get_singbox_version()
#==============================================================================

test_get_singbox_version_missing_binary() {
    # When binary doesn't exist, should return error
    local SB_BIN="/nonexistent/sing-box"
    export SB_BIN
    ! get_singbox_version
}

test_get_singbox_version_function_exists() {
    # Just verify the function exists
    type get_singbox_version > /dev/null 2>&1
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing version_meets_minimum..."
run_test "Equal versions (1.8.0 >= 1.8.0)" test_version_meets_minimum_equal
run_test "Greater major (1.12.0 >= 1.8.0)" test_version_meets_minimum_greater
run_test "Greater minor (1.9.0 >= 1.8.0)" test_version_meets_minimum_greater_minor
run_test "Greater patch (1.8.5 >= 1.8.0)" test_version_meets_minimum_greater_patch
run_test "Less version fails (1.7.0 < 1.8.0)" test_version_meets_minimum_less_fails
run_test "Less minor fails (1.7.9 < 1.8.0)" test_version_meets_minimum_less_minor_fails
run_test "With v prefix (v1.12.0 >= v1.8.0)" test_version_meets_minimum_with_v_prefix
run_test "Mixed v prefix (v1.12.0 >= 1.8.0)" test_version_meets_minimum_mixed_v_prefix
run_test "Empty current fails" test_version_meets_minimum_empty_fails
run_test "Both empty fails" test_version_meets_minimum_both_empty_fails
run_test "Pre-release works (1.12.0-beta.1 >= 1.8.0)" test_version_meets_minimum_prerelease

echo ""
echo "Testing get_singbox_version..."
run_test "Missing binary returns error" test_get_singbox_version_missing_binary
run_test "Function exists" test_get_singbox_version_function_exists

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
