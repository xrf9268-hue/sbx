#!/usr/bin/env bash
# Unit tests for checksum module functions
# Tests: verify_singbox_binary

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

source lib/checksum.sh 2> /dev/null || {
    echo "✗ Failed to load lib/checksum.sh"
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

echo "=== Checksum Binary Verification Tests ==="

#==============================================================================
# Tests for verify_singbox_binary()
#==============================================================================

test_verify_singbox_binary_function_exists() {
    type verify_singbox_binary > /dev/null 2>&1
}

test_verify_singbox_binary_defined_in_module() {
    grep -q "verify_singbox_binary()" lib/checksum.sh
}

test_verify_singbox_binary_uses_sha256() {
    # Function should use SHA256 for verification
    grep -E "(sha256|SHA256)" lib/checksum.sh | grep -q ""
}

test_verify_singbox_binary_missing_file_fails() {
    # Missing binary file should fail (requires 3 args: binary_path, version, arch)
    ! verify_singbox_binary "/nonexistent/path/sing-box" "v1.10.0" "linux-amd64"
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing verify_singbox_binary..."
run_test "Function exists" test_verify_singbox_binary_function_exists
run_test "Defined in checksum module" test_verify_singbox_binary_defined_in_module
run_test "Uses SHA256 for verification" test_verify_singbox_binary_uses_sha256
run_test "Missing file fails gracefully" test_verify_singbox_binary_missing_file_fails

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
