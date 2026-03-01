#!/usr/bin/env bash
# Unit tests for configuration generation functions (lib/config.sh)
# Tests for: create_base_config, create_reality_inbound, JSON validation
# Note: Don't use set -e here, we want to run all tests even if some fail
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
export TERM="xterm"

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load modules under test
# shellcheck source=../../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=../../lib/network.sh
source "${PROJECT_ROOT}/lib/network.sh"
# shellcheck source=../../lib/validation.sh
source "${PROJECT_ROOT}/lib/validation.sh"
# shellcheck source=../../lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"

# Test helper functions
assert_success() {
  local test_name="$1"
  local command="$2"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  if eval "$command" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} $test_name"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  return 0
}

assert_failure() {
  local test_name="$1"
  local command="$2"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  if eval "$command" > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} $test_name (expected failure, got success)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  else
    echo -e "${GREEN}✓${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  fi
  return 0
}

assert_json_valid() {
  local test_name="$1"
  local json_string="$2"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  if echo "$json_string" | jq empty 2> /dev/null; then
    echo -e "${GREEN}✓${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} $test_name (invalid JSON)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  return 0
}

assert_json_has_key() {
  local test_name="$1"
  local json_string="$2"
  local key_path="$3"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  local value
  value=$(echo "$json_string" | jq -r "$key_path" 2> /dev/null)

  if [[ -n "$value" && "$value" != "null" ]]; then
    echo -e "${GREEN}✓${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} $test_name (key '$key_path' not found or null)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  return 0
}

assert_json_value_equals() {
  local test_name="$1"
  local json_string="$2"
  local key_path="$3"
  local expected="$4"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  local actual
  actual=$(echo "$json_string" | jq -r "$key_path" 2> /dev/null)

  if [[ "$actual" == "$expected" ]]; then
    echo -e "${GREEN}✓${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} $test_name"
    echo -e "    Expected: '$expected'"
    echo -e "    Got:      '$actual'"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  return 0
}

#=============================================================================
# create_base_config() Tests
#=============================================================================

test_create_base_config_ipv4_only() {
  echo ""
  echo "Testing create_base_config() - IPv4-only Mode"
  echo "----------------------------------------------"

  local config
  config=$(create_base_config "false" "warn" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$config"
  assert_json_has_key "Has log section" "$config" ".log"
  assert_json_has_key "Has dns section" "$config" ".dns"
  assert_json_has_key "Has inbounds array" "$config" ".inbounds"
  assert_json_has_key "Has outbounds array" "$config" ".outbounds"

  # Check IPv4-only DNS strategy
  assert_json_value_equals "DNS strategy is ipv4_only" "$config" ".dns.strategy" "ipv4_only"

  # Check log level
  assert_json_value_equals "Log level is warn" "$config" ".log.level" "warn"

  # Check outbounds
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local outbound_count
  outbound_count=$(echo "$config" | jq '.outbounds | length' 2> /dev/null)
  if [[ "$outbound_count" -ge 1 ]]; then
    echo -e "${GREEN}✓${NC} Has outbounds (direct)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Missing outbounds (expected 1+, got $outbound_count)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_create_base_config_dual_stack() {
  echo ""
  echo "Testing create_base_config() - Dual-Stack Mode"
  echo "-----------------------------------------------"

  local config
  config=$(create_base_config "true" "info" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$config"

  # Check NO IPv4-only strategy for dual-stack
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local strategy
  strategy=$(echo "$config" | jq -r '.dns.strategy // "none"' 2> /dev/null)
  if [[ "$strategy" == "none" || "$strategy" == "null" ]]; then
    echo -e "${GREEN}✓${NC} DNS strategy not set (dual-stack default)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Unexpected DNS strategy: $strategy"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Check log level
  assert_json_value_equals "Log level is info" "$config" ".log.level" "info"
}

test_create_base_config_log_levels() {
  echo ""
  echo "Testing create_base_config() - Log Levels"
  echo "------------------------------------------"

  local levels=("trace" "debug" "info" "warn" "error" "fatal")

  for level in "${levels[@]}"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local config
    config=$(create_base_config "false" "$level" 2> /dev/null)

    local actual_level
    actual_level=$(echo "$config" | jq -r '.log.level' 2> /dev/null)

    if [[ "$actual_level" == "$level" ]]; then
      echo -e "${GREEN}✓${NC} Accepts log level: $level"
      PASSED_TESTS=$((PASSED_TESTS + 1))
    else
      echo -e "${RED}✗${NC} Failed to set log level: $level (got: $actual_level)"
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  done
}

#=============================================================================
# create_reality_inbound() Tests
#=============================================================================

test_create_reality_inbound_basic() {
  echo ""
  echo "Testing create_reality_inbound() - Basic Functionality"
  echo "------------------------------------------------------"

  # Test data
  local test_uuid="123e4567-e89b-12d3-a456-426614174000"
  local test_port="443"
  local test_listen="::"
  local test_sni="www.microsoft.com"
  local test_priv="EKlZxErkrHGkRKTyR7oiQ4jF-eO8w9BNYQ_MfB8BAnk"
  local test_sid="abcdef12"

  local reality_config
  reality_config=$(create_reality_inbound "$test_uuid" "$test_port" "$test_listen" \
    "$test_sni" "$test_priv" "$test_sid" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$reality_config"
  assert_json_has_key "Has type field" "$reality_config" ".type"
  assert_json_has_key "Has tag field" "$reality_config" ".tag"
  assert_json_has_key "Has listen field" "$reality_config" ".listen"
  assert_json_has_key "Has listen_port field" "$reality_config" ".listen_port"
  assert_json_has_key "Has users array" "$reality_config" ".users"
  assert_json_has_key "Has tls section" "$reality_config" ".tls"

  # Check specific values
  assert_json_value_equals "Type is vless" "$reality_config" ".type" "vless"
  assert_json_value_equals "Listen is ::" "$reality_config" ".listen" "::"
  assert_json_value_equals "Port is $test_port" "$reality_config" ".listen_port" "$test_port"

  # Check Reality TLS section
  assert_json_has_key "Has Reality config" "$reality_config" ".tls.reality"
  assert_json_has_key "Has private_key" "$reality_config" ".tls.reality.private_key"
  assert_json_has_key "Has short_id" "$reality_config" ".tls.reality.short_id"

  # Check user configuration
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local user_uuid
  user_uuid=$(echo "$reality_config" | jq -r '.users[0].uuid' 2> /dev/null)
  if [[ "$user_uuid" == "$test_uuid" ]]; then
    echo -e "${GREEN}✓${NC} User UUID correctly set"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} User UUID mismatch (expected: $test_uuid, got: $user_uuid)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_create_reality_inbound_security() {
  echo ""
  echo "Testing create_reality_inbound() - Security Features"
  echo "-----------------------------------------------------"

  local test_uuid="123e4567-e89b-12d3-a456-426614174000"
  local test_port="443"
  local test_listen="::"
  local test_sni="www.microsoft.com"
  local test_priv="EKlZxErkrHGkRKTyR7oiQ4jF-eO8w9BNYQ_MfB8BAnk"
  local test_sid="abcdef12"

  local reality_config
  reality_config=$(create_reality_inbound "$test_uuid" "$test_port" "$test_listen" \
    "$test_sni" "$test_priv" "$test_sid" 2> /dev/null)

  # Check for XTLS flow
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local flow
  flow=$(echo "$reality_config" | jq -r '.users[0].flow // "none"' 2> /dev/null)
  if [[ "$flow" == "xtls-rprx-vision" ]]; then
    echo -e "${GREEN}✓${NC} Uses XTLS-RPRX-Vision flow"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Missing or incorrect flow (got: $flow)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Check for max_time_difference (anti-replay protection)
  assert_json_has_key "Has anti-replay protection" "$reality_config" ".tls.reality.max_time_difference"

  # Check server_name (SNI)
  assert_json_value_equals "Server name is $test_sni" "$reality_config" ".tls.server_name" "$test_sni"
}

#=============================================================================
# JSON Structure Validation Tests
#=============================================================================

test_json_structure_compliance() {
  echo ""
  echo "Testing JSON Structure - sing-box 1.13.0+ Compliance"
  echo "-----------------------------------------------------"

  local base_config
  base_config=$(create_base_config "false" "warn" 2> /dev/null)

  # Check for required top-level sections
  assert_json_has_key "Has log section" "$base_config" ".log"
  assert_json_has_key "Has dns section" "$base_config" ".dns"
  assert_json_has_key "Has inbounds section" "$base_config" ".inbounds"
  assert_json_has_key "Has outbounds section" "$base_config" ".outbounds"

  # Check DNS servers format (sing-box 1.13.0+)
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local dns_server_type
  dns_server_type=$(echo "$base_config" | jq -r '.dns.servers[0].type' 2> /dev/null)
  if [[ "$dns_server_type" == "local" ]]; then
    echo -e "${GREEN}✓${NC} DNS server uses modern format (type: local)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} DNS server format incorrect (got type: $dns_server_type)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Check log has timestamp
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local log_timestamp
  log_timestamp=$(echo "$base_config" | jq -r '.log.timestamp' 2> /dev/null)
  if [[ "$log_timestamp" == "true" ]]; then
    echo -e "${GREEN}✓${NC} Log timestamp enabled"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Log timestamp not enabled"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_deprecated_fields_not_present() {
  echo ""
  echo "Testing Deprecated Fields - Not Present"
  echo "----------------------------------------"

  local reality_config
  reality_config=$(create_reality_inbound "test-uuid" "443" "::" \
    "www.microsoft.com" "test-key" "abcdef12" 2> /dev/null)

  # Check NO deprecated inbound fields (sing-box 1.13.0+)
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_sniff
  has_sniff=$(echo "$reality_config" | jq 'has("sniff")' 2> /dev/null)
  if [[ "$has_sniff" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No deprecated 'sniff' field in inbound"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Deprecated 'sniff' field present in inbound"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_sniff_override
  has_sniff_override=$(echo "$reality_config" | jq 'has("sniff_override_destination")' 2> /dev/null)
  if [[ "$has_sniff_override" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No deprecated 'sniff_override_destination' field"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Deprecated 'sniff_override_destination' field present"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Check outbound doesn't have deprecated domain_strategy
  local base_config
  base_config=$(create_base_config "false" "warn" 2> /dev/null)

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_domain_strategy
  has_domain_strategy=$(echo "$base_config" | jq '.outbounds[0] | has("domain_strategy")' 2> /dev/null)
  if [[ "$has_domain_strategy" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No deprecated 'domain_strategy' in outbounds"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Deprecated 'domain_strategy' field present in outbound"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

#=============================================================================
# _build_tls_block() Tests — ACME Configuration
#=============================================================================

test_build_tls_block_manual_cert() {
  echo ""
  echo "Testing _build_tls_block() - Manual Certificate Mode"
  echo "----------------------------------------------------"

  local tls_block
  tls_block=$(_build_tls_block "example.com" '["h2","http/1.1"]' \
    "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "" "" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$tls_block"
  assert_json_value_equals "TLS enabled" "$tls_block" ".enabled" "true"
  assert_json_value_equals "Server name set" "$tls_block" ".server_name" "example.com"
  assert_json_value_equals "Certificate path set" "$tls_block" ".certificate_path" "/etc/ssl/cert.pem"
  assert_json_value_equals "Key path set" "$tls_block" ".key_path" "/etc/ssl/key.pem"

  # Must NOT have acme block in manual mode
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_acme
  has_acme=$(echo "$tls_block" | jq 'has("acme")' 2> /dev/null)
  if [[ "$has_acme" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No ACME block in manual cert mode"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Unexpected ACME block in manual cert mode"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Check ALPN array
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local alpn_count
  alpn_count=$(echo "$tls_block" | jq '.alpn | length' 2> /dev/null)
  if [[ "$alpn_count" == "2" ]]; then
    echo -e "${GREEN}✓${NC} ALPN array has 2 entries"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} ALPN array length (expected 2, got $alpn_count)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_build_tls_block_acme_http01() {
  echo ""
  echo "Testing _build_tls_block() - ACME HTTP-01 Mode"
  echo "-----------------------------------------------"

  local tls_block
  tls_block=$(_build_tls_block "test.example.com" '["h2","http/1.1"]' \
    "" "" "acme" "" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$tls_block"
  assert_json_value_equals "TLS enabled" "$tls_block" ".enabled" "true"
  assert_json_value_equals "Server name set" "$tls_block" ".server_name" "test.example.com"
  assert_json_has_key "Has ACME block" "$tls_block" ".acme"
  assert_json_value_equals "ACME domain set" "$tls_block" ".acme.domain[0]" "test.example.com"
  assert_json_value_equals "ACME data directory" "$tls_block" ".acme.data_directory" "/var/lib/sing-box/acme"
  assert_json_value_equals "ACME provider is letsencrypt" "$tls_block" ".acme.provider" "letsencrypt"
  assert_json_value_equals "TLS-ALPN challenge disabled" "$tls_block" ".acme.disable_tls_alpn_challenge" "true"

  # HTTP-01 mode must NOT disable HTTP challenge
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_disable_http
  has_disable_http=$(echo "$tls_block" | jq '.acme | has("disable_http_challenge")' 2> /dev/null)
  if [[ "$has_disable_http" == "false" ]]; then
    echo -e "${GREEN}✓${NC} HTTP challenge not disabled (correct for HTTP-01)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} HTTP challenge disabled in HTTP-01 mode"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Must NOT have dns01_challenge block
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_dns01
  has_dns01=$(echo "$tls_block" | jq '.acme | has("dns01_challenge")' 2> /dev/null)
  if [[ "$has_dns01" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No DNS-01 block in HTTP-01 mode"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Unexpected DNS-01 block in HTTP-01 mode"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  # Must NOT have certificate_path (ACME manages certs)
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_cert_path
  has_cert_path=$(echo "$tls_block" | jq 'has("certificate_path")' 2> /dev/null)
  if [[ "$has_cert_path" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No certificate_path in ACME mode"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Unexpected certificate_path in ACME mode"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_build_tls_block_acme_dns01() {
  echo ""
  echo "Testing _build_tls_block() - ACME DNS-01 (Cloudflare)"
  echo "-----------------------------------------------------"

  local tls_block
  tls_block=$(_build_tls_block "dns.example.com" '["h2","http/1.1"]' \
    "" "" "cf_dns" "fake-cf-api-token-1234567890" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$tls_block"
  assert_json_value_equals "TLS enabled" "$tls_block" ".enabled" "true"
  assert_json_value_equals "Server name set" "$tls_block" ".server_name" "dns.example.com"
  assert_json_has_key "Has ACME block" "$tls_block" ".acme"
  assert_json_value_equals "ACME domain set" "$tls_block" ".acme.domain[0]" "dns.example.com"
  assert_json_value_equals "ACME provider is letsencrypt" "$tls_block" ".acme.provider" "letsencrypt"

  # DNS-01 must disable both HTTP and TLS-ALPN challenges
  assert_json_value_equals "HTTP challenge disabled" "$tls_block" ".acme.disable_http_challenge" "true"
  assert_json_value_equals "TLS-ALPN challenge disabled" "$tls_block" ".acme.disable_tls_alpn_challenge" "true"

  # DNS-01 challenge block
  assert_json_has_key "Has dns01_challenge" "$tls_block" ".acme.dns01_challenge"
  assert_json_value_equals "DNS provider is cloudflare" "$tls_block" ".acme.dns01_challenge.provider" "cloudflare"
  assert_json_value_equals "API token passed" "$tls_block" ".acme.dns01_challenge.api_token" "fake-cf-api-token-1234567890"
}

test_build_tls_block_caddy_compat() {
  echo ""
  echo "Testing _build_tls_block() - 'caddy' Maps to ACME"
  echo "--------------------------------------------------"

  # 'caddy' cert_mode should produce same output as 'acme'
  local tls_caddy tls_acme
  tls_caddy=$(_build_tls_block "compat.example.com" '["h2","http/1.1"]' \
    "" "" "caddy" "" 2> /dev/null)
  tls_acme=$(_build_tls_block "compat.example.com" '["h2","http/1.1"]' \
    "" "" "acme" "" 2> /dev/null)

  assert_json_valid "caddy mode generates valid JSON" "$tls_caddy"
  assert_json_has_key "caddy mode has ACME block" "$tls_caddy" ".acme"
  assert_json_value_equals "caddy mode uses letsencrypt" "$tls_caddy" ".acme.provider" "letsencrypt"

  # Both should produce identical TLS blocks
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [[ "$tls_caddy" == "$tls_acme" ]]; then
    echo -e "${GREEN}✓${NC} 'caddy' and 'acme' produce identical TLS config"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} 'caddy' and 'acme' TLS configs differ"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_build_tls_block_unknown_mode() {
  echo ""
  echo "Testing _build_tls_block() - Unknown Mode Rejected"
  echo "---------------------------------------------------"

  assert_failure "Rejects unknown cert_mode" \
    "_build_tls_block 'example.com' '[\"h2\"]' '' '' 'invalid_mode' '' 2>/dev/null"
}

#=============================================================================
# create_ws_inbound() Tests
#=============================================================================

test_create_ws_inbound_basic() {
  echo ""
  echo "Testing create_ws_inbound() - Basic Functionality"
  echo "--------------------------------------------------"

  local test_uuid="123e4567-e89b-12d3-a456-426614174000"
  local test_port="8444"
  local test_listen="::"
  local test_domain="ws.example.com"

  # Build a TLS block first
  local tls_json
  tls_json=$(_build_tls_block "${test_domain}" '["h2","http/1.1"]' \
    "" "" "acme" "" 2> /dev/null)

  local ws_config
  ws_config=$(create_ws_inbound "${test_uuid}" "${test_port}" "${test_listen}" \
    "${test_domain}" "${tls_json}" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$ws_config"
  assert_json_value_equals "Type is vless" "$ws_config" ".type" "vless"
  assert_json_value_equals "Tag is in-ws" "$ws_config" ".tag" "in-ws"
  assert_json_value_equals "Listen is ::" "$ws_config" ".listen" "::"
  assert_json_value_equals "Port is 8444" "$ws_config" ".listen_port" "8444"

  # Check user UUID
  assert_json_value_equals "User UUID set" "$ws_config" ".users[0].uuid" "${test_uuid}"

  # Check WS transport
  assert_json_value_equals "Transport type is ws" "$ws_config" ".transport.type" "ws"
  assert_json_value_equals "WS path is /ws" "$ws_config" ".transport.path" "/ws"

  # Check TLS with ACME is embedded
  assert_json_value_equals "TLS enabled" "$ws_config" ".tls.enabled" "true"
  assert_json_has_key "TLS has ACME block" "$ws_config" ".tls.acme"
  assert_json_value_equals "ACME domain correct" "$ws_config" ".tls.acme.domain[0]" "${test_domain}"
}

test_create_ws_inbound_manual_cert() {
  echo ""
  echo "Testing create_ws_inbound() - Manual Certificate"
  echo "-------------------------------------------------"

  local test_uuid="123e4567-e89b-12d3-a456-426614174000"

  local tls_json
  tls_json=$(_build_tls_block "manual.example.com" '["h2","http/1.1"]' \
    "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "" "" 2> /dev/null)

  local ws_config
  ws_config=$(create_ws_inbound "${test_uuid}" "443" "::" \
    "manual.example.com" "${tls_json}" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$ws_config"
  assert_json_value_equals "TLS has cert path" "$ws_config" ".tls.certificate_path" "/etc/ssl/cert.pem"
  assert_json_value_equals "TLS has key path" "$ws_config" ".tls.key_path" "/etc/ssl/key.pem"

  # Must NOT have ACME block
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local has_acme
  has_acme=$(echo "$ws_config" | jq '.tls | has("acme")' 2> /dev/null)
  if [[ "$has_acme" == "false" ]]; then
    echo -e "${GREEN}✓${NC} No ACME block with manual certs"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${RED}✗${NC} Unexpected ACME block with manual certs"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

#=============================================================================
# create_hysteria2_inbound() Tests
#=============================================================================

test_create_hysteria2_inbound_basic() {
  echo ""
  echo "Testing create_hysteria2_inbound() - Basic Functionality"
  echo "--------------------------------------------------------"

  local test_password="test-hy2-password-123"
  local test_port="8443"
  local test_listen="::"

  local tls_json
  tls_json=$(_build_tls_block "hy2.example.com" '["h3"]' \
    "" "" "acme" "" 2> /dev/null)

  local hy2_config
  hy2_config=$(create_hysteria2_inbound "${test_password}" "${test_port}" \
    "${test_listen}" "${tls_json}" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$hy2_config"
  assert_json_value_equals "Type is hysteria2" "$hy2_config" ".type" "hysteria2"
  assert_json_value_equals "Tag is in-hy2" "$hy2_config" ".tag" "in-hy2"
  assert_json_value_equals "Listen is ::" "$hy2_config" ".listen" "::"
  assert_json_value_equals "Port is 8443" "$hy2_config" ".listen_port" "8443"
  assert_json_value_equals "User password set" "$hy2_config" ".users[0].password" "${test_password}"

  # Check bandwidth limits
  assert_json_has_key "Has up_mbps" "$hy2_config" ".up_mbps"
  assert_json_has_key "Has down_mbps" "$hy2_config" ".down_mbps"

  # Check TLS with ACME
  assert_json_value_equals "TLS enabled" "$hy2_config" ".tls.enabled" "true"
  assert_json_has_key "TLS has ACME block" "$hy2_config" ".tls.acme"
}

test_create_hysteria2_inbound_dns01() {
  echo ""
  echo "Testing create_hysteria2_inbound() - DNS-01 Mode"
  echo "-------------------------------------------------"

  local tls_json
  tls_json=$(_build_tls_block "hy2-dns.example.com" '["h3"]' \
    "" "" "cf_dns" "fake-cf-token-abcdef" 2> /dev/null)

  local hy2_config
  hy2_config=$(create_hysteria2_inbound "password123" "8443" "::" \
    "${tls_json}" 2> /dev/null)

  assert_json_valid "Generates valid JSON" "$hy2_config"

  # Verify DNS-01 challenge is in the TLS block
  assert_json_has_key "Has dns01_challenge" "$hy2_config" ".tls.acme.dns01_challenge"
  assert_json_value_equals "DNS provider is cloudflare" "$hy2_config" ".tls.acme.dns01_challenge.provider" "cloudflare"
  assert_json_value_equals "HTTP challenge disabled" "$hy2_config" ".tls.acme.disable_http_challenge" "true"
}

#=============================================================================
# Error Handling Tests
#=============================================================================

test_error_handling() {
  echo ""
  echo "Testing Error Handling - Invalid Inputs"
  echo "----------------------------------------"

  # Test with empty UUID (should fail gracefully)
  assert_failure "Rejects empty UUID" \
    "create_reality_inbound '' '443' '::' 'www.microsoft.com' 'key' 'abcdef12' 2>/dev/null"

  # Test with invalid port (should fail gracefully)
  assert_failure "Rejects invalid port" \
    "create_reality_inbound 'uuid' '99999' '::' 'www.microsoft.com' 'key' 'abcdef12' 2>/dev/null"

  # Test with empty private key (should fail gracefully)
  assert_failure "Rejects empty private key" \
    "create_reality_inbound 'uuid' '443' '::' 'www.microsoft.com' '' 'abcdef12' 2>/dev/null"
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
  echo "========================================="
  echo "Configuration Generation Tests"
  echo "========================================="

  # Check if functions are exported/available
  echo ""
  echo "Pre-flight Checks"
  echo "-----------------"

  local required_functions=(
    "create_base_config"
    "create_reality_inbound"
    "_build_tls_block"
    "create_ws_inbound"
    "create_hysteria2_inbound"
  )

  local missing_functions=0
  for func in "${required_functions[@]}"; do
    if declare -f "$func" > /dev/null 2>&1; then
      echo -e "${GREEN}✓${NC} $func is available"
    else
      echo -e "${RED}✗${NC} $func is NOT available (not exported?)"
      missing_functions=$((missing_functions + 1))
    fi
  done

  # Check for jq
  if command -v jq > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} jq is available"
  else
    echo -e "${RED}✗${NC} jq is NOT available (required for config generation)"
    echo ""
    echo "ERROR: jq is required for configuration generation tests"
    exit 1
  fi

  if [[ $missing_functions -gt 0 ]]; then
    echo ""
    echo -e "${RED}ERROR:${NC} $missing_functions required function(s) not available"
    exit 1
  fi

  # Run test suites — base config + Reality
  test_create_base_config_ipv4_only
  test_create_base_config_dual_stack
  test_create_base_config_log_levels
  test_create_reality_inbound_basic
  test_create_reality_inbound_security
  test_json_structure_compliance
  test_deprecated_fields_not_present

  # Run test suites — ACME TLS block
  test_build_tls_block_manual_cert
  test_build_tls_block_acme_http01
  test_build_tls_block_acme_dns01
  test_build_tls_block_caddy_compat
  test_build_tls_block_unknown_mode

  # Run test suites — WS + Hysteria2 inbounds
  test_create_ws_inbound_basic
  test_create_ws_inbound_manual_cert
  test_create_hysteria2_inbound_basic
  test_create_hysteria2_inbound_dns01

  # Run test suites — error handling
  test_error_handling

  # Print summary
  echo ""
  echo "========================================="
  echo "Test Summary"
  echo "========================================="
  echo -e "Total:  $TOTAL_TESTS"
  echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
  echo -e "${RED}Failed: $FAILED_TESTS${NC}"
  echo ""

  if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

# Run tests
main "$@"
