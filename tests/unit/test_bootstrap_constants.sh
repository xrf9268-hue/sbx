#!/usr/bin/env bash
# tests/unit/test_bootstrap_constants.sh - Validate bootstrap constant definitions
#
# PURPOSE: Prevent recurring "unbound variable" errors during bootstrap
#
# CONTEXT: This codebase has repeatedly suffered from constants being defined in
# lib/common.sh but used during bootstrap before modules are loaded. This has
# caused 6+ production bugs:
# - url variable (install.sh:836)
# - HTTP_DOWNLOAD_TIMEOUT_SEC
# - get_file_size()
# - REALITY_SHORT_ID_MIN_LENGTH (this fix)
# - REALITY_FLOW_VISION (this fix)
# - IPV6_TEST_TIMEOUT_SEC (this fix)
# - IPV6_PING_WAIT_SEC (this fix)
#
# SOLUTION: This test validates:
# 1. All bootstrap constants are defined in install.sh early section
# 2. lib/common.sh has conditional declarations for bootstrap constants
# 3. Script can execute with bash -u without unbound variable errors
#
# MAINTENANCE: When adding new constants to lib/common.sh that are used during
# bootstrap, add them to REQUIRED_BOOTSTRAP_CONSTANTS array below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Bootstrap Constants Validation Test ==="
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

#==============================================================================
# Bootstrap Constants Registry
#==============================================================================
# CRITICAL: Keep this list synchronized with install.sh early constants
# If you add a constant here, ensure it's in install.sh lines 16-44

# Download configuration constants
DOWNLOAD_CONSTANTS=(
  "DOWNLOAD_CONNECT_TIMEOUT_SEC"
  "DOWNLOAD_MAX_TIMEOUT_SEC"
  "HTTP_DOWNLOAD_TIMEOUT_SEC"
  "MIN_MODULE_FILE_SIZE_BYTES"
  "MIN_MANAGER_FILE_SIZE_BYTES"
)

# Network configuration constants
NETWORK_CONSTANTS=(
  "NETWORK_TIMEOUT_SEC"
  "IPV6_TEST_TIMEOUT_SEC"
  "IPV6_PING_WAIT_SEC"
)

# Reality validation constants (used by lib/validation.sh during bootstrap)
REALITY_VALIDATION_CONSTANTS=(
  "REALITY_SHORT_ID_MIN_LENGTH"
  "REALITY_SHORT_ID_MAX_LENGTH"
)

# Port default constants (used by lib/validation.sh during bootstrap)
PORT_DEFAULT_CONSTANTS=(
  "REALITY_PORT_DEFAULT"
  "WS_PORT_DEFAULT"
  "HY2_PORT_DEFAULT"
)

# Caddy port default constants (used by lib/caddy.sh during bootstrap)
CADDY_PORT_CONSTANTS=(
  "CADDY_HTTP_PORT_DEFAULT"
  "CADDY_HTTPS_PORT_DEFAULT"
  "CADDY_FALLBACK_PORT_DEFAULT"
)

# Reality configuration constants (used by lib/config.sh during bootstrap)
REALITY_CONFIG_CONSTANTS=(
  "REALITY_FLOW_VISION"
  "REALITY_DEFAULT_HANDSHAKE_PORT"
  "REALITY_MAX_TIME_DIFF"
  "REALITY_ALPN_H2"
  "REALITY_ALPN_HTTP11"
)

# File permission constants
PERMISSION_CONSTANTS=(
  "SECURE_DIR_PERMISSIONS"
  "SECURE_FILE_PERMISSIONS"
)

# Cloudflare API Token constants (used by lib/validation.sh during bootstrap)
CF_TOKEN_CONSTANTS=(
  "CF_API_TOKEN_MIN_LENGTH"
  "CF_API_TOKEN_MAX_LENGTH"
)

# Combine all into master list
REQUIRED_BOOTSTRAP_CONSTANTS=(
  "${DOWNLOAD_CONSTANTS[@]}"
  "${NETWORK_CONSTANTS[@]}"
  "${REALITY_VALIDATION_CONSTANTS[@]}"
  "${PORT_DEFAULT_CONSTANTS[@]}"
  "${CADDY_PORT_CONSTANTS[@]}"
  "${REALITY_CONFIG_CONSTANTS[@]}"
  "${PERMISSION_CONSTANTS[@]}"
  "${CF_TOKEN_CONSTANTS[@]}"
)

#==============================================================================
# Test 1: All bootstrap constants defined in install.sh
#==============================================================================
test_start "All bootstrap constants defined in install.sh"

missing_constants=()
for const in "${REQUIRED_BOOTSTRAP_CONSTANTS[@]}"; do
  if ! grep -q "^readonly ${const}=" "$SCRIPT_DIR/install.sh"; then
    missing_constants+=("$const")
  fi
done

if [[ ${#missing_constants[@]} -eq 0 ]]; then
  test_pass
else
  test_fail "Missing constants: ${missing_constants[*]}"
  echo "       Add to install.sh early constants section (lines 16-44)"
fi

#==============================================================================
# Test 2: Bootstrap constants in early section (before line 100)
#==============================================================================
test_start "Bootstrap constants defined before module loading"

late_constants=()
for const in "${REQUIRED_BOOTSTRAP_CONSTANTS[@]}"; do
  line_num=$(grep -n "^readonly ${const}=" "$SCRIPT_DIR/install.sh" | cut -d: -f1 || echo "999999")
  if [[ $line_num -gt 100 ]]; then
    late_constants+=("${const}:line${line_num}")
  fi
done

if [[ ${#late_constants[@]} -eq 0 ]]; then
  test_pass
else
  test_fail "Constants defined too late: ${late_constants[*]}"
  echo "       Move to early constants section (lines 16-44)"
fi

#==============================================================================
# Test 3: Reality constants have conditional declarations in lib/common.sh
#==============================================================================
test_start "Reality, port, and Caddy constants conditionally declared in lib/common.sh"

# These constants should have conditional declarations since they're in bootstrap
CONDITIONALLY_DECLARED=(
  "${REALITY_VALIDATION_CONSTANTS[@]}"
  "${PORT_DEFAULT_CONSTANTS[@]}"
  "${CADDY_PORT_CONSTANTS[@]}"
  "${REALITY_CONFIG_CONSTANTS[@]}"
)

missing_conditional=()
for const in "${CONDITIONALLY_DECLARED[@]}"; do
  # Check for pattern: if [[ -z "${CONST:-}" ]]; then
  if ! grep -q "if \[\[ -z \"\${${const}:-}\" \]\]; then" "$SCRIPT_DIR/lib/common.sh"; then
    missing_conditional+=("$const")
  fi
done

if [[ ${#missing_conditional[@]} -eq 0 ]]; then
  test_pass
else
  test_fail "Missing conditional declarations: ${missing_conditional[*]}"
  echo "       Add to lib/common.sh with pattern:"
  echo "       if [[ -z \"\${CONST_NAME:-}\" ]]; then"
  echo "         declare -r CONST_NAME=value"
  echo "       fi"
fi

#==============================================================================
# Test 4: No duplicate constant declarations
#==============================================================================
test_start "No duplicate constant declarations between files"

duplicate_found=0
for const in "${REQUIRED_BOOTSTRAP_CONSTANTS[@]}"; do
  # Count unconditional declarations in lib/common.sh
  # Pattern: declare -r CONST= (not inside if statement)
  # Note: grep -c exits 1 when no match, so use || true to avoid exit, then check count
  unconditional_count=$(grep -c "^declare -r ${const}=" "$SCRIPT_DIR/lib/common.sh" 2> /dev/null) || unconditional_count=0

  if [[ $unconditional_count -gt 0 ]]; then
    echo ""
    echo "       WARNING: ${const} has unconditional declaration in lib/common.sh"
    echo "       This will conflict with bootstrap definition in install.sh"
    duplicate_found=1
  fi
done

if [[ $duplicate_found -eq 0 ]]; then
  test_pass
else
  test_fail "Found unconditional declarations (see warnings above)"
fi

#==============================================================================
# Test 5: Validate script can source with strict mode
#==============================================================================
test_start "install.sh sources successfully with strict mode"

# Test that we can source just the early constants section
test_output=$(bash -euo pipefail -c "
    # Source just the early constants section (lines 1-100)
    eval \"\$(sed -n '1,100p' '$SCRIPT_DIR/install.sh' | grep '^readonly')\"

    # Try to access each constant
    for const in ${REQUIRED_BOOTSTRAP_CONSTANTS[*]}; do
        eval \"echo \\\$const=\\\${\$const}\" >/dev/null
    done

    echo 'SUCCESS'
" 2>&1)

if echo "$test_output" | grep -q "SUCCESS"; then
  test_pass
else
  test_fail "Constants not accessible"
  echo "       Error: $test_output"
fi

#==============================================================================
# Test 6: lib/common.sh can be sourced after bootstrap constants
#==============================================================================
test_start "lib/common.sh sources successfully after bootstrap constants"

test_output=$(bash -euo pipefail -c "
    # Define bootstrap constants first (simulating install.sh)
    readonly REALITY_SHORT_ID_MIN_LENGTH=1
    readonly REALITY_SHORT_ID_MAX_LENGTH=8
    readonly REALITY_FLOW_VISION='xtls-rprx-vision'
    readonly REALITY_DEFAULT_HANDSHAKE_PORT=443
    readonly REALITY_MAX_TIME_DIFF='1m'
    readonly REALITY_ALPN_H2='h2'
    readonly REALITY_ALPN_HTTP11='http/1.1'

    # Now source lib/common.sh - should not conflict
    source '$SCRIPT_DIR/lib/common.sh' 2>&1 || echo 'FAILED_TO_SOURCE'

    # Verify constants still accessible
    echo \$REALITY_SHORT_ID_MIN_LENGTH >/dev/null
    echo 'SUCCESS'
" 2>&1)

if echo "$test_output" | grep -q "SUCCESS" && ! echo "$test_output" | grep -q "FAILED_TO_SOURCE"; then
  test_pass
else
  test_fail "lib/common.sh conflicts with bootstrap constants"
  echo "       Error: $test_output"
fi

#==============================================================================
# Test 7: Detect unbound variable usage in early bootstrap functions
#==============================================================================
test_start "Bootstrap functions don't use unbound variables"

# Extract and test the early bootstrap functions
unbound_errors=$(bash -uo pipefail -c "
    # Extract get_file_size function
    $(sed -n '/^get_file_size() {/,/^}/p' "$SCRIPT_DIR/install.sh")

    # Test it with a sample file
    test_file='/tmp/test-bootstrap-\$\$.txt'
    echo 'test' > \"\$test_file\"
    get_file_size \"\$test_file\" >/dev/null
    rm -f \"\$test_file\"

    echo 'SUCCESS'
" 2>&1)

if echo "$unbound_errors" | grep -q "SUCCESS"; then
  test_pass
else
  test_fail "Bootstrap functions use unbound variables"
  echo "       Error: $unbound_errors"
fi

#==============================================================================
# Test 8: Early constants section has proper documentation
#==============================================================================
test_start "Early constants section has documentation header"

if grep -q "# Early Constants (used before module loading)" "$SCRIPT_DIR/install.sh"; then
  test_pass
else
  test_fail "Missing documentation header for early constants section"
  echo "       Add comment: # Early Constants (used before module loading)"
fi

#==============================================================================
# Test 9: CLAUDE.md documents bootstrap pattern
#==============================================================================
test_start "CLAUDE.md documents bootstrap constant pattern"

claude_md_checks=0

if grep -q "Bootstrap" "$SCRIPT_DIR/CLAUDE.md"; then
  claude_md_checks=$((claude_md_checks + 1))
fi

if grep -q "unbound variable" "$SCRIPT_DIR/CLAUDE.md"; then
  claude_md_checks=$((claude_md_checks + 1))
fi

if [[ $claude_md_checks -eq 2 ]]; then
  test_pass
else
  test_fail "CLAUDE.md missing bootstrap documentation"
  echo "       Document the bootstrap constant pattern"
fi

#==============================================================================
# Test 10: Comprehensive strict mode check (integration test)
#==============================================================================
test_start "install.sh help works with bash -u (no unbound vars)"

# Run install script with --help flag in strict mode
# This should catch any unbound variable usage during early initialization
help_output=$(timeout 5 bash -uo pipefail "$SCRIPT_DIR/install.sh" --help 2>&1 || true)

if echo "$help_output" | grep -q "unbound variable"; then
  unbound_var=$(echo "$help_output" | grep "unbound variable" | head -1)
  test_fail "Found unbound variable: $unbound_var"
else
  test_pass
fi

#==============================================================================
# Test Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Total constants tracked: ${#REQUIRED_BOOTSTRAP_CONSTANTS[@]}"
echo "  - Download: ${#DOWNLOAD_CONSTANTS[@]}"
echo "  - Network: ${#NETWORK_CONSTANTS[@]}"
echo "  - Reality validation: ${#REALITY_VALIDATION_CONSTANTS[@]}"
echo "  - Port defaults: ${#PORT_DEFAULT_CONSTANTS[@]}"
echo "  - Caddy ports: ${#CADDY_PORT_CONSTANTS[@]}"
echo "  - Reality config: ${#REALITY_CONFIG_CONSTANTS[@]}"
echo "  - Permissions: ${#PERMISSION_CONSTANTS[@]}"
echo "  - CF Token: ${#CF_TOKEN_CONSTANTS[@]}"
echo ""
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo "✓ All bootstrap constant validation tests passed!"
  echo ""
  echo "This test suite prevents recurring 'unbound variable' errors by ensuring:"
  echo "  1. All bootstrap constants defined in install.sh early section"
  echo "  2. lib/common.sh uses conditional declarations to avoid conflicts"
  echo "  3. Script executes with bash -u without errors"
  echo ""
  exit 0
else
  echo "✗ Some tests failed - bootstrap constants not properly configured"
  echo ""
  echo "REMEDIATION STEPS:"
  echo "  1. Review failed tests above"
  echo "  2. Add missing constants to install.sh (lines 16-44)"
  echo "  3. Update lib/common.sh to use conditional declarations"
  echo "  4. Re-run this test: bash tests/unit/test_bootstrap_constants.sh"
  echo ""
  exit 1
fi
