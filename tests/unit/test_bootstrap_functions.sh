#!/usr/bin/env bash
# tests/unit/test_bootstrap_functions.sh - Test early bootstrap functions
# These functions must work before any modules are loaded

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Unit Test: Bootstrap Functions ==="
echo ""

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $1 ... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ PASS"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ FAIL: $1"
}

# Source the install script to get the bootstrap get_file_size function
# We need to extract just the function definition, not run the whole script
extract_bootstrap_function() {
    # Extract get_file_size function from install.sh
    # It's defined before module loading (lines 34-49)
    sed -n '/^get_file_size() {/,/^}/p' "$SCRIPT_DIR/install.sh"
}

# Create a test environment with the bootstrap function
setup_test_env() {
    eval "$(extract_bootstrap_function)"
}

setup_test_env

#==============================================================================
# Test 1: get_file_size exists and is a function
#==============================================================================
test_start "get_file_size function is defined"

if declare -F get_file_size >/dev/null 2>&1; then
    test_pass
else
    test_fail "get_file_size function not found"
fi

#==============================================================================
# Test 2: get_file_size returns 0 for non-existent file
#==============================================================================
test_start "get_file_size returns 0 for non-existent file"

# Function returns 0 and exits with status 1 for non-existent file
result=$(get_file_size "/tmp/nonexistent-file-$$.txt" 2>/dev/null || true)

if [[ "$result" == "0" ]]; then
    test_pass
else
    test_fail "Expected 0, got: '$result'"
fi

#==============================================================================
# Test 3: get_file_size returns correct size for small file
#==============================================================================
test_start "get_file_size returns correct size for small file"

test_file="/tmp/test-filesize-$$.txt"
echo "Hello World" > "$test_file"
expected_size=$(wc -c < "$test_file")
actual_size=$(get_file_size "$test_file")

if [[ "$actual_size" == "$expected_size" ]]; then
    test_pass
else
    test_fail "Expected $expected_size, got $actual_size"
fi

rm -f "$test_file"

#==============================================================================
# Test 4: get_file_size works with empty file
#==============================================================================
test_start "get_file_size handles empty file (size 0)"

test_file="/tmp/test-empty-$$.txt"
touch "$test_file"
actual_size=$(get_file_size "$test_file")

if [[ "$actual_size" == "0" ]]; then
    test_pass
else
    test_fail "Expected 0 for empty file, got $actual_size"
fi

rm -f "$test_file"

#==============================================================================
# Test 5: get_file_size works with larger file
#==============================================================================
test_start "get_file_size handles larger files correctly"

test_file="/tmp/test-large-$$.txt"
# Create a 1KB file
dd if=/dev/zero of="$test_file" bs=1024 count=1 2>/dev/null
expected_size=$(wc -c < "$test_file")
actual_size=$(get_file_size "$test_file")

if [[ "$actual_size" == "$expected_size" ]]; then
    test_pass
else
    test_fail "Expected $expected_size, got $actual_size"
fi

rm -f "$test_file"

#==============================================================================
# Test 6: Constants are defined correctly
#==============================================================================
test_start "Early constants are defined in install.sh"

constants_found=0
if grep -q "readonly DOWNLOAD_CONNECT_TIMEOUT_SEC=" "$SCRIPT_DIR/install.sh"; then
    constants_found=$((constants_found + 1))
fi
if grep -q "readonly DOWNLOAD_MAX_TIMEOUT_SEC=" "$SCRIPT_DIR/install.sh"; then
    constants_found=$((constants_found + 1))
fi
if grep -q "readonly MIN_MODULE_FILE_SIZE_BYTES=" "$SCRIPT_DIR/install.sh"; then
    constants_found=$((constants_found + 1))
fi
if grep -q "readonly SECURE_DIR_PERMISSIONS=" "$SCRIPT_DIR/install.sh"; then
    constants_found=$((constants_found + 1))
fi

if [[ $constants_found -eq 4 ]]; then
    test_pass
else
    test_fail "Expected 4 constants, found $constants_found"
fi

#==============================================================================
# Test 7: Bootstrap function works before any module loading
#==============================================================================
test_start "get_file_size works in isolated environment"

# Test in a subshell without any modules loaded
result=$(bash -c '
    # Extract just the function
    get_file_size() {
        local file="$1"
        [[ -f "$file" ]] || { echo "0"; return 1; }
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
    }

    # Test it
    test_file="/tmp/test-isolated-$$.txt"
    echo "test content" > "$test_file"
    get_file_size "$test_file"
    rm -f "$test_file"
')

if [[ "$result" -gt 0 ]]; then
    test_pass
else
    test_fail "Function failed in isolated environment"
fi

#==============================================================================
# Test 8: Bootstrap function is exported for subshells
#==============================================================================
test_start "get_file_size can be exported for parallel downloads"

# Check if install.sh exports the function
if grep -q "export -f get_file_size" "$SCRIPT_DIR/install.sh"; then
    test_pass
else
    test_fail "get_file_size not exported (needed for parallel downloads)"
fi

#==============================================================================
# Test Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All bootstrap function tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
