#!/usr/bin/env bash
# Unit tests for validation error formatting functions in lib/messages.sh
# Tests: format_validation_error, format_validation_error_with_example,
#        format_validation_error_with_command

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

source lib/messages.sh 2> /dev/null || {
    echo "✗ Failed to load lib/messages.sh"
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

echo "=== Validation Error Formatting Unit Tests ==="

#==============================================================================
# Tests for format_validation_error()
#==============================================================================

test_format_validation_error_basic() {
    # Should output error message with field and value
    local output
    output=$(format_validation_error "Short ID" "invalid123" "Must be hex" 2>&1)
    [[ "$output" == *"Invalid Short ID"* ]]
}

test_format_validation_error_contains_value() {
    local output
    output=$(format_validation_error "Port" "99999" "Range 1-65535" 2>&1)
    [[ "$output" == *"99999"* ]]
}

test_format_validation_error_contains_requirements() {
    local output
    output=$(format_validation_error "UUID" "bad" "Must be valid UUID" "Format: 8-4-4-4-12" 2>&1)
    [[ "$output" == *"Requirements"* ]]
}

test_format_validation_error_multiple_requirements() {
    local output
    output=$(format_validation_error "Key" "x" "Req 1" "Req 2" "Req 3" 2>&1)
    [[ "$output" == *"Req 1"* ]] && [[ "$output" == *"Req 2"* ]] && [[ "$output" == *"Req 3"* ]]
}

test_format_validation_error_returns_zero() {
    format_validation_error "Test" "value" "requirement" > /dev/null 2>&1
    return $?
}

#==============================================================================
# Tests for format_validation_error_with_example()
#==============================================================================

test_format_validation_error_with_example_basic() {
    local output
    output=$(format_validation_error_with_example "UUID" "bad" "a1b2c3d4-..." "Valid UUID" 2>&1)
    [[ "$output" == *"Example"* ]]
}

test_format_validation_error_with_example_contains_example() {
    local output
    output=$(format_validation_error_with_example "Short ID" "gg" "a1b2c3d4" "8 hex chars" 2>&1)
    [[ "$output" == *"a1b2c3d4"* ]]
}

test_format_validation_error_with_example_contains_requirements() {
    local output
    output=$(format_validation_error_with_example "Port" "abc" "443" "Numeric" "1-65535" 2>&1)
    [[ "$output" == *"Requirements"* ]] && [[ "$output" == *"Numeric"* ]]
}

test_format_validation_error_with_example_returns_zero() {
    format_validation_error_with_example "Test" "val" "example" "req" > /dev/null 2>&1
    return $?
}

#==============================================================================
# Tests for format_validation_error_with_command()
#==============================================================================

test_format_validation_error_with_command_basic() {
    local output
    output=$(format_validation_error_with_command "Short ID" "bad" "openssl rand -hex 4" "8 hex" 2>&1)
    [[ "$output" == *"Generate"* ]]
}

test_format_validation_error_with_command_contains_command() {
    local output
    output=$(format_validation_error_with_command "Key" "x" "sing-box generate reality-keypair" "43 chars" 2>&1)
    [[ "$output" == *"sing-box generate"* ]]
}

test_format_validation_error_with_command_contains_field() {
    local output
    output=$(format_validation_error_with_command "Private Key" "short" "cmd" "req" 2>&1)
    [[ "$output" == *"Private Key"* ]]
}

test_format_validation_error_with_command_multiple_requirements() {
    local output
    output=$(format_validation_error_with_command "UUID" "x" "uuidgen" "RFC 4122" "Lowercase" 2>&1)
    [[ "$output" == *"RFC 4122"* ]] && [[ "$output" == *"Lowercase"* ]]
}

test_format_validation_error_with_command_returns_zero() {
    format_validation_error_with_command "Test" "val" "cmd" "req" > /dev/null 2>&1
    return $?
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing format_validation_error..."
run_test "Basic error formatting" test_format_validation_error_basic
run_test "Contains invalid value" test_format_validation_error_contains_value
run_test "Contains requirements header" test_format_validation_error_contains_requirements
run_test "Multiple requirements listed" test_format_validation_error_multiple_requirements
run_test "Returns zero exit code" test_format_validation_error_returns_zero

echo ""
echo "Testing format_validation_error_with_example..."
run_test "Contains Example label" test_format_validation_error_with_example_basic
run_test "Contains example value" test_format_validation_error_with_example_contains_example
run_test "Contains requirements" test_format_validation_error_with_example_contains_requirements
run_test "Returns zero exit code" test_format_validation_error_with_example_returns_zero

echo ""
echo "Testing format_validation_error_with_command..."
run_test "Contains Generate label" test_format_validation_error_with_command_basic
run_test "Contains generation command" test_format_validation_error_with_command_contains_command
run_test "Contains field name" test_format_validation_error_with_command_contains_field
run_test "Multiple requirements" test_format_validation_error_with_command_multiple_requirements
run_test "Returns zero exit code" test_format_validation_error_with_command_returns_zero

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
