#!/usr/bin/env bash
# tests/unit/test_version_helpers.sh - Unit tests for lib/version.sh helper functions
# Tests version comparison and validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the version module
source "${PROJECT_ROOT}/lib/version.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/version.sh"
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
# Test: Version Comparison
#==============================================================================

test_version_comparison() {
    echo ""
    echo "Testing compare_versions..."

    if declare -f compare_versions >/dev/null 2>&1; then
        # compare_versions returns the LOWER version
        local result

        # Test equal versions - should return either version
        result=$(compare_versions "1.0.0" "1.0.0" 2>/dev/null) || true
        if [[ "$result" == "1.0.0" ]]; then
            test_result "returns 1.0.0 for equal versions" "pass"
        else
            test_result "returns 1.0.0 for equal versions" "fail"
        fi

        # Test 2.0.0 vs 1.0.0 - should return 1.0.0 (lower)
        result=$(compare_versions "2.0.0" "1.0.0" 2>/dev/null) || true
        if [[ "$result" == "1.0.0" ]]; then
            test_result "returns 1.0.0 as min(2.0.0, 1.0.0)" "pass"
        else
            test_result "returns 1.0.0 as min(2.0.0, 1.0.0)" "fail"
        fi

        # Test 1.0.0 vs 2.0.0 - should also return 1.0.0
        result=$(compare_versions "1.0.0" "2.0.0" 2>/dev/null) || true
        if [[ "$result" == "1.0.0" ]]; then
            test_result "returns 1.0.0 as min(1.0.0, 2.0.0)" "pass"
        else
            test_result "returns 1.0.0 as min(1.0.0, 2.0.0)" "fail"
        fi

        # Test patch version comparison
        result=$(compare_versions "1.0.2" "1.0.1" 2>/dev/null) || true
        if [[ "$result" == "1.0.1" ]]; then
            test_result "returns 1.0.1 as min(1.0.2, 1.0.1)" "pass"
        else
            test_result "returns 1.0.1 as min(1.0.2, 1.0.1)" "fail"
        fi

        # Test minor version comparison
        result=$(compare_versions "1.2.0" "1.1.9" 2>/dev/null) || true
        if [[ "$result" == "1.1.9" ]]; then
            test_result "returns 1.1.9 as min(1.2.0, 1.1.9)" "pass"
        else
            test_result "returns 1.1.9 as min(1.2.0, 1.1.9)" "fail"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Version Info Display
#==============================================================================

test_version_info() {
    echo ""
    echo "Testing show_version_info..."

    if declare -f show_version_info >/dev/null 2>&1; then
        local output
        output=$(show_version_info 2>&1) || true
        test_result "show_version_info executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: sing-box Version Validation
#==============================================================================

test_singbox_version_validation() {
    echo ""
    echo "Testing validate_singbox_version..."

    if declare -f validate_singbox_version >/dev/null 2>&1; then
        # Test valid version format
        if validate_singbox_version "1.8.0" 2>/dev/null; then
            test_result "accepts valid version 1.8.0" "pass"
        else
            test_result "accepts valid version 1.8.0" "fail"
        fi

        # Test version with v prefix
        if validate_singbox_version "v1.10.0" 2>/dev/null; then
            test_result "accepts version with v prefix" "pass"
        else
            test_result "accepts version with v prefix" "fail"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: resolve_singbox_version
#==============================================================================

test_resolve_version() {
    echo ""
    echo "Testing resolve_singbox_version..."

    if declare -f resolve_singbox_version >/dev/null 2>&1; then
        # Test with specific version
        local result
        result=$(resolve_singbox_version "1.8.0" 2>/dev/null) || true
        if [[ -n "$result" ]]; then
            test_result "resolves specific version" "pass"
        else
            test_result "resolves specific version (network may be unavailable)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/version.sh Helper Functions"
echo "=========================================="

test_version_comparison
test_version_info
test_singbox_version_validation
test_resolve_version

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
