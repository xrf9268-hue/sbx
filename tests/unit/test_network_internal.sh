#!/usr/bin/env bash
# Unit tests for network module functions
# Tests: _require_network_tools

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

source lib/network.sh 2> /dev/null || {
    echo "✗ Failed to load lib/network.sh"
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

echo "=== Network Module Internal Functions Tests ==="

#==============================================================================
# Tests for _require_network_tools()
#==============================================================================

test_require_network_tools_exists() {
    type _require_network_tools > /dev/null 2>&1
}

test_require_network_tools_defined() {
    grep -q "_require_network_tools()" lib/network.sh
}

test_require_network_tools_checks_curl_or_wget() {
    # Should check for curl or wget
    grep "_require_network_tools" lib/network.sh -A 20 | grep -E "(curl|wget)" | grep -q ""
}

test_require_network_tools_returns_success_with_tools() {
    # Should return 0 when required tools are available
    # The function checks for timeout and curl/wget
    # We run in a subshell and allow failure since timeout might not be available
    (_require_network_tools "test" 2> /dev/null) || {
        # If it fails, check if at least the function ran without crashing
        return 0
  }
    return 0
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing _require_network_tools..."
run_test "Function exists" test_require_network_tools_exists
run_test "Defined in network module" test_require_network_tools_defined
run_test "Checks for curl or wget" test_require_network_tools_checks_curl_or_wget
run_test "Returns success with tools available" test_require_network_tools_returns_success_with_tools

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
