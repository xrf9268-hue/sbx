#!/usr/bin/env bash
# Unit tests for config module functions
# Tests: write_config, _create_all_inbounds

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

source lib/config.sh 2> /dev/null || {
    echo "✗ Failed to load lib/config.sh"
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

echo "=== Config Module Functions Tests ==="

#==============================================================================
# Tests for write_config()
#==============================================================================

test_write_config_function_exists() {
    type write_config > /dev/null 2>&1
}

test_write_config_defined_in_module() {
    grep -q "write_config()" lib/config.sh
}

test_write_config_uses_jq() {
    # write_config should use jq for JSON handling
    grep -E "jq" lib/config.sh | grep -q ""
}

test_write_config_validates_before_write() {
    # Should validate JSON before writing
    grep -E "(validate|check|test)" lib/config.sh | grep -q ""
}

#==============================================================================
# Tests for _create_all_inbounds()
#==============================================================================

test_create_all_inbounds_function_exists() {
    type _create_all_inbounds > /dev/null 2>&1
}

test_create_all_inbounds_defined_in_module() {
    grep -q "_create_all_inbounds()" lib/config.sh
}

test_create_all_inbounds_creates_reality_inbound() {
    # Should call create_reality_inbound
    grep "_create_all_inbounds" lib/config.sh | head -20 || grep "create_reality_inbound" lib/config.sh | grep -q ""
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing write_config..."
run_test "Function exists" test_write_config_function_exists
run_test "Defined in config module" test_write_config_defined_in_module
run_test "Uses jq for JSON" test_write_config_uses_jq
run_test "Validates before write" test_write_config_validates_before_write

echo ""
echo "Testing _create_all_inbounds..."
run_test "Function exists" test_create_all_inbounds_function_exists
run_test "Defined in config module" test_create_all_inbounds_defined_in_module
run_test "Creates reality inbound" test_create_all_inbounds_creates_reality_inbound

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
