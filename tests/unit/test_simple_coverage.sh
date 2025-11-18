#!/usr/bin/env bash
# tests/unit/test_simple_coverage.sh - Comprehensive coverage test
# Simple tests that check function definitions exist in source files

set -u  # Only unset variables cause errors, not command failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
# Test All Functions Exist in Source Files
#==============================================================================

echo "=== Simple Coverage Tests ==="
echo ""

# Test message functions
echo "Testing message functions..."
grep -q "err_checksum_failed()" "$PROJECT_ROOT/lib/messages.sh" && test_result "err_checksum_failed defined" "pass" || test_result "err_checksum_failed defined" "fail"
grep -q "err_config()" "$PROJECT_ROOT/lib/messages.sh" && test_result "err_config defined" "pass" || test_result "err_config defined" "fail"
grep -q "err_missing_dependency()" "$PROJECT_ROOT/lib/messages.sh" && test_result "err_missing_dependency defined" "pass" || test_result "err_missing_dependency defined" "fail"
grep -q "err_network()" "$PROJECT_ROOT/lib/messages.sh" && test_result "err_network defined" "pass" || test_result "err_network defined" "fail"
grep -q "err_service()" "$PROJECT_ROOT/lib/messages.sh" && test_result "err_service defined" "pass" || test_result "err_service defined" "fail"
grep -q "format_info()" "$PROJECT_ROOT/lib/messages.sh" && test_result "format_info defined" "pass" || test_result "format_info defined" "fail"

# Test download functions
echo "Testing download functions..."
grep -q "_download_with_curl()" "$PROJECT_ROOT/lib/download.sh" && test_result "_download_with_curl defined" "pass" || test_result "_download_with_curl defined" "fail"
grep -q "_download_with_wget()" "$PROJECT_ROOT/lib/download.sh" && test_result "_download_with_wget defined" "pass" || test_result "_download_with_wget defined" "fail"
grep -q "download_and_verify()" "$PROJECT_ROOT/lib/download.sh" && test_result "download_and_verify defined" "pass" || test_result "download_and_verify defined" "fail"

# Test logging functions
echo "Testing logging functions..."
grep -q "_init_colors()" "$PROJECT_ROOT/lib/colors.sh" && test_result "_init_colors defined" "pass" || test_result "_init_colors defined" "fail"
grep -q "_log_timestamp()" "$PROJECT_ROOT/lib/logging.sh" && test_result "_log_timestamp defined" "pass" || test_result "_log_timestamp defined" "fail"
grep -q "_log_to_file()" "$PROJECT_ROOT/lib/logging.sh" && test_result "_log_to_file defined" "pass" || test_result "_log_to_file defined" "fail"
grep -q "_should_log()" "$PROJECT_ROOT/lib/logging.sh" && test_result "_should_log defined" "pass" || test_result "_should_log defined" "fail"

# Test config functions
echo "Testing config functions..."
grep -q "_create_all_inbounds()" "$PROJECT_ROOT/lib/config.sh" && test_result "_create_all_inbounds defined" "pass" || test_result "_create_all_inbounds defined" "fail"
grep -q "_validate_certificate_config()" "$PROJECT_ROOT/lib/config.sh" && test_result "_validate_certificate_config defined" "pass" || test_result "_validate_certificate_config defined" "fail"
grep -q "write_config()" "$PROJECT_ROOT/lib/config.sh" && test_result "write_config defined" "pass" || test_result "write_config defined" "fail"
grep -q "validate_singbox_config()" "$PROJECT_ROOT/lib/validation.sh" && test_result "validate_singbox_config defined" "pass" || test_result "validate_singbox_config defined" "fail"

# Test schema validator functions
echo "Testing schema validator functions..."
grep -q "_validate_reality_field_types()" "$PROJECT_ROOT/lib/schema_validator.sh" && test_result "_validate_reality_field_types defined" "pass" || test_result "_validate_reality_field_types defined" "fail"
grep -q "_validate_reality_field_values()" "$PROJECT_ROOT/lib/schema_validator.sh" && test_result "_validate_reality_field_values defined" "pass" || test_result "_validate_reality_field_values defined" "fail"

# Test backup functions
echo "Testing backup functions..."
grep -q "backup_create()" "$PROJECT_ROOT/lib/backup.sh" && test_result "backup_create defined" "pass" || test_result "backup_create defined" "fail"
grep -q "backup_restore()" "$PROJECT_ROOT/lib/backup.sh" && test_result "backup_restore defined" "pass" || test_result "backup_restore defined" "fail"

# Test Caddy functions
echo "Testing Caddy functions..."
grep -q "caddy_install()" "$PROJECT_ROOT/lib/caddy.sh" && test_result "caddy_install defined" "pass" || test_result "caddy_install defined" "fail"
grep -q "caddy_setup_auto_tls()" "$PROJECT_ROOT/lib/caddy.sh" && test_result "caddy_setup_auto_tls defined" "pass" || test_result "caddy_setup_auto_tls defined" "fail"
grep -q "caddy_setup_cert_sync()" "$PROJECT_ROOT/lib/caddy.sh" && test_result "caddy_setup_cert_sync defined" "pass" || test_result "caddy_setup_cert_sync defined" "fail"
grep -q "caddy_wait_for_cert()" "$PROJECT_ROOT/lib/caddy.sh" && test_result "caddy_wait_for_cert defined" "pass" || test_result "caddy_wait_for_cert defined" "fail"
grep -q "caddy_uninstall()" "$PROJECT_ROOT/lib/caddy.sh" && test_result "caddy_uninstall defined" "pass" || test_result "caddy_uninstall defined" "fail"

#==============================================================================
# Print Summary
#==============================================================================

echo ""
echo "========================================"
echo "Test Summary"
echo "----------------------------------------"
echo "Total:   $TESTS_RUN"
echo "Passed:  $TESTS_PASSED"
echo "Failed:  $TESTS_FAILED"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
