#!/usr/bin/env bash
# Unit tests for export functions in lib/export.sh
# Tests: export_v2rayn_json

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

source lib/export.sh 2> /dev/null || {
    echo "✗ Failed to load lib/export.sh"
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

echo "=== Export Functions Unit Tests ==="

#==============================================================================
# Tests for export_v2rayn_json()
#==============================================================================

test_export_v2rayn_json_function_exists() {
    type export_v2rayn_json > /dev/null 2>&1
}

test_export_v2rayn_json_defined_in_module() {
    # Verify the function is exported
    grep -q "export_v2rayn_json" lib/export.sh
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing export_v2rayn_json..."
run_test "Function exists" test_export_v2rayn_json_function_exists
run_test "Defined in export module" test_export_v2rayn_json_defined_in_module

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
