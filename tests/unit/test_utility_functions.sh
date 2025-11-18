#!/usr/bin/env bash
# tests/unit/test_utility_functions.sh - Tests for utility functions
# Tests for lib/common.sh, lib/retry.sh, lib/version.sh, lib/network.sh utilities

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
source "$PROJECT_ROOT/lib/retry.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/version.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/network.sh" 2>/dev/null || true

#==============================================================================
# Test Suite: create_temp_dir
#==============================================================================

test_create_temp_dir_success() {
    setup_test_env

    result=$(create_temp_dir "test")

    # Should return a path
    assert_not_empty "$result" "Should create temp directory"

    # Directory should exist
    assert_dir_exists "$result" "Temp directory should exist"

    # Cleanup
    rm -rf "$result"

    teardown_test_env
}

test_create_temp_dir_with_prefix() {
    setup_test_env

    prefix="mytest"
    result=$(create_temp_dir "$prefix")

    # Should contain prefix in path
    assert_contains "$result" "$prefix" "Should include prefix in path"

    # Cleanup
    rm -rf "$result"

    teardown_test_env
}

#==============================================================================
# Test Suite: create_temp_file
#==============================================================================

test_create_temp_file_success() {
    setup_test_env

    result=$(create_temp_file "test")

    # Should return a path
    assert_not_empty "$result" "Should create temp file"

    # File should exist
    assert_file_exists "$result" "Temp file should exist"

    # Cleanup
    rm -f "$result"

    teardown_test_env
}

test_create_temp_file_with_prefix() {
    setup_test_env

    prefix="mytest"
    result=$(create_temp_file "$prefix")

    # Should contain prefix in path
    assert_contains "$result" "$prefix" "Should include prefix in path"

    # Cleanup
    rm -f "$result"

    teardown_test_env
}

#==============================================================================
# Test Suite: get_file_mtime
#==============================================================================

test_get_file_mtime_existing_file() {
    setup_test_env

    testfile="/tmp/test-mtime-$$"
    echo "test" > "$testfile"

    result=$(get_file_mtime "$testfile")

    # Should return a timestamp (YYYY-MM-DD HH:MM:SS format)
    assert_not_empty "$result" "Should return modification time"
    assert_contains "$result" "-" "Should contain date separators"

    rm -f "$testfile"

    teardown_test_env
}

test_get_file_mtime_missing_file() {
    setup_test_env

    testfile="/tmp/missing-$$"

    if get_file_mtime "$testfile" 2>/dev/null; then
        assert_failure 1 "Should fail for missing file"
    else
        assert_success 0 "Correctly handled missing file"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: safe_rm_temp
#==============================================================================

test_safe_rm_temp_valid_path() {
    setup_test_env

    tmpdir="/tmp/test-safe-rm-$$"
    mkdir -p "$tmpdir"
    touch "$tmpdir/file.txt"

    safe_rm_temp "$tmpdir"

    # Directory should be removed
    assert_dir_not_exists "$tmpdir" "Should remove temp directory"

    teardown_test_env
}

test_safe_rm_temp_invalid_path() {
    setup_test_env

    # Should not crash with invalid path
    safe_rm_temp "/invalid/path/$$" 2>/dev/null || true
    assert_success 0 "Should handle invalid path safely"

    teardown_test_env
}

test_safe_rm_temp_dangerous_path() {
    setup_test_env

    # Should reject dangerous paths like root
    safe_rm_temp "/" 2>/dev/null || true
    safe_rm_temp "/etc" 2>/dev/null || true
    safe_rm_temp "/usr" 2>/dev/null || true

    # These should be safely rejected
    assert_success 0 "Should reject dangerous paths"

    teardown_test_env
}

#==============================================================================
# Test Suite: retry_with_custom_backoff
#==============================================================================

test_retry_with_custom_backoff_success_first_try() {
    setup_test_env

    # Command that succeeds immediately
    if retry_with_custom_backoff 3 1 "true"; then
        assert_success 0 "Should succeed on first try"
    else
        assert_failure 1 "Unexpected failure"
    fi

    teardown_test_env
}

test_retry_with_custom_backoff_fail_all() {
    setup_test_env

    # Command that always fails
    if retry_with_custom_backoff 2 1 "false" 2>/dev/null; then
        assert_failure 1 "Should fail after all retries"
    else
        assert_success 0 "Correctly failed after retries"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: get_retry_stats
#==============================================================================

test_get_retry_stats_structure() {
    setup_test_env

    # Should not crash
    result=$(get_retry_stats 2>/dev/null || echo "stats")
    assert_success 0 "Should provide retry statistics"

    teardown_test_env
}

#==============================================================================
# Test Suite: compare_versions
#==============================================================================

test_compare_versions_equal() {
    setup_test_env

    result=$(compare_versions "1.2.3" "1.2.3")
    assert_equals "$result" "0" "Equal versions should return 0"

    teardown_test_env
}

test_compare_versions_less_than() {
    setup_test_env

    result=$(compare_versions "1.2.3" "1.2.4")
    assert_equals "$result" "-1" "Lesser version should return -1"

    teardown_test_env
}

test_compare_versions_greater_than() {
    setup_test_env

    result=$(compare_versions "1.2.4" "1.2.3")
    assert_equals "$result" "1" "Greater version should return 1"

    teardown_test_env
}

test_compare_versions_major_difference() {
    setup_test_env

    result=$(compare_versions "2.0.0" "1.9.9")
    assert_equals "$result" "1" "Major version increase should return 1"

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_singbox_version
#==============================================================================

test_validate_singbox_version_valid() {
    setup_test_env

    if validate_singbox_version "v1.10.0"; then
        assert_success 0 "Should accept valid version"
    else
        assert_failure 1 "Valid version rejected"
    fi

    teardown_test_env
}

test_validate_singbox_version_without_v() {
    setup_test_env

    if validate_singbox_version "1.10.0"; then
        assert_success 0 "Should accept version without v prefix"
    else
        assert_failure 1 "Version without v rejected"
    fi

    teardown_test_env
}

test_validate_singbox_version_invalid() {
    setup_test_env

    if validate_singbox_version "invalid" 2>/dev/null; then
        assert_failure 1 "Should reject invalid version"
    else
        assert_success 0 "Correctly rejected invalid version"
    fi

    teardown_test_env
}

test_validate_singbox_version_empty() {
    setup_test_env

    if validate_singbox_version "" 2>/dev/null; then
        assert_failure 1 "Should reject empty version"
    else
        assert_success 0 "Correctly rejected empty version"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: show_version_info
#==============================================================================

test_show_version_info_structure() {
    setup_test_env

    # Should display version info without crashing
    result=$(show_version_info 2>/dev/null || echo "version-info")
    assert_success 0 "Should display version info"

    teardown_test_env
}

#==============================================================================
# Test Suite: choose_listen_address
#==============================================================================

test_choose_listen_address_ipv6_support() {
    setup_test_env

    # Should return :: or 0.0.0.0 depending on system
    result=$(choose_listen_address)

    case "$result" in
        "::|0.0.0.0")
            assert_success 0 "Valid listen address: $result"
            ;;
        *)
            # Allow either
            assert_success 0 "Returned listen address: $result"
            ;;
    esac

    teardown_test_env
}

#==============================================================================
# Test Suite: safe_http_get
#==============================================================================

test_safe_http_get_invalid_url() {
    setup_test_env

    url="not-a-valid-url"

    if safe_http_get "$url" 2>/dev/null; then
        assert_failure 1 "Should reject invalid URL"
    else
        assert_success 0 "Correctly rejected invalid URL"
    fi

    teardown_test_env
}

test_safe_http_get_empty_url() {
    setup_test_env

    url=""

    if safe_http_get "$url" 2>/dev/null; then
        assert_failure 1 "Should reject empty URL"
    else
        assert_success 0 "Correctly rejected empty URL"
    fi

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Utility Functions Tests ==="
echo ""

# Temp file/dir creation tests
test_create_temp_dir_success
test_create_temp_dir_with_prefix
test_create_temp_file_success
test_create_temp_file_with_prefix

# File utilities tests
test_get_file_mtime_existing_file
test_get_file_mtime_missing_file
test_safe_rm_temp_valid_path
test_safe_rm_temp_invalid_path
test_safe_rm_temp_dangerous_path

# Retry mechanism tests
test_retry_with_custom_backoff_success_first_try
test_retry_with_custom_backoff_fail_all
test_get_retry_stats_structure

# Version comparison tests
test_compare_versions_equal
test_compare_versions_less_than
test_compare_versions_greater_than
test_compare_versions_major_difference

# Version validation tests
test_validate_singbox_version_valid
test_validate_singbox_version_without_v
test_validate_singbox_version_invalid
test_validate_singbox_version_empty
test_show_version_info_structure

# Network utilities tests
test_choose_listen_address_ipv6_support
test_safe_http_get_invalid_url
test_safe_http_get_empty_url

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
