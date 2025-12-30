#!/usr/bin/env bash
# tests/unit/test_validation_helpers.sh - High-quality tests for validation helper functions
# Tests for require(), require_all(), require_valid(), validate_file_integrity()

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

# Source validation module
source "${PROJECT_ROOT}/lib/validation.sh" 2>/dev/null || true

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
# require() Function Tests
#==============================================================================

test_require_function() {
    echo ""
    echo "Testing require() function..."

    # Test 1: require() succeeds with non-empty value
    local TEST_VAR="value"
    if require "TEST_VAR" "$TEST_VAR" "Test Variable" 2>/dev/null; then
        test_result "require accepts non-empty value" "pass"
    else
        test_result "require accepts non-empty value" "fail"
    fi

    # Test 2: require() fails with empty value
    local EMPTY_VAR=""
    if require "EMPTY_VAR" "$EMPTY_VAR" "Empty Variable" 2>/dev/null; then
        test_result "require rejects empty value" "fail"
    else
        test_result "require rejects empty value" "pass"
    fi

    # Test 3: require() fails with unset variable
    if require "UNSET_VAR" "${UNSET_VAR:-}" "Unset Variable" 2>/dev/null; then
        test_result "require rejects unset variable" "fail"
    else
        test_result "require rejects unset variable" "pass"
    fi

    # Test 4: require() accepts whitespace (intentionally)
    local SPACE_VAR=" "
    if require "SPACE_VAR" "$SPACE_VAR" "Space Variable" 2>/dev/null; then
        test_result "require accepts whitespace (by design)" "pass"
    else
        test_result "require accepts whitespace (by design)" "fail"
    fi
}

#==============================================================================
# require_all() Function Tests
#==============================================================================

test_require_all_function() {
    echo ""
    echo "Testing require_all() function..."

    # Test 1: require_all() succeeds with all values set
    local VAR1="value1"
    local VAR2="value2"
    local VAR3="value3"
    if require_all VAR1 VAR2 VAR3 2>/dev/null; then
        test_result "require_all accepts all non-empty values" "pass"
    else
        test_result "require_all accepts all non-empty values" "fail"
    fi

    # Test 2: require_all() fails with one empty value
    local VAR1="value1"
    local VAR2=""
    local VAR3="value3"
    if require_all VAR1 VAR2 VAR3 2>/dev/null; then
        test_result "require_all rejects when one is empty" "fail"
    else
        test_result "require_all rejects when one is empty" "pass"
    fi

    # Test 3: require_all() fails with all empty
    local VAR1=""
    local VAR2=""
    local VAR3=""
    if require_all VAR1 VAR2 VAR3 2>/dev/null; then
        test_result "require_all rejects when all empty" "fail"
    else
        test_result "require_all rejects when all empty" "pass"
    fi

    # Test 4: require_all() succeeds with single variable
    local SINGLE="value"
    if require_all SINGLE 2>/dev/null; then
        test_result "require_all works with single variable" "pass"
    else
        test_result "require_all works with single variable" "fail"
    fi

    # Test 5: require_all() succeeds with multiple variables
    local VAR1="a"
    local VAR2="b"
    local VAR3="c"
    local VAR4="d"
    local VAR5="e"
    if require_all VAR1 VAR2 VAR3 VAR4 VAR5 2>/dev/null; then
        test_result "require_all works with 5 variables" "pass"
    else
        test_result "require_all works with 5 variables" "fail"
    fi
}

#==============================================================================
# require_valid() Function Tests
#==============================================================================

test_require_valid_function() {
    echo ""
    echo "Testing require_valid() function..."

    # Mock validator function - always succeeds
    mock_validator_success() {
        return 0
    }

    # Mock validator function - always fails
    mock_validator_fail() {
        return 1
    }

    # Test 1: require_valid() succeeds with valid value
    VALID_VAR="value"
    if require_valid "VALID_VAR" "Valid Variable" mock_validator_success 2>/dev/null; then
        test_result "require_valid accepts value passing validation" "pass"
    else
        test_result "require_valid accepts value passing validation" "fail"
    fi

    # Test 2: require_valid() fails with invalid value
    INVALID_VAR="value"
    if require_valid "INVALID_VAR" "Invalid Variable" mock_validator_fail 2>/dev/null; then
        test_result "require_valid rejects value failing validation" "fail"
    else
        test_result "require_valid rejects value failing validation" "pass"
    fi

    # Test 3: require_valid() fails with empty value
    EMPTY_VAR=""
    if require_valid "EMPTY_VAR" "Empty Variable" mock_validator_success 2>/dev/null; then
        test_result "require_valid rejects empty value" "fail"
    else
        test_result "require_valid rejects empty value" "pass"
    fi
}

#==============================================================================
# validate_file_integrity() Function Tests
#==============================================================================

test_validate_file_integrity_function() {
    echo ""
    echo "Testing validate_file_integrity() function..."

    # Create temporary test certificate and key
    local test_cert="/tmp/test_cert_$$.pem"
    local test_key="/tmp/test_key_$$.pem"

    # Test 1: Function exists
    if grep -q "validate_file_integrity()" "${PROJECT_ROOT}/lib/validation.sh"; then
        test_result "validate_file_integrity function exists" "pass"
    else
        test_result "validate_file_integrity function exists" "fail"
    fi

    # Test 2: Fails with non-existent certificate
    if validate_file_integrity "/tmp/nonexistent_cert_$$.pem" "/tmp/nonexistent_key_$$.pem" 2>/dev/null; then
        test_result "validate_file_integrity rejects non-existent files" "fail"
    else
        test_result "validate_file_integrity rejects non-existent files" "pass"
    fi

    # Test 3: Fails with empty certificate path
    if validate_file_integrity "" "" 2>/dev/null; then
        test_result "validate_file_integrity rejects empty paths" "fail"
    else
        test_result "validate_file_integrity rejects empty paths" "pass"
    fi

    # Cleanup
    rm -f "$test_cert" "$test_key"
}

#==============================================================================
# validate_cert_files() Function Tests
#==============================================================================

test_validate_cert_files_missing() {
    echo ""
    echo "Testing validate_cert_files() with missing files..."

    if ! declare -f validate_cert_files >/dev/null 2>&1; then
        test_result "validate_cert_files available" "fail"
        return
    fi

    if validate_cert_files "/tmp/nonexistent-cert-$$.pem" "/tmp/nonexistent-key-$$.pem" 2>/dev/null; then
        test_result "validate_cert_files rejects missing files" "fail"
    else
        test_result "validate_cert_files rejects missing files" "pass"
    fi
}

#==============================================================================
# validate_singbox_config() Function Tests
#==============================================================================

test_validate_singbox_config_handles_missing_binary() {
    echo ""
    echo "Testing validate_singbox_config() with missing binary..."

    if ! declare -f validate_singbox_config >/dev/null 2>&1; then
        test_result "validate_singbox_config available" "fail"
        return
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    local config_file="${temp_dir}/config.json"

    cat > "$config_file" <<'EOF'
{"log":{"level":"warn"}}
EOF

    if validate_singbox_config "$config_file" 2>/dev/null; then
        test_result "validate_singbox_config warns on missing binary" "fail"
    else
        test_result "validate_singbox_config warns on missing binary" "pass"
    fi

    rm -rf "$temp_dir"
}

#==============================================================================
# Helper Function Existence Tests
#==============================================================================

test_helper_functions_exist() {
    echo ""
    echo "Testing helper function existence..."

    # Test 1: require exists
    if grep -q "^require()" "${PROJECT_ROOT}/lib/validation.sh"; then
        test_result "require function defined" "pass"
    else
        test_result "require function defined" "fail"
    fi

    # Test 2: require_all exists
    if grep -q "^require_all()" "${PROJECT_ROOT}/lib/validation.sh"; then
        test_result "require_all function defined" "pass"
    else
        test_result "require_all function defined" "fail"
    fi

    # Test 3: require_valid exists
    if grep -q "^require_valid()" "${PROJECT_ROOT}/lib/validation.sh"; then
        test_result "require_valid function defined" "pass"
    else
        test_result "require_valid function defined" "fail"
    fi

    # Test 4: validate_file_integrity exists
    if grep -q "^validate_file_integrity()" "${PROJECT_ROOT}/lib/validation.sh"; then
        test_result "validate_file_integrity function defined" "pass"
    else
        test_result "validate_file_integrity function defined" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Validation Helper Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_helper_functions_exist
    test_require_function
    test_require_all_function
    test_require_valid_function
    test_validate_file_integrity_function
    test_validate_cert_files_missing
    test_validate_singbox_config_handles_missing_binary

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
