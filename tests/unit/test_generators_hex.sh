#!/usr/bin/env bash
# Unit tests for generators functions in lib/generators.sh
# Tests: generate_hex_string

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

source lib/generators.sh 2> /dev/null || {
    echo "✗ Failed to load lib/generators.sh"
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

echo "=== Generator Functions Unit Tests ==="

#==============================================================================
# Tests for generate_hex_string()
#==============================================================================

test_generate_hex_string_function_exists() {
    type generate_hex_string > /dev/null 2>&1
}

test_generate_hex_string_default_length() {
    # Default is 16 bytes = 32 hex chars
    local result
    result=$(generate_hex_string)
    [[ ${#result} -eq 32 ]]
}

test_generate_hex_string_custom_length_4() {
    # 4 bytes = 8 hex chars
    local result
    result=$(generate_hex_string 4)
    [[ ${#result} -eq 8 ]]
}

test_generate_hex_string_custom_length_8() {
    # 8 bytes = 16 hex chars
    local result
    result=$(generate_hex_string 8)
    [[ ${#result} -eq 16 ]]
}

test_generate_hex_string_only_hex_chars() {
    local result
    result=$(generate_hex_string 16)
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

test_generate_hex_string_unique_values() {
    # Two calls should produce different results
    local result1 result2
    result1=$(generate_hex_string)
    result2=$(generate_hex_string)
    [[ "$result1" != "$result2" ]]
}

test_generate_hex_string_small_length() {
    # 1 byte = 2 hex chars
    local result
    result=$(generate_hex_string 1)
    [[ ${#result} -eq 2 ]]
}

test_generate_hex_string_returns_zero() {
    generate_hex_string 4 > /dev/null
    return $?
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing generate_hex_string..."
run_test "Function exists" test_generate_hex_string_function_exists
run_test "Default length (16 bytes = 32 chars)" test_generate_hex_string_default_length
run_test "Custom length 4 bytes" test_generate_hex_string_custom_length_4
run_test "Custom length 8 bytes" test_generate_hex_string_custom_length_8
run_test "Only hex characters (0-9a-f)" test_generate_hex_string_only_hex_chars
run_test "Produces unique values" test_generate_hex_string_unique_values
run_test "Small length (1 byte)" test_generate_hex_string_small_length
run_test "Returns zero exit code" test_generate_hex_string_returns_zero

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
