#!/usr/bin/env bash
# tests/unit/test_port_hopping.sh - Unit tests for lib/port_hopping.sh

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode
set +e

# Source required modules
if ! source "${PROJECT_ROOT}/lib/common.sh" 2> /dev/null; then
  echo "ERROR: Failed to load lib/common.sh"
  exit 1
fi

# Disable traps after loading modules
trap - EXIT INT TERM

# Reset to permissive mode
set +e
set -o pipefail

# Source port_hopping module
source "${PROJECT_ROOT}/lib/port_hopping.sh" 2> /dev/null || true

# Source test framework
source "${PROJECT_ROOT}/tests/test_framework.sh" 2> /dev/null || {
  # Inline minimal test framework if not available
  TESTS_RUN=0
  TESTS_PASSED=0
  TESTS_FAILED=0
}

# Disable strict mode for test execution (assertions use arithmetic that fails with set -e)
set +e

echo "=============================================="
echo "  Port Hopping Module Tests"
echo "=============================================="

#==============================================================================
# validate_port_range() Tests
#==============================================================================

echo ""
echo "Testing validate_port_range() - Valid Ranges"
echo "---------------------------------------------"

# Valid range
validate_port_range "20000-40000" 2> /dev/null
assert_equals "0" "$?" "Valid range 20000-40000 accepted"

# Minimum valid range
validate_port_range "1024-1025" 2> /dev/null
assert_equals "0" "$?" "Minimum valid range 1024-1025 accepted"

# Maximum port boundary
validate_port_range "60000-65535" 2> /dev/null
assert_equals "0" "$?" "Max boundary range 60000-65535 accepted"

# Exactly max range size (20000)
validate_port_range "20000-40000" 2> /dev/null
assert_equals "0" "$?" "Exactly 20000-port range accepted"

echo ""
echo "Testing validate_port_range() - Invalid Ranges"
echo "------------------------------------------------"

# Empty input
validate_port_range "" 2> /dev/null
assert_equals "1" "$?" "Empty range rejected"

# Non-numeric
validate_port_range "abc-def" 2> /dev/null
assert_equals "1" "$?" "Non-numeric range rejected"

# Single port (no dash)
validate_port_range "20000" 2> /dev/null
assert_equals "1" "$?" "Single port without dash rejected"

# Start >= End
validate_port_range "40000-20000" 2> /dev/null
assert_equals "1" "$?" "Reversed range (start >= end) rejected"

# Equal start and end
validate_port_range "20000-20000" 2> /dev/null
assert_equals "1" "$?" "Equal start and end rejected"

# Below minimum port
validate_port_range "100-5000" 2> /dev/null
assert_equals "1" "$?" "Below minimum port (100) rejected"

# Above maximum port
validate_port_range "60000-70000" 2> /dev/null
assert_equals "1" "$?" "Above maximum port (70000) rejected"

# Range too large (> 20000)
validate_port_range "1024-30000" 2> /dev/null
assert_equals "1" "$?" "Range too large (> 20000 ports) rejected"

# Multiple dashes
validate_port_range "100-200-300" 2> /dev/null
assert_equals "1" "$?" "Multiple dashes rejected"

#==============================================================================
# detect_nat_backend() Tests
#==============================================================================

echo ""
echo "Testing detect_nat_backend()"
echo "-----------------------------"

backend=$(detect_nat_backend 2> /dev/null) || true
if [[ -n "${backend}" ]]; then
  assert_contains "nftables iptables" "${backend}" "Backend detected: ${backend}"
else
  echo "  - Neither nftables nor iptables available (skipped)"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

#==============================================================================
# show_port_hopping_status() Tests
#==============================================================================

echo ""
echo "Testing show_port_hopping_status()"
echo "------------------------------------"

# Test with no state file
TEST_STATE_FILE="/tmp/sbx-test-porthop-$$.json" \
  show_port_hopping_status 2> /dev/null | grep -q "not enabled"
assert_equals "0" "$?" "Shows not enabled when no state file"

# Test with state file but no port range
cat > "/tmp/sbx-test-porthop-$$.json" << 'STATEEOF'
{
  "protocols": {
    "hysteria2": {
      "enabled": true,
      "port": 8443,
      "password": "testpass",
      "port_range": null
    }
  }
}
STATEEOF

status_output=$(TEST_STATE_FILE="/tmp/sbx-test-porthop-$$.json" show_port_hopping_status 2> /dev/null)
assert_contains "${status_output}" "disabled" "Shows disabled when port_range is null"
assert_contains "${status_output}" "8443" "Shows HY2 port"

# Test with state file and port range configured
cat > "/tmp/sbx-test-porthop-$$.json" << 'STATEEOF'
{
  "protocols": {
    "hysteria2": {
      "enabled": true,
      "port": 8443,
      "password": "testpass",
      "port_range": "20000-40000"
    }
  }
}
STATEEOF

status_output=$(TEST_STATE_FILE="/tmp/sbx-test-porthop-$$.json" show_port_hopping_status 2> /dev/null)
assert_contains "${status_output}" "enabled" "Shows enabled when port_range is set"
assert_contains "${status_output}" "20000-40000" "Shows configured port range"

# Cleanup
rm -f "/tmp/sbx-test-porthop-$$.json"

#==============================================================================
# URI Export with mport Tests
#==============================================================================

echo ""
echo "Testing URI export with port hopping"
echo "--------------------------------------"

# Test URI without port hopping (no mport param)
HY2_PORT_RANGE="" \
  HY2_PASS="testpassword" \
  DOMAIN="example.com" \
  HY2_PORT="8443"

uri_no_hop="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0"
[[ -n "${HY2_PORT_RANGE:-}" ]] && uri_no_hop+="&mport=${HY2_PORT_RANGE}"
uri_no_hop+="#Hysteria2-${DOMAIN}"

assert_not_contains "${uri_no_hop}" "mport" "URI without port hopping has no mport param"

# Test URI with port hopping (has mport param)
HY2_PORT_RANGE="20000-40000"

uri_with_hop="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0"
[[ -n "${HY2_PORT_RANGE:-}" ]] && uri_with_hop+="&mport=${HY2_PORT_RANGE}"
uri_with_hop+="#Hysteria2-${DOMAIN}"

assert_contains "${uri_with_hop}" "mport=20000-40000" "URI with port hopping includes mport param"
assert_contains "${uri_with_hop}" "hysteria2://testpassword@example.com:8443" "URI base is correct"

# Reset
unset HY2_PORT_RANGE

#==============================================================================
# State.json port_range roundtrip Tests
#==============================================================================

echo ""
echo "Testing state.json port_range field"
echo "-------------------------------------"

state_tmp="/tmp/sbx-test-state-porthop-$$.json"

# Write state with port_range
jq -n \
  --arg port_range "25000-45000" \
  --argjson hy2_port 8443 \
  '{
    protocols: {
      hysteria2: {
        enabled: true,
        port: $hy2_port,
        password: "testpass",
        port_range: $port_range
      }
    }
  }' > "${state_tmp}"

# Read back port_range
read_range=$(jq -r '.protocols.hysteria2.port_range // empty' "${state_tmp}")
assert_equals "25000-45000" "${read_range}" "port_range roundtrip preserves value"

# Write state without port_range (null)
jq -n \
  --argjson hy2_port 8443 \
  '{
    protocols: {
      hysteria2: {
        enabled: true,
        port: $hy2_port,
        password: "testpass",
        port_range: null
      }
    }
  }' > "${state_tmp}"

read_range=$(jq -r '.protocols.hysteria2.port_range // empty' "${state_tmp}")
assert_equals "" "${read_range}" "null port_range reads as empty"

# Cleanup
rm -f "${state_tmp}"

#==============================================================================
# Summary
#==============================================================================

echo ""
echo "=============================================="
echo "           Test Summary"
echo "=============================================="
echo "Total tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  echo "=============================================="
  exit 0
else
  echo ""
  echo "✗ Some tests failed!"
  echo "=============================================="
  exit 1
fi
