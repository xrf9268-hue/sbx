#!/usr/bin/env bash
# Unit tests for TUIC V5 and Trojan inbound configuration generation
# Tests: create_tuic_inbound(), create_trojan_inbound()
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
export TERM="xterm"
export SBX_TEST_MODE=1

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load modules under test
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/network.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/validation.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/config.sh"

trap - EXIT INT TERM

# Helper functions
assert_json_valid() {
  local test_name="$1"
  local json="$2"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if echo "${json}" | jq empty 2> /dev/null; then
    echo -e "${GREEN}✓${NC} ${test_name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} ${test_name} (invalid JSON)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

assert_json_value_equals() {
  local test_name="$1"
  local json="$2"
  local key_path="$3"
  local expected="$4"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local actual
  actual=$(echo "${json}" | jq -r "${key_path}" 2> /dev/null)
  if [[ "${actual}" == "${expected}" ]]; then
    echo -e "${GREEN}✓${NC} ${test_name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} ${test_name} (expected '${expected}', got '${actual}')"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

assert_json_has_key() {
  local test_name="$1"
  local json="$2"
  local key_path="$3"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local value
  value=$(echo "${json}" | jq -r "${key_path}" 2> /dev/null)
  if [[ -n "${value}" && "${value}" != "null" ]]; then
    echo -e "${GREEN}✓${NC} ${test_name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} ${test_name} (key '${key_path}' not found or null)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

assert_true() {
  local test_name="$1"
  local result="$2"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ "${result}" == "true" ]]; then
    echo -e "${GREEN}✓${NC} ${test_name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} ${test_name} (expected true, got '${result}')"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# ── Minimal TLS block for tests (manual cert mode with dummy paths) ──────────
_make_test_tls() {
  local alpn_json="$1"
  jq -n \
    --argjson alpn "${alpn_json}" \
    '{
      enabled: true,
      server_name: "test.example.com",
      alpn: $alpn,
      certificate_path: "/tmp/test-cert.pem",
      key_path: "/tmp/test-key.pem"
    }' 2> /dev/null
}

#==============================================================================
# TUIC V5 Tests
#==============================================================================

test_create_tuic_inbound_basic() {
  echo ""
  echo "Testing create_tuic_inbound() - Basic Functionality"
  echo "----------------------------------------------------"

  local test_uuid="123e4567-e89b-12d3-a456-426614174000"
  local test_pass="deadbeefcafebabe0102030405060708"
  local test_port="8445"
  local test_listen="::"
  local test_tls
  test_tls=$(_make_test_tls '["h3"]')

  local config
  config=$(create_tuic_inbound "${test_uuid}" "${test_pass}" "${test_port}" \
    "${test_listen}" "${test_tls}" 2> /dev/null)

  assert_json_valid "TUIC: generates valid JSON" "${config}"
  assert_json_value_equals "TUIC: type is tuic" "${config}" ".type" "tuic"
  assert_json_value_equals "TUIC: tag is in-tuic" "${config}" ".tag" "in-tuic"
  assert_json_value_equals "TUIC: listen is ::" "${config}" ".listen" "::"
  assert_json_value_equals "TUIC: port is 8445" "${config}" ".listen_port" "8445"
  assert_json_has_key "TUIC: has users array" "${config}" ".users"
  assert_json_has_key "TUIC: has tls section" "${config}" ".tls"
}

test_create_tuic_inbound_user_fields() {
  echo ""
  echo "Testing create_tuic_inbound() - User Fields"
  echo "--------------------------------------------"

  local test_uuid="123e4567-e89b-12d3-a456-426614174000"
  local test_pass="deadbeefcafebabe0102030405060708"
  local test_tls
  test_tls=$(_make_test_tls '["h3"]')

  local config
  config=$(create_tuic_inbound "${test_uuid}" "${test_pass}" "8445" \
    "::" "${test_tls}" 2> /dev/null)

  assert_json_value_equals "TUIC: user uuid matches" "${config}" ".users[0].uuid" "${test_uuid}"
  assert_json_value_equals "TUIC: user password matches" "${config}" ".users[0].password" "${test_pass}"
}

test_create_tuic_inbound_protocol_fields() {
  echo ""
  echo "Testing create_tuic_inbound() - Protocol Fields"
  echo "------------------------------------------------"

  local test_tls
  test_tls=$(_make_test_tls '["h3"]')

  local config
  config=$(create_tuic_inbound "uuid" "pass" "8445" "::" "${test_tls}" 2> /dev/null)

  assert_json_value_equals "TUIC: congestion_control is bbr" "${config}" ".congestion_control" "bbr"
  local zrtt
  zrtt=$(echo "${config}" | jq -r '.zero_rtt_handshake' 2> /dev/null)
  assert_true "TUIC: zero_rtt_handshake is false" "$([[ "${zrtt}" == "false" ]] && echo true || echo false)"
  assert_json_value_equals "TUIC: heartbeat is 10s" "${config}" ".heartbeat" "10s"
}

test_create_tuic_inbound_tls_alpn() {
  echo ""
  echo "Testing create_tuic_inbound() - TLS ALPN"
  echo "-----------------------------------------"

  local test_tls
  test_tls=$(_make_test_tls '["h3"]')

  local config
  config=$(create_tuic_inbound "uuid" "pass" "8445" "::" "${test_tls}" 2> /dev/null)

  assert_json_value_equals "TUIC: TLS alpn[0] is h3" "${config}" ".tls.alpn[0]" "h3"
  local tls_enabled
  tls_enabled=$(echo "${config}" | jq -r '.tls.enabled' 2> /dev/null)
  assert_true "TUIC: TLS enabled" "$([[ "${tls_enabled}" == "true" ]] && echo true || echo false)"
}

#==============================================================================
# Trojan Tests
#==============================================================================

test_create_trojan_inbound_basic() {
  echo ""
  echo "Testing create_trojan_inbound() - Basic Functionality"
  echo "------------------------------------------------------"

  local test_pass="deadbeefcafebabe0102030405060708"
  local test_port="8446"
  local test_listen="::"
  local test_tls
  test_tls=$(_make_test_tls '["h2","http/1.1"]')

  local config
  config=$(create_trojan_inbound "${test_pass}" "${test_port}" \
    "${test_listen}" "${test_tls}" 2> /dev/null)

  assert_json_valid "Trojan: generates valid JSON" "${config}"
  assert_json_value_equals "Trojan: type is trojan" "${config}" ".type" "trojan"
  assert_json_value_equals "Trojan: tag is in-trojan" "${config}" ".tag" "in-trojan"
  assert_json_value_equals "Trojan: listen is ::" "${config}" ".listen" "::"
  assert_json_value_equals "Trojan: port is 8446" "${config}" ".listen_port" "8446"
  assert_json_has_key "Trojan: has users array" "${config}" ".users"
  assert_json_has_key "Trojan: has tls section" "${config}" ".tls"
}

test_create_trojan_inbound_user_fields() {
  echo ""
  echo "Testing create_trojan_inbound() - User Fields"
  echo "----------------------------------------------"

  local test_pass="deadbeefcafebabe0102030405060708"
  local test_tls
  test_tls=$(_make_test_tls '["h2","http/1.1"]')

  local config
  config=$(create_trojan_inbound "${test_pass}" "8446" "::" "${test_tls}" 2> /dev/null)

  assert_json_value_equals "Trojan: user password matches" "${config}" ".users[0].password" "${test_pass}"
}

test_create_trojan_inbound_tls_alpn() {
  echo ""
  echo "Testing create_trojan_inbound() - TLS ALPN"
  echo "-------------------------------------------"

  local test_tls
  test_tls=$(_make_test_tls '["h2","http/1.1"]')

  local config
  config=$(create_trojan_inbound "pass" "8446" "::" "${test_tls}" 2> /dev/null)

  assert_json_value_equals "Trojan: TLS alpn[0] is h2" "${config}" ".tls.alpn[0]" "h2"
  assert_json_value_equals "Trojan: TLS alpn[1] is http/1.1" "${config}" ".tls.alpn[1]" "http/1.1"
  local tls_enabled
  tls_enabled=$(echo "${config}" | jq -r '.tls.enabled' 2> /dev/null)
  assert_true "Trojan: TLS enabled" "$([[ "${tls_enabled}" == "true" ]] && echo true || echo false)"
}

#==============================================================================
# Port constants tests
#==============================================================================

test_port_constants() {
  echo ""
  echo "Testing port constants"
  echo "----------------------"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ -n "${TUIC_PORT_DEFAULT:-}" && "${TUIC_PORT_DEFAULT}" -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} TUIC_PORT_DEFAULT is defined (${TUIC_PORT_DEFAULT})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} TUIC_PORT_DEFAULT not defined or invalid"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ -n "${TROJAN_PORT_DEFAULT:-}" && "${TROJAN_PORT_DEFAULT}" -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} TROJAN_PORT_DEFAULT is defined (${TROJAN_PORT_DEFAULT})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} TROJAN_PORT_DEFAULT not defined or invalid"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ -n "${TUIC_PORT_FALLBACK:-}" && "${TUIC_PORT_FALLBACK}" -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} TUIC_PORT_FALLBACK is defined (${TUIC_PORT_FALLBACK})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} TUIC_PORT_FALLBACK not defined or invalid"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ -n "${TROJAN_PORT_FALLBACK:-}" && "${TROJAN_PORT_FALLBACK}" -gt 0 ]]; then
    echo -e "${GREEN}✓${NC} TROJAN_PORT_FALLBACK is defined (${TROJAN_PORT_FALLBACK})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} TROJAN_PORT_FALLBACK not defined or invalid"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_function_exists() {
  echo ""
  echo "Testing function existence"
  echo "--------------------------"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if declare -f create_tuic_inbound > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} create_tuic_inbound is defined"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} create_tuic_inbound not defined"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if declare -f create_trojan_inbound > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} create_trojan_inbound is defined"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} create_trojan_inbound not defined"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

#==============================================================================
# Main
#==============================================================================

echo "=========================================="
echo "TUIC V5 and Trojan Configuration Tests"
echo "=========================================="

test_function_exists
test_port_constants
test_create_tuic_inbound_basic
test_create_tuic_inbound_user_fields
test_create_tuic_inbound_protocol_fields
test_create_tuic_inbound_tls_alpn
test_create_trojan_inbound_basic
test_create_trojan_inbound_user_fields
test_create_trojan_inbound_tls_alpn

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total:  ${TOTAL_TESTS}"
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]]; then
  echo "✓ All tests passed!"
  exit 0
else
  echo "✗ ${FAILED_TESTS} test(s) failed"
  exit 1
fi
