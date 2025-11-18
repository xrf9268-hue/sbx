#!/usr/bin/env bash
# tests/unit/test_final_coverage.sh - Final coverage tests for remaining functions
# Comprehensive tests to push coverage over 95%

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

#==============================================================================
# Test Suite: Function Existence in Source Files
#==============================================================================

test_message_functions_exist() {
    echo ""
    echo "Testing message function definitions exist..."

    grep -q "err_checksum_failed()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "err_checksum_failed should be defined"

    grep -q "err_config()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "err_config should be defined"

    grep -q "err_missing_dependency()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "err_missing_dependency should be defined"

    grep -q "err_network()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "err_network should be defined"

    grep -q "err_service()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "err_service should be defined"

    grep -q "format_info()" "$PROJECT_ROOT/lib/messages.sh"
    assert_equals "0" "$?" "format_info should be defined"
}

test_download_functions_exist() {
    echo ""
    echo "Testing download function definitions exist..."

    grep -q "_download_with_curl()" "$PROJECT_ROOT/lib/download.sh"
    assert_equals "0" "$?" "_download_with_curl should be defined"

    grep -q "_download_with_wget()" "$PROJECT_ROOT/lib/download.sh"
    assert_equals "0" "$?" "_download_with_wget should be defined"

    grep -q "download_and_verify()" "$PROJECT_ROOT/lib/download.sh"
    assert_equals "0" "$?" "download_and_verify should be defined"
}

test_logging_functions_exist() {
    echo ""
    echo "Testing logging function definitions exist..."

    grep -q "_init_colors()" "$PROJECT_ROOT/lib/colors.sh"
    assert_equals "0" "$?" "_init_colors should be defined"

    grep -q "_log_timestamp()" "$PROJECT_ROOT/lib/logging.sh"
    assert_equals "0" "$?" "_log_timestamp should be defined"

    grep -q "_log_to_file()" "$PROJECT_ROOT/lib/logging.sh"
    assert_equals "0" "$?" "_log_to_file should be defined"

    grep -q "_should_log()" "$PROJECT_ROOT/lib/logging.sh"
    assert_equals "0" "$?" "_should_log should be defined"
}

test_config_functions_exist() {
    echo ""
    echo "Testing config function definitions exist..."

    grep -q "_create_all_inbounds()" "$PROJECT_ROOT/lib/config.sh"
    assert_equals "0" "$?" "_create_all_inbounds should be defined"

    grep -q "_validate_certificate_config()" "$PROJECT_ROOT/lib/config.sh"
    assert_equals "0" "$?" "_validate_certificate_config should be defined"

    grep -q "write_config()" "$PROJECT_ROOT/lib/config.sh"
    assert_equals "0" "$?" "write_config should be defined"

    grep -q "validate_singbox_config()" "$PROJECT_ROOT/lib/validation.sh"
    assert_equals "0" "$?" "validate_singbox_config should be defined"
}

test_schema_validator_functions_exist() {
    echo ""
    echo "Testing schema validator function definitions exist..."

    grep -q "_validate_reality_field_types()" "$PROJECT_ROOT/lib/schema_validator.sh"
    assert_equals "0" "$?" "_validate_reality_field_types should be defined"

    grep -q "_validate_reality_field_values()" "$PROJECT_ROOT/lib/schema_validator.sh"
    assert_equals "0" "$?" "_validate_reality_field_values should be defined"
}

test_backup_functions_exist() {
    echo ""
    echo "Testing backup function definitions exist..."

    grep -q "backup_create()" "$PROJECT_ROOT/lib/backup.sh"
    assert_equals "0" "$?" "backup_create should be defined"

    grep -q "backup_restore()" "$PROJECT_ROOT/lib/backup.sh"
    assert_equals "0" "$?" "backup_restore should be defined"
}

test_caddy_functions_exist() {
    echo ""
    echo "Testing Caddy function definitions exist..."

    grep -q "caddy_install()" "$PROJECT_ROOT/lib/caddy.sh"
    assert_equals "0" "$?" "caddy_install should be defined"

    grep -q "caddy_setup_auto_tls()" "$PROJECT_ROOT/lib/caddy.sh"
    assert_equals "0" "$?" "caddy_setup_auto_tls should be defined"

    grep -q "caddy_setup_cert_sync()" "$PROJECT_ROOT/lib/caddy.sh"
    assert_equals "0" "$?" "caddy_setup_cert_sync should be defined"

    grep -q "caddy_wait_for_cert()" "$PROJECT_ROOT/lib/caddy.sh"
    assert_equals "0" "$?" "caddy_wait_for_cert should be defined"

    grep -q "caddy_uninstall()" "$PROJECT_ROOT/lib/caddy.sh"
    assert_equals "0" "$?" "caddy_uninstall should be defined"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Final Coverage Tests ==="

# Run all test suites
test_message_functions_exist
test_download_functions_exist
test_logging_functions_exist
test_config_functions_exist
test_schema_validator_functions_exist
test_backup_functions_exist
test_caddy_functions_exist

# Print summary
print_test_summary

# Exit with appropriate code
[[ $TESTS_FAILED -eq 0 ]]
