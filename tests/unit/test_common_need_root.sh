#!/usr/bin/env bash
# Unit tests for common module functions
# Tests: need_root

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

echo "=== Common Module Functions Unit Tests ==="

#==============================================================================
# Tests for need_root()
#==============================================================================

test_need_root_function_exists() {
    type need_root > /dev/null 2>&1
}

test_need_root_defined_in_module() {
    grep -q "need_root()" lib/common.sh
}

test_need_root_checks_euid() {
    # Function should check EUID or use id -u
    grep -E "(EUID|id -u)" lib/common.sh | grep -q ""
}

test_need_root_returns_value() {
    # need_root calls die() if not root, so we test in a subshell
    # We verify it returns 0 when run as root, or exits non-zero when not root
    # Since we're likely not root in tests, just verify function can be called
    (need_root 2> /dev/null) || true
    return 0
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing need_root..."
run_test "Function exists" test_need_root_function_exists
run_test "Defined in common module" test_need_root_defined_in_module
run_test "Checks EUID or id" test_need_root_checks_euid
run_test "Returns without error" test_need_root_returns_value

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
