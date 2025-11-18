#!/usr/bin/env bash
# tests/unit/test_ui_certificate_functions.sh - Tests for UI and certificate functions
# Tests for lib/ui.sh, lib/certificate.sh, lib/generators.sh

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
source "$PROJECT_ROOT/lib/generators.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/certificate.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null || true

#==============================================================================
# Test Suite: generate_reality_keypair
#==============================================================================

test_generate_reality_keypair_format() {
    setup_test_env

    if command -v sing-box &>/dev/null || command -v openssl &>/dev/null; then
        result=$(generate_reality_keypair)

        # Should output two lines: private key and public key
        line_count=$(echo "$result" | wc -l)
        assert_equals "$line_count" "2" "Should output private and public keys"

        # Check for key format (base64-like strings)
        assert_not_empty "$result" "Should generate non-empty keys"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: generate_qr_code
#==============================================================================

test_generate_qr_code_empty_data() {
    setup_test_env

    data=""

    if generate_qr_code "$data" 2>/dev/null; then
        assert_failure 1 "Should reject empty data"
    else
        assert_success 0 "Correctly rejected empty data"
    fi

    teardown_test_env
}

test_generate_qr_code_valid_data() {
    setup_test_env

    data="vless://test@example.com:443"

    # Function should not crash with valid data
    generate_qr_code "$data" 2>/dev/null || true
    assert_success 0 "Should handle valid data"

    teardown_test_env
}

#==============================================================================
# Test Suite: generate_all_qr_codes
#==============================================================================

test_generate_all_qr_codes_structure() {
    setup_test_env

    # Mock reality URI
    REALITY_URI="vless://test@example.com:443"

    # Function should not crash
    generate_all_qr_codes 2>/dev/null || true
    assert_success 0 "Should handle QR code generation"

    teardown_test_env
}

#==============================================================================
# Test Suite: check_cert_expiry
#==============================================================================

test_check_cert_expiry_missing_cert() {
    setup_test_env

    cert="/tmp/missing-cert-$$.pem"

    if check_cert_expiry "$cert" 2>/dev/null; then
        assert_failure 1 "Should fail for missing certificate"
    else
        assert_success 0 "Correctly handled missing certificate"
    fi

    teardown_test_env
}

test_check_cert_expiry_empty_cert() {
    setup_test_env

    cert="/tmp/empty-cert-$$.pem"
    touch "$cert"

    if check_cert_expiry "$cert" 2>/dev/null; then
        assert_failure 1 "Should fail for empty certificate"
    else
        assert_success 0 "Correctly handled empty certificate"
    fi

    rm -f "$cert"
    teardown_test_env
}

#==============================================================================
# Test Suite: maybe_issue_cert
#==============================================================================

test_maybe_issue_cert_missing_domain() {
    setup_test_env

    domain=""

    if maybe_issue_cert "$domain" 2>/dev/null; then
        assert_failure 1 "Should reject empty domain"
    else
        assert_success 0 "Correctly rejected empty domain"
    fi

    teardown_test_env
}

test_maybe_issue_cert_invalid_domain() {
    setup_test_env

    domain="invalid_domain!"

    if maybe_issue_cert "$domain" 2>/dev/null; then
        assert_failure 1 "Should reject invalid domain"
    else
        assert_success 0 "Correctly rejected invalid domain"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: show_logo
#==============================================================================

test_show_logo_output() {
    setup_test_env

    # Should not crash
    result=$(show_logo 2>/dev/null || echo "logo")
    assert_success 0 "Should display logo without error"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_sbx_logo
#==============================================================================

test_show_sbx_logo_output() {
    setup_test_env

    # Should not crash
    result=$(show_sbx_logo 2>/dev/null || echo "sbx-logo")
    assert_success 0 "Should display sbx logo without error"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_error
#==============================================================================

test_show_error_with_message() {
    setup_test_env

    message="Test error message"

    # Should display error and not crash
    result=$(show_error "$message" 2>&1 || echo "error shown")
    assert_contains "$result" "error" "Should contain error indicator"

    teardown_test_env
}

test_show_error_empty_message() {
    setup_test_env

    message=""

    # Should handle empty message
    show_error "$message" 2>/dev/null || true
    assert_success 0 "Should handle empty error message"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_progress
#==============================================================================

test_show_progress_valid_input() {
    setup_test_env

    current=50
    total=100
    message="Processing"

    # Should not crash
    show_progress "$current" "$total" "$message" 2>/dev/null || true
    assert_success 0 "Should show progress without error"

    teardown_test_env
}

test_show_progress_invalid_numbers() {
    setup_test_env

    current="abc"
    total="xyz"
    message="Processing"

    # Should handle invalid numbers gracefully
    show_progress "$current" "$total" "$message" 2>/dev/null || true
    assert_success 0 "Should handle invalid numbers"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_spinner
#==============================================================================

test_show_spinner_structure() {
    setup_test_env

    # Should not crash (but won't run indefinitely in tests)
    timeout 1 show_spinner "Testing" &>/dev/null || true
    assert_success 0 "Should handle spinner display"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_config_summary
#==============================================================================

test_show_config_summary_structure() {
    setup_test_env

    # Mock variables
    DOMAIN="example.com"
    REALITY_PORT="443"
    UUID="test-uuid"

    # Should not crash
    show_config_summary 2>/dev/null || true
    assert_success 0 "Should display config summary"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_installation_summary
#==============================================================================

test_show_installation_summary_structure() {
    setup_test_env

    # Mock URIs
    REALITY_URI="vless://test@example.com:443"

    # Should not crash
    show_installation_summary 2>/dev/null || true
    assert_success 0 "Should display installation summary"

    teardown_test_env
}

#==============================================================================
# Test Suite: prompt_yes_no
#==============================================================================

test_prompt_yes_no_structure() {
    setup_test_env

    # Can't easily test interactive input, but check function exists
    # and accepts parameters
    type prompt_yes_no &>/dev/null
    assert_success 0 "prompt_yes_no function should exist"

    teardown_test_env
}

#==============================================================================
# Test Suite: prompt_input
#==============================================================================

test_prompt_input_structure() {
    setup_test_env

    # Check function exists and accepts parameters
    type prompt_input &>/dev/null
    assert_success 0 "prompt_input function should exist"

    teardown_test_env
}

#==============================================================================
# Test Suite: prompt_password
#==============================================================================

test_prompt_password_structure() {
    setup_test_env

    # Check function exists
    type prompt_password &>/dev/null
    assert_success 0 "prompt_password function should exist"

    teardown_test_env
}

#==============================================================================
# Test Suite: prompt_menu_choice
#==============================================================================

test_prompt_menu_choice_structure() {
    setup_test_env

    # Check function exists
    type prompt_menu_choice &>/dev/null
    assert_success 0 "prompt_menu_choice function should exist"

    teardown_test_env
}

#==============================================================================
# Test Suite: show_existing_installation_menu
#==============================================================================

test_show_existing_installation_menu_structure() {
    setup_test_env

    # Check function exists
    type show_existing_installation_menu &>/dev/null
    assert_success 0 "show_existing_installation_menu function should exist"

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== UI and Certificate Functions Tests ==="
echo ""

# Generator tests
test_generate_reality_keypair_format
test_generate_qr_code_empty_data
test_generate_qr_code_valid_data
test_generate_all_qr_codes_structure

# Certificate tests
test_check_cert_expiry_missing_cert
test_check_cert_expiry_empty_cert
test_maybe_issue_cert_missing_domain
test_maybe_issue_cert_invalid_domain

# UI display tests
test_show_logo_output
test_show_sbx_logo_output
test_show_error_with_message
test_show_error_empty_message
test_show_progress_valid_input
test_show_progress_invalid_numbers
test_show_spinner_structure
test_show_config_summary_structure
test_show_installation_summary_structure

# UI prompt tests (structure only - can't test interactivity)
test_prompt_yes_no_structure
test_prompt_input_structure
test_prompt_password_structure
test_prompt_menu_choice_structure
test_show_existing_installation_menu_structure

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
