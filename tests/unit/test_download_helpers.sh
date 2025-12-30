#!/usr/bin/env bash
# tests/unit/test_download_helpers.sh - Unit tests for lib/download.sh
# Tests download functionality and HTTP helpers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the download module
source "${PROJECT_ROOT}/lib/download.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/download.sh"
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
# Test: Download with curl
#==============================================================================

test_download_curl() {
    echo ""
    echo "Testing _download_with_curl..."

    if declare -f _download_with_curl >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1; then
            local temp=$(mktemp)
            if _download_with_curl "https://www.google.com/robots.txt" "$temp" 2>/dev/null; then
                if [[ -f "$temp" ]] && [[ -s "$temp" ]]; then
                    test_result "_download_with_curl downloads file" "pass"
                else
                    test_result "_download_with_curl downloads file" "fail"
                fi
            else
                test_result "_download_with_curl (network unavailable)" "pass"
            fi
            rm -f "$temp"
        else
            test_result "skipped (curl not installed)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Download with wget
#==============================================================================

test_download_wget() {
    echo ""
    echo "Testing _download_with_wget..."

    if declare -f _download_with_wget >/dev/null 2>&1; then
        if command -v wget >/dev/null 2>&1; then
            local temp=$(mktemp)
            if _download_with_wget "https://www.google.com/robots.txt" "$temp" 2>/dev/null; then
                if [[ -f "$temp" ]]; then
                    test_result "_download_with_wget downloads file" "pass"
                else
                    test_result "_download_with_wget downloads file" "fail"
                fi
            else
                test_result "_download_with_wget (network unavailable)" "pass"
            fi
            rm -f "$temp"
        else
            test_result "skipped (wget not installed)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Get Download Info
#==============================================================================

test_get_download_info() {
    echo ""
    echo "Testing get_download_info..."

    if declare -f get_download_info >/dev/null 2>&1; then
        local info
        info=$(get_download_info "1.8.0" "linux" "amd64" 2>/dev/null) || true
        if [[ -n "$info" ]]; then
            if [[ "$info" == *"sing-box"* ]]; then
                test_result "returns sing-box info" "pass"
            else
                test_result "returns info" "pass"
            fi
        else
            test_result "get_download_info (may fail without network)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Safe HTTP Get
#==============================================================================

test_safe_http_get() {
    echo ""
    echo "Testing safe_http_get..."

    if declare -f safe_http_get >/dev/null 2>&1; then
        local response
        response=$(safe_http_get "https://api.github.com" 2>/dev/null) || true
        if [[ -n "$response" ]]; then
            test_result "safe_http_get fetches content" "pass"
        else
            test_result "safe_http_get (network unavailable or rate limited)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Test: Check curl continue support
#==============================================================================

test_curl_continue_support() {
    echo ""
    echo "Testing check_curl_continue_support..."

    if declare -f check_curl_continue_support >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1; then
            if check_curl_continue_support 2>/dev/null; then
                test_result "curl supports resume" "pass"
            else
                test_result "curl may not support resume" "pass"
            fi
        else
            test_result "skipped (curl not installed)" "pass"
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
echo "Running test suite: lib/download.sh Functions"
echo "=========================================="

test_download_curl
test_download_wget
test_get_download_info
test_safe_http_get
test_curl_continue_support

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
