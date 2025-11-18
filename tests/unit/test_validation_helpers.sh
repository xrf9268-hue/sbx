#!/usr/bin/env bash
# tests/unit/test_validation_helpers.sh - Tests for validation helper functions
# Tests for lib/validation.sh helper functions

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
source "$PROJECT_ROOT/lib/tools.sh"

#==============================================================================
# Test Suite: require_all
#==============================================================================

test_require_all_success() {
    setup_test_env

    VAR1="value1"
    VAR2="value2"
    VAR3="value3"

    if require_all VAR1 VAR2 VAR3; then
        assert_success 0 "Should succeed when all variables set"
    else
        assert_failure 1 "require_all failed unexpectedly"
    fi

    teardown_test_env
}

test_require_all_one_missing() {
    setup_test_env

    VAR1="value1"
    VAR2=""
    VAR3="value3"

    if require_all VAR1 VAR2 VAR3 2>/dev/null; then
        assert_failure 1 "Should fail when one variable empty"
    else
        assert_success 0 "Correctly rejected empty variable"
    fi

    teardown_test_env
}

test_require_all_all_missing() {
    setup_test_env

    VAR1=""
    VAR2=""
    VAR3=""

    if require_all VAR1 VAR2 VAR3 2>/dev/null; then
        assert_failure 1 "Should fail when all variables empty"
    else
        assert_success 0 "Correctly rejected all empty variables"
    fi

    teardown_test_env
}

test_require_all_no_parameters() {
    setup_test_env

    if require_all 2>/dev/null; then
        assert_failure 1 "Should fail with no parameters"
    else
        assert_success 0 "Correctly handled no parameters"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: require_valid
#==============================================================================

test_require_valid_success() {
    setup_test_env

    PORT="443"

    if require_valid "PORT" "$PORT" "Port number" validate_port; then
        assert_success 0 "Should succeed with valid port"
    else
        assert_failure 1 "require_valid failed unexpectedly"
    fi

    teardown_test_env
}

test_require_valid_invalid_value() {
    setup_test_env

    PORT="99999"

    if require_valid "PORT" "$PORT" "Port number" validate_port 2>/dev/null; then
        assert_failure 1 "Should fail with invalid port"
    else
        assert_success 0 "Correctly rejected invalid port"
    fi

    teardown_test_env
}

test_require_valid_empty_value() {
    setup_test_env

    PORT=""

    if require_valid "PORT" "$PORT" "Port number" validate_port 2>/dev/null; then
        assert_failure 1 "Should fail with empty value"
    else
        assert_success 0 "Correctly rejected empty value"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: sanitize_input
#==============================================================================

test_sanitize_input_clean() {
    setup_test_env

    input="clean-input_123"
    result=$(sanitize_input "$input")

    assert_equals "$result" "$input" "Clean input should pass through unchanged"

    teardown_test_env
}

test_sanitize_input_with_semicolon() {
    setup_test_env

    input="test;command"
    result=$(sanitize_input "$input")

    assert_not_equals "$result" "$input" "Should sanitize semicolon"
    assert_not_contains "$result" ";" "Should remove semicolon"

    teardown_test_env
}

test_sanitize_input_with_pipe() {
    setup_test_env

    input="test|command"
    result=$(sanitize_input "$input")

    assert_not_contains "$result" "|" "Should remove pipe"

    teardown_test_env
}

test_sanitize_input_with_backtick() {
    setup_test_env

    input="test\`command\`"
    result=$(sanitize_input "$input")

    assert_not_contains "$result" "\`" "Should remove backticks"

    teardown_test_env
}

test_sanitize_input_with_dollar_paren() {
    setup_test_env

    input="test\$(command)"
    result=$(sanitize_input "$input")

    assert_not_contains "$result" "\$(" "Should remove command substitution"

    teardown_test_env
}

test_sanitize_input_empty() {
    setup_test_env

    input=""
    result=$(sanitize_input "$input")

    assert_equals "$result" "" "Empty input should return empty"

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_file_integrity
#==============================================================================

test_validate_file_integrity_both_missing() {
    setup_test_env

    cert="/tmp/missing_cert_$$.pem"
    key="/tmp/missing_key_$$.pem"

    if validate_file_integrity "$cert" "$key" 2>/dev/null; then
        assert_failure 1 "Should fail when both files missing"
    else
        assert_success 0 "Correctly failed for missing files"
    fi

    teardown_test_env
}

test_validate_file_integrity_cert_missing() {
    setup_test_env

    cert="/tmp/missing_cert_$$.pem"
    key="/tmp/test_key_$$.pem"
    echo "test key" > "$key"

    if validate_file_integrity "$cert" "$key" 2>/dev/null; then
        assert_failure 1 "Should fail when cert missing"
    else
        assert_success 0 "Correctly failed for missing cert"
    fi

    rm -f "$key"
    teardown_test_env
}

test_validate_file_integrity_key_missing() {
    setup_test_env

    cert="/tmp/test_cert_$$.pem"
    key="/tmp/missing_key_$$.pem"
    echo "test cert" > "$cert"

    if validate_file_integrity "$cert" "$key" 2>/dev/null; then
        assert_failure 1 "Should fail when key missing"
    else
        assert_success 0 "Correctly failed for missing key"
    fi

    rm -f "$cert"
    teardown_test_env
}

test_validate_file_integrity_empty_cert() {
    setup_test_env

    cert="/tmp/test_cert_$$.pem"
    key="/tmp/test_key_$$.pem"
    touch "$cert"  # Empty file
    echo "test key" > "$key"

    if validate_file_integrity "$cert" "$key" 2>/dev/null; then
        assert_failure 1 "Should fail for empty cert"
    else
        assert_success 0 "Correctly failed for empty cert"
    fi

    rm -f "$cert" "$key"
    teardown_test_env
}

#==============================================================================
# Test Suite: validate_files_integrity
#==============================================================================

test_validate_files_integrity_missing_files() {
    setup_test_env

    if validate_files_integrity "/tmp/missing1_$$" "/tmp/missing2_$$" 2>/dev/null; then
        assert_failure 1 "Should fail for missing files"
    else
        assert_success 0 "Correctly failed for missing files"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_menu_choice
#==============================================================================

test_validate_menu_choice_valid() {
    setup_test_env

    if validate_menu_choice "1" "3"; then
        assert_success 0 "Should accept valid choice within range"
    else
        assert_failure 1 "Valid choice rejected"
    fi

    teardown_test_env
}

test_validate_menu_choice_too_low() {
    setup_test_env

    if validate_menu_choice "0" "3" 2>/dev/null; then
        assert_failure 1 "Should reject choice below min"
    else
        assert_success 0 "Correctly rejected choice below min"
    fi

    teardown_test_env
}

test_validate_menu_choice_too_high() {
    setup_test_env

    if validate_menu_choice "4" "3" 2>/dev/null; then
        assert_failure 1 "Should reject choice above max"
    else
        assert_success 0 "Correctly rejected choice above max"
    fi

    teardown_test_env
}

test_validate_menu_choice_non_numeric() {
    setup_test_env

    if validate_menu_choice "abc" "3" 2>/dev/null; then
        assert_failure 1 "Should reject non-numeric choice"
    else
        assert_success 0 "Correctly rejected non-numeric choice"
    fi

    teardown_test_env
}

test_validate_menu_choice_empty() {
    setup_test_env

    if validate_menu_choice "" "3" 2>/dev/null; then
        assert_failure 1 "Should reject empty choice"
    else
        assert_success 0 "Correctly rejected empty choice"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_transport_security_pairing
#==============================================================================

test_validate_transport_security_pairing_ws_with_tls() {
    setup_test_env

    transport="ws"
    security="tls"

    if validate_transport_security_pairing "$transport" "$security"; then
        assert_success 0 "WS with TLS should be valid"
    else
        assert_failure 1 "Valid WS+TLS pairing rejected"
    fi

    teardown_test_env
}

test_validate_transport_security_pairing_tcp_with_reality() {
    setup_test_env

    transport="tcp"
    security="reality"

    if validate_transport_security_pairing "$transport" "$security"; then
        assert_success 0 "TCP with Reality should be valid"
    else
        assert_failure 1 "Valid TCP+Reality pairing rejected"
    fi

    teardown_test_env
}

test_validate_transport_security_pairing_invalid() {
    setup_test_env

    transport="ws"
    security="reality"

    if validate_transport_security_pairing "$transport" "$security" 2>/dev/null; then
        assert_failure 1 "WS with Reality should be invalid"
    else
        assert_success 0 "Correctly rejected invalid pairing"
    fi

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Validation Helper Functions Tests ==="
echo ""

# require_all tests
test_require_all_success
test_require_all_one_missing
test_require_all_all_missing
test_require_all_no_parameters

# require_valid tests
test_require_valid_success
test_require_valid_invalid_value
test_require_valid_empty_value

# sanitize_input tests
test_sanitize_input_clean
test_sanitize_input_with_semicolon
test_sanitize_input_with_pipe
test_sanitize_input_with_backtick
test_sanitize_input_with_dollar_paren
test_sanitize_input_empty

# validate_file_integrity tests
test_validate_file_integrity_both_missing
test_validate_file_integrity_cert_missing
test_validate_file_integrity_key_missing
test_validate_file_integrity_empty_cert

# validate_files_integrity tests
test_validate_files_integrity_missing_files

# validate_menu_choice tests
test_validate_menu_choice_valid
test_validate_menu_choice_too_low
test_validate_menu_choice_too_high
test_validate_menu_choice_non_numeric
test_validate_menu_choice_empty

# validate_transport_security_pairing tests
test_validate_transport_security_pairing_ws_with_tls
test_validate_transport_security_pairing_tcp_with_reality
test_validate_transport_security_pairing_invalid

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
