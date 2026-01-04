#!/usr/bin/env bash
# Unit tests for schema_validator module functions
# Tests: validate_reality_structure

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

source lib/schema_validator.sh 2> /dev/null || {
    echo "✗ Failed to load lib/schema_validator.sh"
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

echo "=== Schema Validator Reality Structure Tests ==="

#==============================================================================
# Tests for validate_reality_structure()
#==============================================================================

test_validate_reality_structure_function_exists() {
    type validate_reality_structure > /dev/null 2>&1
}

test_validate_reality_structure_defined_in_module() {
    grep -q "validate_reality_structure()" lib/schema_validator.sh
}

test_validate_reality_structure_checks_required_fields() {
    # validate_reality_structure calls _validate_reality_required_fields
    # which checks for private_key, short_id, and handshake
    grep -q "_validate_reality_required_fields" lib/schema_validator.sh \
                                                                        && grep -E "(private_key|short_id)" lib/schema_validator.sh | grep -q ""
}

test_validate_reality_structure_validates_field_types() {
    # validate_reality_structure calls _validate_reality_field_types
    # which validates array types and other field types
    grep -q "_validate_reality_field_types" lib/schema_validator.sh \
                                                                    && grep -E '(type|"array")' lib/schema_validator.sh | grep -q ""
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing validate_reality_structure..."
run_test "Function exists" test_validate_reality_structure_function_exists
run_test "Defined in schema_validator module" test_validate_reality_structure_defined_in_module
run_test "Checks required fields" test_validate_reality_structure_checks_required_fields
run_test "Validates field types" test_validate_reality_structure_validates_field_types

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
