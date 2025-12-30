#!/usr/bin/env bash
# tests/test_reality.sh - Reality configuration test suite
# Part of sbx-lite Phase 2: Testing Infrastructure

set -euo pipefail

# Prevent cleanup() from interfering with test execution
export SBX_TEST_MODE=1

# Test framework configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source library modules at top level (before any functions are called)
# shellcheck source=/dev/null
source "$LIB_DIR/common.sh"

# shellcheck source=/dev/null
source "$LIB_DIR/validation.sh"

# shellcheck source=/dev/null
source "$LIB_DIR/generators.sh"

# shellcheck source=/dev/null
source "$LIB_DIR/config.sh"

# shellcheck source=/dev/null
source "$LIB_DIR/export.sh"

# Disable all traps from sourced libraries to prevent interference with tests
# This MUST be done at top level, not inside a function, to work correctly
# Libraries like common.sh set EXIT traps that can cause test failures
trap - EXIT INT TERM HUP QUIT ERR RETURN

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Color variables are provided by lib/common.sh
# Using library's color scheme: R (red), G (green), Y (yellow), BLUE, N (reset)

#==============================================================================
# Test Framework Functions
#==============================================================================

# Mark test as passed
pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${G}✓${N} ${FUNCNAME[1]}"
}

# Mark test as failed
fail() {
  local message="${1:-No error message provided}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${R}✗${N} ${FUNCNAME[1]}: $message"
  return 1
}

# Skip a test
skip() {
  local reason="${1:-No reason provided}"
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${Y}⊘${N} ${FUNCNAME[1]}: SKIPPED - $reason"
  return 0
}

# Assert condition is true
assert_true() {
  local condition="$1"
  local message="${2:-Assertion failed}"
  if ! eval "$condition"; then
    fail "$message"
    return 1
  fi
  return 0
}

# Assert two values are equal
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Expected '$expected', got '$actual'}"
  if [[ "$expected" != "$actual" ]]; then
    fail "$message"
    return 1
  fi
  return 0
}

# Assert command succeeds
assert_success() {
  if ! "$@" >/dev/null 2>&1; then
    fail "Command failed: $*"
    return 1
  fi
  return 0
}

# Assert command fails
assert_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "Command should have failed: $*"
    return 1
  fi
  return 0
}

#==============================================================================
# Test Setup and Teardown
#==============================================================================

# Global setup - runs once before all tests
setup_suite() {
  echo -e "${BLUE}Setting up test suite...${N}"

  # Create temporary directory for test artifacts
  TEST_TMP_DIR=$(mktemp -d)
  export TEST_TMP_DIR

  echo -e "${BLUE}Test artifacts directory: $TEST_TMP_DIR${N}"
}

# Global teardown - runs once after all tests
teardown_suite() {
  echo -e "${BLUE}Cleaning up test suite...${N}"

  # Remove temporary directory
  if [[ -n "${TEST_TMP_DIR:-}" && -d "$TEST_TMP_DIR" ]]; then
    rm -rf "$TEST_TMP_DIR"
  fi
}

# Setup before each test
setup_test() {
  # Create unique temp dir for this test
  TEST_TEMP=$(mktemp -d "$TEST_TMP_DIR/test.XXXXXX")
}

# Cleanup after each test
teardown_test() {
  # Clean up test-specific temp dir
  if [[ -n "${TEST_TEMP:-}" && -d "$TEST_TEMP" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

#==============================================================================
# Category 1: Short ID Validation Tests
#==============================================================================

test_short_id_valid_8_chars() {
  setup_test

  # Valid 8-character hex short ID
  local sid="a1b2c3d4"
  assert_success validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_valid_4_chars() {
  setup_test

  # Valid 4-character hex short ID
  local sid="abcd"
  assert_success validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_valid_1_char() {
  setup_test

  # Valid 1-character hex short ID
  local sid="a"
  assert_success validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_invalid_empty() {
  setup_test

  # Empty short ID should fail
  local sid=""
  assert_failure validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_invalid_9_chars() {
  setup_test

  # 9 characters exceeds sing-box limit
  local sid="abcd12345"
  assert_failure validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_invalid_16_chars_xray() {
  setup_test

  # 16-character Xray-style short ID (invalid for sing-box)
  local sid="abcd1234abcd1234"
  assert_failure validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_invalid_non_hex() {
  setup_test

  # Non-hexadecimal characters
  local sid="gggg1234"
  assert_failure validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_invalid_special_chars() {
  setup_test

  # Special characters not allowed
  local sid="ab-cd-12"
  assert_failure validate_short_id "$sid" && pass || return 1

  teardown_test
}

test_short_id_case_insensitive() {
  setup_test

  # Both uppercase and lowercase hex should work
  assert_success validate_short_id "ABCD1234" || return 1
  assert_success validate_short_id "abcd1234" || return 1
  assert_success validate_short_id "AbCd1234" || return 1
  pass

  teardown_test
}

#==============================================================================
# Category 2: Reality Keypair Validation Tests
#==============================================================================

test_reality_keypair_valid() {
  setup_test

  # Valid base64-like keypair
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local pub="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

  assert_success validate_reality_keypair "$priv" "$pub" && pass || return 1

  teardown_test
}

test_reality_keypair_empty_private() {
  setup_test

  # Empty private key should fail
  local priv=""
  local pub="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

  assert_failure validate_reality_keypair "$priv" "$pub" && pass || return 1

  teardown_test
}

test_reality_keypair_empty_public() {
  setup_test

  # Empty public key should fail
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local pub=""

  assert_failure validate_reality_keypair "$priv" "$pub" && pass || return 1

  teardown_test
}

test_reality_keypair_invalid_format() {
  setup_test

  # Invalid characters in keys
  local priv="invalid@key!"
  local pub="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

  assert_failure validate_reality_keypair "$priv" "$pub" && pass || return 1

  teardown_test
}

#==============================================================================
# Category 3: Reality SNI Validation Tests
#==============================================================================

test_reality_sni_valid_domain() {
  setup_test

  # Valid domain names
  assert_success validate_reality_sni "www.microsoft.com" || return 1
  assert_success validate_reality_sni "google.com" || return 1
  assert_success validate_reality_sni "example.org" || return 1
  pass

  teardown_test
}

test_reality_sni_invalid_empty() {
  setup_test

  # Empty SNI should fail
  assert_failure validate_reality_sni "" && pass || return 1

  teardown_test
}

test_reality_sni_invalid_format() {
  setup_test

  # Invalid domain formats
  assert_failure validate_reality_sni "not a domain!" || return 1
  assert_failure validate_reality_sni "http://example.com" || return 1
  pass

  teardown_test
}

#==============================================================================
# Category 4: Configuration Generation Tests
#==============================================================================

test_reality_config_structure() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  # Generate Reality configuration
  local uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  local port="443"
  local listen="::"
  local sni="www.microsoft.com"
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local sid="a1b2c3d4"

  local config
  config=$(create_reality_inbound "$uuid" "$port" "$listen" "$sni" "$priv" "$sid" 2>/dev/null) || {
    fail "Failed to generate configuration"
    teardown_test
    return 1
  }

  # Verify JSON structure
  echo "$config" | jq -e '.type == "vless"' >/dev/null || {
    fail "Wrong protocol type"
    teardown_test
    return 1
  }

  echo "$config" | jq -e '.users[0].flow == "xtls-rprx-vision"' >/dev/null || {
    fail "Wrong flow value"
    teardown_test
    return 1
  }

  echo "$config" | jq -e '.tls.reality.enabled == true' >/dev/null || {
    fail "Reality not enabled"
    teardown_test
    return 1
  }

  pass
  teardown_test
}

test_short_id_array_format() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  local uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  local port="443"
  local listen="::"
  local sni="www.microsoft.com"
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local sid="a1b2c3d4"

  local config
  config=$(create_reality_inbound "$uuid" "$port" "$listen" "$sni" "$priv" "$sid" 2>/dev/null) || {
    fail "Failed to generate configuration"
    teardown_test
    return 1
  }

  # Verify short_id is array, not string
  local sid_type
  sid_type=$(echo "$config" | jq -r '.tls.reality.short_id | type')

  if [[ "$sid_type" != "array" ]]; then
    fail "Short ID must be array, got: $sid_type"
    teardown_test
    return 1
  fi

  # Verify array has one element
  local sid_count
  sid_count=$(echo "$config" | jq -r '.tls.reality.short_id | length')

  if [[ "$sid_count" -ne 1 ]]; then
    fail "Short ID array must have 1 element, got: $sid_count"
    teardown_test
    return 1
  fi

  pass
  teardown_test
}

test_tls_reality_nesting() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  local uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  local port="443"
  local listen="::"
  local sni="www.microsoft.com"
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local sid="a1b2c3d4"

  local config
  config=$(create_reality_inbound "$uuid" "$port" "$listen" "$sni" "$priv" "$sid" 2>/dev/null) || {
    fail "Failed to generate configuration"
    teardown_test
    return 1
  }

  # Verify Reality is under tls, not top-level
  echo "$config" | jq -e '.tls.reality' >/dev/null || {
    fail "Reality not nested under tls"
    teardown_test
    return 1
  }

  # Verify Reality is NOT at top level
  if echo "$config" | jq -e '.reality' >/dev/null 2>&1; then
    fail "Reality should not be top-level"
    teardown_test
    return 1
  fi

  pass
  teardown_test
}

test_required_fields_present() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  local uuid="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  local port="443"
  local listen="::"
  local sni="www.microsoft.com"
  local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
  local sid="a1b2c3d4"

  local config
  config=$(create_reality_inbound "$uuid" "$port" "$listen" "$sni" "$priv" "$sid" 2>/dev/null) || {
    fail "Failed to generate configuration"
    teardown_test
    return 1
  }

  # Server-side required fields
  echo "$config" | jq -e '.tls.reality.private_key' >/dev/null || {
    fail "Missing private_key"
    teardown_test
    return 1
  }

  echo "$config" | jq -e '.tls.reality.short_id' >/dev/null || {
    fail "Missing short_id"
    teardown_test
    return 1
  }

  echo "$config" | jq -e '.tls.reality.handshake.server' >/dev/null || {
    fail "Missing handshake.server"
    teardown_test
    return 1
  }

  echo "$config" | jq -e '.tls.reality.handshake.server_port' >/dev/null || {
    fail "Missing handshake.server_port"
    teardown_test
    return 1
  }

  pass
  teardown_test
}

#==============================================================================
# Category 5: Export Format Tests
#==============================================================================

test_uri_format_compliance() {
  setup_test

  # Create mock client info
  export UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  export DOMAIN="test.example.com"
  export REALITY_PORT="443"
  export SNI="www.microsoft.com"
  export PUBLIC_KEY="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
  export SHORT_ID="a1b2c3d4"

  # Create temporary client-info file with required permissions
  cat > "$TEST_TEMP/client-info.txt" <<EOF
UUID=$UUID
DOMAIN=$DOMAIN
REALITY_PORT=$REALITY_PORT
SNI=$SNI
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF
  chmod 600 "$TEST_TEMP/client-info.txt"

  export TEST_CLIENT_INFO="$TEST_TEMP/client-info.txt"

  local uri
  uri=$(export_uri reality 2>/dev/null) || {
    fail "Failed to generate URI"
    teardown_test
    return 1
  }

  # Verify URI components
  [[ "$uri" =~ ^vless:// ]] || {
    fail "URI must start with vless://"
    teardown_test
    return 1
  }

  [[ "$uri" =~ security=reality ]] || {
    fail "Missing security=reality"
    teardown_test
    return 1
  }

  [[ "$uri" =~ flow=xtls-rprx-vision ]] || {
    fail "Missing flow=xtls-rprx-vision"
    teardown_test
    return 1
  }

  [[ "$uri" =~ type=tcp ]] || {
    fail "Missing type=tcp"
    teardown_test
    return 1
  }

  [[ "$uri" =~ pbk= ]] || {
    fail "Missing public key (pbk)"
    teardown_test
    return 1
  }

  [[ "$uri" =~ sid= ]] || {
    fail "Missing short ID (sid)"
    teardown_test
    return 1
  }

  pass
  teardown_test
}

test_flow_field_in_exports() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  # Create mock client info
  export UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  export DOMAIN="test.example.com"
  export REALITY_PORT="443"
  export SNI="www.microsoft.com"
  export PUBLIC_KEY="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
  export SHORT_ID="a1b2c3d4"

  cat > "$TEST_TEMP/client-info.txt" <<EOF
UUID=$UUID
DOMAIN=$DOMAIN
REALITY_PORT=$REALITY_PORT
SNI=$SNI
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF
  chmod 600 "$TEST_TEMP/client-info.txt"

  export TEST_CLIENT_INFO="$TEST_TEMP/client-info.txt"

  # Test v2rayN JSON export
  local v2rayn_json
  v2rayn_json=$(export_v2rayn_json reality 2>/dev/null) || {
    fail "Failed to generate v2rayN JSON"
    teardown_test
    return 1
  }

  echo "$v2rayn_json" | jq -e '.outbounds[0].settings.vnext[0].users[0].flow == "xtls-rprx-vision"' >/dev/null || {
    fail "v2rayN: Missing or incorrect flow field"
    teardown_test
    return 1
  }

  # Test URI export
  local uri
  uri=$(export_uri reality 2>/dev/null) || {
    fail "Failed to generate URI"
    teardown_test
    return 1
  }

  [[ "$uri" =~ flow=xtls-rprx-vision ]] || {
    fail "URI: Missing flow field"
    teardown_test
    return 1
  }

  pass
  teardown_test
}

test_public_key_not_private_key() {
  setup_test

  # Skip if jq not available
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not available"
    teardown_test
    return 0
  fi

  # Create mock client info with both keys
  export UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  export DOMAIN="test.example.com"
  export REALITY_PORT="443"
  export SNI="www.microsoft.com"
  export PUBLIC_KEY="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
  export SHORT_ID="a1b2c3d4"
  local PRIV="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"

  cat > "$TEST_TEMP/client-info.txt" <<EOF
UUID=$UUID
DOMAIN=$DOMAIN
REALITY_PORT=$REALITY_PORT
SNI=$SNI
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF
  chmod 600 "$TEST_TEMP/client-info.txt"

  export TEST_CLIENT_INFO="$TEST_TEMP/client-info.txt"

  # Ensure exports use public key, not private key
  local v2rayn_json
  v2rayn_json=$(export_v2rayn_json reality 2>/dev/null) || {
    fail "Failed to generate v2rayN JSON"
    teardown_test
    return 1
  }

  # Should contain public key
  echo "$v2rayn_json" | jq -e ".outbounds[0].streamSettings.realitySettings.publicKey == \"$PUBLIC_KEY\"" >/dev/null || {
    fail "Public key not found in export"
    teardown_test
    return 1
  }

  # Should NOT contain private key
  if echo "$v2rayn_json" | grep -q "$PRIV"; then
    fail "Private key leaked in client export!"
    teardown_test
    return 1
  fi

  pass
  teardown_test
}

#==============================================================================
# Test Runner
#==============================================================================

run_tests() {
  echo ""
  echo "==============================================="
  echo "Reality Configuration Test Suite"
  echo "==============================================="
  echo ""

  # Setup suite
  setup_suite

  echo ""
  echo "Category 1: Short ID Validation Tests"
  echo "---------------------------------------"
  test_short_id_valid_8_chars
  test_short_id_valid_4_chars
  test_short_id_valid_1_char
  test_short_id_invalid_empty
  test_short_id_invalid_9_chars
  test_short_id_invalid_16_chars_xray
  test_short_id_invalid_non_hex
  test_short_id_invalid_special_chars
  test_short_id_case_insensitive

  echo ""
  echo "Category 2: Reality Keypair Validation Tests"
  echo "----------------------------------------------"
  test_reality_keypair_valid
  test_reality_keypair_empty_private
  test_reality_keypair_empty_public
  test_reality_keypair_invalid_format

  echo ""
  echo "Category 3: Reality SNI Validation Tests"
  echo "------------------------------------------"
  test_reality_sni_valid_domain
  test_reality_sni_invalid_empty
  test_reality_sni_invalid_format

  echo ""
  echo "Category 4: Configuration Generation Tests"
  echo "-------------------------------------------"
  test_reality_config_structure
  test_short_id_array_format
  test_tls_reality_nesting
  test_required_fields_present

  echo ""
  echo "Category 5: Export Format Tests"
  echo "--------------------------------"
  test_uri_format_compliance
  test_flow_field_in_exports
  test_public_key_not_private_key

  # Teardown suite
  teardown_suite

  # Report results
  echo ""
  echo "==============================================="
  echo "Test Results"
  echo "==============================================="
  echo -e "Tests run:    ${BLUE}$TESTS_RUN${N}"
  echo -e "Passed:       ${G}$TESTS_PASSED${N}"
  echo -e "Failed:       ${R}$TESTS_FAILED${N}"
  echo -e "Skipped:      ${Y}$TESTS_SKIPPED${N}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${G}✓ All tests passed!${N}"
    return 0
  else
    echo -e "${R}✗ Some tests failed${N}"
    return 1
  fi
}

# Execute tests
run_tests
exit $?
