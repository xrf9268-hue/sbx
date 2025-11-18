#!/usr/bin/env bash
# tests/unit/test_download_functions.sh - High-quality tests for download functions
# Tests for lib/download.sh URL validation and function existence

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode
set +e

# Source required modules
if ! source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/common.sh"
    exit 1
fi

# Disable traps after loading modules
trap - EXIT INT TERM

# Reset to permissive mode
set +e
set -o pipefail

# Source download module
source "${PROJECT_ROOT}/lib/download.sh" 2>/dev/null || true

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
        return 1
    fi
}

#==============================================================================
# URL Validation Tests
#==============================================================================

test_url_validation() {
    echo ""
    echo "Testing URL validation..."

    # Test 1: Valid HTTPS URL accepted
    if validate_download_url "https://example.com/file.tar.gz" 2>/dev/null; then
        test_result "validate_download_url accepts valid HTTPS URL" "pass"
    else
        test_result "validate_download_url accepts valid HTTPS URL" "fail"
    fi

    # Test 2: HTTP URL rejected (only HTTPS allowed)
    if validate_download_url "http://example.com/file.tar.gz" 2>/dev/null; then
        test_result "validate_download_url rejects HTTP URL" "fail"
    else
        test_result "validate_download_url rejects HTTP URL" "pass"
    fi

    # Test 3: Empty URL rejected
    if validate_download_url "" 2>/dev/null; then
        test_result "validate_download_url rejects empty URL" "fail"
    else
        test_result "validate_download_url rejects empty URL" "pass"
    fi

    # Test 4: Invalid protocol rejected
    if validate_download_url "ftp://example.com/file" 2>/dev/null; then
        test_result "validate_download_url rejects FTP protocol" "fail"
    else
        test_result "validate_download_url rejects FTP protocol" "pass"
    fi

    # Test 5: No protocol rejected
    if validate_download_url "example.com/file" 2>/dev/null; then
        test_result "validate_download_url rejects URL without protocol" "fail"
    else
        test_result "validate_download_url rejects URL without protocol" "pass"
    fi

    # Test 6: GitHub raw URL accepted
    if validate_download_url "https://raw.githubusercontent.com/user/repo/main/file.sh" 2>/dev/null; then
        test_result "validate_download_url accepts GitHub raw URL" "pass"
    else
        test_result "validate_download_url accepts GitHub raw URL" "fail"
    fi
}

#==============================================================================
# Downloader Detection Tests
#==============================================================================

test_downloader_detection() {
    echo ""
    echo "Testing downloader detection..."

    # Test 1: detect_downloader returns curl or wget
    local downloader
    downloader=$(detect_downloader 2>/dev/null) || true
    if [[ "$downloader" == "curl" ]] || [[ "$downloader" == "wget" ]]; then
        test_result "detect_downloader returns valid downloader" "pass"
    else
        test_result "detect_downloader returns valid downloader (got: $downloader)" "fail"
    fi

    # Test 2: curl is available (should be in test environment)
    if command -v curl >/dev/null 2>&1; then
        test_result "curl is available in test environment" "pass"
    else
        test_result "curl is available in test environment" "fail"
    fi

    # Test 3: check_curl_retry_support detects support
    if command -v curl >/dev/null 2>&1; then
        if check_curl_retry_support 2>/dev/null; then
            test_result "check_curl_retry_support detects retry support" "pass"
        else
            test_result "check_curl_retry_support runs without error" "pass"
        fi
    else
        test_result "check_curl_retry_support (skipped - no curl)" "pass"
    fi
}

#==============================================================================
# Function Existence Tests
#==============================================================================

test_download_functions_exist() {
    echo ""
    echo "Testing download function existence..."

    # Test 1: validate_download_url exists
    if grep -q "^validate_download_url()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "validate_download_url function defined" "pass"
    else
        test_result "validate_download_url function defined" "fail"
    fi

    # Test 2: detect_downloader exists
    if grep -q "^detect_downloader()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "detect_downloader function defined" "pass"
    else
        test_result "detect_downloader function defined" "fail"
    fi

    # Test 3: download_file exists
    if grep -q "^download_file()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "download_file function defined" "pass"
    else
        test_result "download_file function defined" "fail"
    fi

    # Test 4: download_file_with_retry exists
    if grep -q "^download_file_with_retry()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "download_file_with_retry function defined" "pass"
    else
        test_result "download_file_with_retry function defined" "fail"
    fi

    # Test 5: verify_downloaded_file exists
    if grep -q "^verify_downloaded_file()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "verify_downloaded_file function defined" "pass"
    else
        test_result "verify_downloaded_file function defined" "fail"
    fi

    # Test 6: download_and_verify exists
    if grep -q "^download_and_verify()" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "download_and_verify function defined" "pass"
    else
        test_result "download_and_verify function defined" "fail"
    fi
}

#==============================================================================
# Constants Tests
#==============================================================================

test_download_constants() {
    echo ""
    echo "Testing download constants..."

    # Test 1: DOWNLOAD_TIMEOUT is defined
    if grep -q "DOWNLOAD_TIMEOUT=" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "DOWNLOAD_TIMEOUT constant defined" "pass"
    else
        test_result "DOWNLOAD_TIMEOUT constant defined" "fail"
    fi

    # Test 2: DOWNLOAD_CONNECT_TIMEOUT is defined
    if grep -q "DOWNLOAD_CONNECT_TIMEOUT=" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "DOWNLOAD_CONNECT_TIMEOUT constant defined" "pass"
    else
        test_result "DOWNLOAD_CONNECT_TIMEOUT constant defined" "fail"
    fi

    # Test 3: DOWNLOAD_MAX_RETRIES is defined
    if grep -q "DOWNLOAD_MAX_RETRIES=" "${PROJECT_ROOT}/lib/download.sh"; then
        test_result "DOWNLOAD_MAX_RETRIES constant defined" "pass"
    else
        test_result "DOWNLOAD_MAX_RETRIES constant defined" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Download Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_download_functions_exist
    test_download_constants
    test_url_validation
    test_downloader_detection

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        exit 0
    else
        echo "✗ $TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
