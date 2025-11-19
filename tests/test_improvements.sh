#!/usr/bin/env bash
# tests/test_improvements.sh - Test jq optional and musl detection improvements
#
# Usage: bash tests/test_improvements.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
N='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${G}✓${N} $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${R}✗${N} $1"
}

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${Y}Test $TESTS_RUN:${N} $1"
}

echo "========================================"
echo "Testing Installation Script Improvements"
echo "========================================"

# Source necessary functions from install.sh for testing
# We need to extract just the functions without running the main script

# Test 1: verify detect_libc function exists
test_start "Verify detect_libc() function exists"
if grep -q "^detect_libc()" "$SCRIPT_DIR/install.sh"; then
    pass "detect_libc() function defined"
else
    fail "detect_libc() function not found"
fi

# Test 2: Verify musl detection methods
test_start "Verify musl detection has 3 methods"
if grep -A 40 "^detect_libc()" "$SCRIPT_DIR/install.sh" | grep -q "Method 1.*musl shared library"; then
    pass "Method 1: musl shared library check present"
else
    fail "Method 1 missing"
fi

if grep -A 40 "^detect_libc()" "$SCRIPT_DIR/install.sh" | grep -q "Method 2.*ldd"; then
    pass "Method 2: ldd check present"
else
    fail "Method 2 missing"
fi

if grep -A 40 "^detect_libc()" "$SCRIPT_DIR/install.sh" | grep -q "Method 3.*os-release"; then
    pass "Method 3: os-release check present"
else
    fail "Method 3 missing"
fi

# Test 3: Verify jq is optional
test_start "Verify jq moved to optional tools"
if grep -A 20 "^ensure_tools()" "$SCRIPT_DIR/install.sh" | grep -q 'local optional=(jq)'; then
    pass "jq is in optional tools list"
else
    fail "jq not in optional tools list"
fi

if grep -A 20 "^ensure_tools()" "$SCRIPT_DIR/install.sh" | grep -q 'local required=(curl tar gzip openssl systemctl)'; then
    pass "jq not in required tools list"
else
    fail "jq still in required tools list"
fi

# Test 4: Verify libc suffix used in download
test_start "Verify libc_suffix used in download_singbox()"
if grep -A 15 "^download_singbox()" "$SCRIPT_DIR/install.sh" | grep -q 'libc_suffix="$(detect_libc)"'; then
    pass "libc_suffix variable assigned"
else
    fail "libc_suffix not assigned"
fi

if grep -A 80 "^download_singbox()" "$SCRIPT_DIR/install.sh" | grep -q 'linux-\${arch}\${libc_suffix}'; then
    pass "libc_suffix used in download URL pattern"
else
    fail "libc_suffix not used in URL pattern"
fi

# Test 5: Verify fallback to generic binary
test_start "Verify fallback to generic Linux binary"
if grep -A 80 "^download_singbox()" "$SCRIPT_DIR/install.sh" | grep -q "musl-specific binary not found"; then
    pass "Warning message for missing musl binary"
else
    fail "No warning for missing musl binary"
fi

if grep -A 80 "^download_singbox()" "$SCRIPT_DIR/install.sh" | grep -q "Fallback to generic linux binary"; then
    pass "Fallback logic present"
else
    fail "Fallback logic missing"
fi

# Test 6: Verify checksum uses libc suffix
test_start "Verify checksum verification uses libc suffix"
if grep -A 20 "SHA256 Checksum Verification" "$SCRIPT_DIR/install.sh" | grep -q 'platform="linux-${arch}${libc_suffix}"'; then
    pass "Checksum uses libc suffix"
else
    fail "Checksum doesn't use libc suffix"
fi

# Test 7: Verify optional tools notification
test_start "Verify user-friendly messages for optional tools"
if grep -A 40 "^ensure_tools()" "$SCRIPT_DIR/install.sh" | grep -q "Optional tools not available"; then
    pass "Info message for optional tools"
else
    fail "No info message for optional tools"
fi

if grep -A 40 "^ensure_tools()" "$SCRIPT_DIR/install.sh" | grep -q "fallback methods"; then
    pass "Mentions fallback methods"
else
    fail "No mention of fallback methods"
fi

# Test 8: Verify lib/tools.sh has JSON fallbacks
test_start "Verify lib/tools.sh has robust JSON fallbacks"
if grep -q "# Primary: Use jq if available" "$SCRIPT_DIR/lib/tools.sh"; then
    pass "jq is primary parser"
else
    fail "jq not marked as primary"
fi

if grep -q "# Fallback 1: Python 3" "$SCRIPT_DIR/lib/tools.sh"; then
    pass "Python 3 fallback exists"
else
    fail "Python 3 fallback missing"
fi

if grep -q "# Fallback 2: Python 2" "$SCRIPT_DIR/lib/tools.sh"; then
    pass "Python 2 fallback exists"
else
    fail "Python 2 fallback missing"
fi

# Test 9: Syntax validation
test_start "Validate bash syntax of install.sh"
if bash -n "$SCRIPT_DIR/install.sh" 2>/dev/null; then
    pass "Syntax is valid"
else
    fail "Syntax errors found"
fi

# Test 10: Check for early get_file_size bootstrap function
test_start "Verify early get_file_size() for bootstrapping"
if grep -B 5 "^get_file_size()" "$SCRIPT_DIR/install.sh" | grep -q "Early Helper Functions"; then
    pass "Early get_file_size() exists for bootstrapping"
else
    fail "Early get_file_size() not found"
fi

if grep -A 20 "_download_modules_parallel()" "$SCRIPT_DIR/install.sh" | grep -q "export -f get_file_size"; then
    pass "get_file_size exported for parallel downloads"
else
    fail "get_file_size not exported"
fi

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests run:    $TESTS_RUN"
echo -e "${G}Tests passed: $TESTS_PASSED${N}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${R}Tests failed: $TESTS_FAILED${N}"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
