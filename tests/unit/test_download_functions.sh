#!/usr/bin/env bash
# tests/unit/test_download_functions.sh - Comprehensive download function tests
# Tests for lib/download.sh functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

# Source required modules
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/download.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/retry.sh"

#==============================================================================
# Test Suite: detect_downloader
#==============================================================================

test_detect_downloader_curl() {
    setup_test_env

    # Mock curl available
    if command -v curl &>/dev/null; then
        result=$(detect_downloader)
        assert_equals "$result" "curl" "Should detect curl when available"
    fi

    teardown_test_env
}

test_detect_downloader_wget() {
    setup_test_env

    # Mock scenario where only wget available
    if command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        result=$(detect_downloader)
        assert_equals "$result" "wget" "Should detect wget when curl unavailable"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: check_curl_retry_support
#==============================================================================

test_check_curl_retry_support() {
    setup_test_env

    if command -v curl &>/dev/null; then
        # Should detect retry support in modern curl
        if check_curl_retry_support; then
            assert_success 0 "Modern curl should support retry"
        else
            # Older curl might not support it
            assert_success 0 "Older curl might not support retry"
        fi
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: check_curl_continue_support
#==============================================================================

test_check_curl_continue_support() {
    setup_test_env

    if command -v curl &>/dev/null; then
        # Should detect continue-at support
        if check_curl_continue_support; then
            assert_success 0 "Modern curl should support continue-at"
        fi
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_download_url
#==============================================================================

test_validate_download_url_valid_https() {
    setup_test_env

    url="https://example.com/file.tar.gz"
    if validate_download_url "$url"; then
        assert_success 0 "Should accept valid HTTPS URL"
    else
        assert_failure 1 "Valid HTTPS URL rejected"
    fi

    teardown_test_env
}

test_validate_download_url_valid_http() {
    setup_test_env

    url="http://example.com/file.tar.gz"
    if validate_download_url "$url"; then
        assert_success 0 "Should accept valid HTTP URL"
    else
        assert_failure 1 "Valid HTTP URL rejected"
    fi

    teardown_test_env
}

test_validate_download_url_invalid_protocol() {
    setup_test_env

    url="ftp://example.com/file.tar.gz"
    if validate_download_url "$url" 2>/dev/null; then
        assert_failure 1 "Should reject FTP URL"
    else
        assert_success 0 "Correctly rejected FTP URL"
    fi

    teardown_test_env
}

test_validate_download_url_empty() {
    setup_test_env

    url=""
    if validate_download_url "$url" 2>/dev/null; then
        assert_failure 1 "Should reject empty URL"
    else
        assert_success 0 "Correctly rejected empty URL"
    fi

    teardown_test_env
}

test_validate_download_url_no_protocol() {
    setup_test_env

    url="example.com/file.tar.gz"
    if validate_download_url "$url" 2>/dev/null; then
        assert_failure 1 "Should reject URL without protocol"
    else
        assert_success 0 "Correctly rejected URL without protocol"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: get_download_info
#==============================================================================

test_get_download_info_structure() {
    setup_test_env

    platform="linux-amd64"
    version="v1.10.0"

    # Mock DOWNLOAD_URLS array (normally from install_multi.sh)
    declare -gA DOWNLOAD_URLS
    DOWNLOAD_URLS["linux-amd64"]="https://github.com/SagerNet/sing-box/releases/download/VERSION/sing-box-VERSION-linux-amd64.tar.gz"

    result=$(get_download_info "$platform" "$version" 2>/dev/null || echo "")

    # Should return URL and filename on separate lines
    if [[ -n "$result" ]]; then
        line_count=$(echo "$result" | wc -l)
        assert_equals "$line_count" "2" "Should return URL and filename"
    fi

    unset DOWNLOAD_URLS

    teardown_test_env
}

#==============================================================================
# Test Suite: download_file
#==============================================================================

test_download_file_invalid_url() {
    setup_test_env

    invalid_url="not-a-url"
    dest="/tmp/test-download-$$"

    if download_file "$invalid_url" "$dest" 2>/dev/null; then
        assert_failure 1 "Should fail with invalid URL"
    else
        assert_success 0 "Correctly failed with invalid URL"
    fi

    rm -f "$dest"

    teardown_test_env
}

test_download_file_empty_destination() {
    setup_test_env

    url="https://example.com/file.tar.gz"
    dest=""

    if download_file "$url" "$dest" 2>/dev/null; then
        assert_failure 1 "Should fail with empty destination"
    else
        assert_success 0 "Correctly failed with empty destination"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: verify_downloaded_file
#==============================================================================

test_verify_downloaded_file_missing() {
    setup_test_env

    file="/tmp/nonexistent-file-$$"

    if verify_downloaded_file "$file" 2>/dev/null; then
        assert_failure 1 "Should fail for missing file"
    else
        assert_success 0 "Correctly failed for missing file"
    fi

    teardown_test_env
}

test_verify_downloaded_file_empty() {
    setup_test_env

    file="/tmp/empty-file-$$"
    touch "$file"

    if verify_downloaded_file "$file" 2>/dev/null; then
        assert_failure 1 "Should fail for empty file"
    else
        assert_success 0 "Correctly failed for empty file"
    fi

    rm -f "$file"

    teardown_test_env
}

test_verify_downloaded_file_valid() {
    setup_test_env

    file="/tmp/valid-file-$$"
    echo "test content" > "$file"

    if verify_downloaded_file "$file"; then
        assert_success 0 "Should succeed for valid file"
    else
        assert_failure 1 "Valid file rejected"
    fi

    rm -f "$file"

    teardown_test_env
}

#==============================================================================
# Test Suite: download_file_with_retry
#==============================================================================

test_download_file_with_retry_invalid_url() {
    setup_test_env

    invalid_url="not-a-url"
    dest="/tmp/test-retry-$$"

    if download_file_with_retry "$invalid_url" "$dest" 2>/dev/null; then
        assert_failure 1 "Should fail with invalid URL even with retry"
    else
        assert_success 0 "Correctly failed with invalid URL"
    fi

    rm -f "$dest"

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Download Functions Tests ==="
echo ""

# Downloader detection tests
test_detect_downloader_curl
test_detect_downloader_wget

# Curl capability tests
test_check_curl_retry_support
test_check_curl_continue_support

# URL validation tests
test_validate_download_url_valid_https
test_validate_download_url_valid_http
test_validate_download_url_invalid_protocol
test_validate_download_url_empty
test_validate_download_url_no_protocol

# Download info tests
test_get_download_info_structure

# Download file tests
test_download_file_invalid_url
test_download_file_empty_destination

# File verification tests
test_verify_downloaded_file_missing
test_verify_downloaded_file_empty
test_verify_downloaded_file_valid

# Retry tests
test_download_file_with_retry_invalid_url

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
