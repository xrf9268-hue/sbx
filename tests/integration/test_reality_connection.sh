#!/usr/bin/env bash
# tests/integration/test_reality_connection.sh
# Integration test: Verify Reality configuration and service startup
# Part of sbx-lite Phase 4: Advanced Features

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Load common functions
# shellcheck source=/dev/null
source "$LIB_DIR/common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#==============================================================================
# Test Framework Functions
#==============================================================================

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${G}✓${N} ${FUNCNAME[1]}"
}

fail() {
  local message="${1:-No error message provided}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${R}✗${N} ${FUNCNAME[1]}: $message"
  return 1
}

#==============================================================================
# Integration Tests
#==============================================================================

test_singbox_binary_exists() {
  if [[ ! -f "/usr/local/bin/sing-box" ]]; then
    fail "sing-box binary not found at /usr/local/bin/sing-box"
    return 1
  fi

  if [[ ! -x "/usr/local/bin/sing-box" ]]; then
    fail "sing-box binary is not executable"
    return 1
  fi

  pass
}

test_singbox_version_check() {
  local version
  version=$(/usr/local/bin/sing-box version 2>&1 | grep -oP 'sing-box version \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

  if [[ "$version" == "unknown" ]]; then
    fail "Could not detect sing-box version"
    return 1
  fi

  echo "  Detected version: $version"
  pass
}

test_config_file_exists() {
  if [[ ! -f "/etc/sing-box/config.json" ]]; then
    fail "Configuration file not found at /etc/sing-box/config.json"
    return 1
  fi

  pass
}

test_config_json_syntax() {
  if ! have jq; then
    echo "  SKIP: jq not available"
    return 0
  fi

  if ! jq empty /etc/sing-box/config.json 2>/dev/null; then
    fail "Configuration has invalid JSON syntax"
    return 1
  fi

  pass
}

test_singbox_config_validation() {
  local output
  output=$(/usr/local/bin/sing-box check -c /etc/sing-box/config.json 2>&1) || {
    fail "sing-box config validation failed: $output"
    return 1
  }

  pass
}

test_reality_structure_validation() {
  if ! have jq; then
    echo "  SKIP: jq not available"
    return 0
  fi

  # Check Reality is nested under tls
  if ! jq -e '.inbounds[0].tls.reality' /etc/sing-box/config.json >/dev/null 2>&1; then
    fail "Reality configuration not found or improperly nested"
    return 1
  fi

  # Check Reality is enabled
  local reality_enabled
  reality_enabled=$(jq -r '.inbounds[0].tls.reality.enabled' /etc/sing-box/config.json 2>/dev/null)
  if [[ "$reality_enabled" != "true" ]]; then
    fail "Reality not enabled in configuration"
    return 1
  fi

  # Check short_id is array
  local sid_type
  sid_type=$(jq -r '.inbounds[0].tls.reality.short_id | type' /etc/sing-box/config.json 2>/dev/null)
  if [[ "$sid_type" != "array" ]]; then
    fail "Short ID must be array, got: $sid_type"
    return 1
  fi

  # Check flow field
  local flow
  flow=$(jq -r '.inbounds[0].users[0].flow' /etc/sing-box/config.json 2>/dev/null)
  if [[ "$flow" != "xtls-rprx-vision" ]]; then
    fail "Flow field must be xtls-rprx-vision, got: $flow"
    return 1
  fi

  pass
}

test_systemd_service_exists() {
  if [[ ! -f "/etc/systemd/system/sing-box.service" ]]; then
    fail "systemd service file not found"
    return 1
  fi

  pass
}

test_service_status() {
  if ! systemctl is-active sing-box >/dev/null 2>&1; then
    fail "sing-box service is not running"
    return 1
  fi

  pass
}

test_port_listening() {
  # Get configured port from config
  local port
  if have jq; then
    port=$(jq -r '.inbounds[0].listen_port' /etc/sing-box/config.json 2>/dev/null || echo "443")
  else
    port="443"
  fi

  if ! ss -lntp 2>/dev/null | grep -q ":${port}"; then
    fail "Port $port is not listening"
    return 1
  fi

  echo "  Port $port is listening"
  pass
}

test_service_logs_no_errors() {
  local logs
  logs=$(journalctl -u sing-box -n 50 --no-pager 2>/dev/null || echo "")

  if echo "$logs" | grep -qi "fatal\|panic"; then
    fail "Fatal errors found in service logs"
    return 1
  fi

  # Warnings are OK, but worth noting
  local warning_count
  warning_count=$(echo "$logs" | grep -ci "error" || echo "0")
  if [[ "$warning_count" -gt 0 ]]; then
    echo "  Note: $warning_count error messages in recent logs (may be normal)"
  fi

  pass
}

test_client_info_file() {
  if [[ ! -f "/etc/sing-box/client-info.txt" ]]; then
    fail "Client info file not found"
    return 1
  fi

  # Check required fields
  local required_fields=("UUID" "REALITY_PORT" "PUBLIC_KEY" "SHORT_ID")
  for field in "${required_fields[@]}"; do
    if ! grep -q "^${field}=" /etc/sing-box/client-info.txt 2>/dev/null; then
      fail "Missing $field in client-info.txt"
      return 1
    fi
  done

  pass
}

test_sbx_manager_exists() {
  if [[ ! -f "/usr/local/bin/sbx" ]]; then
    fail "sbx manager script not found"
    return 1
  fi

  if [[ ! -x "/usr/local/bin/sbx" ]]; then
    fail "sbx manager script is not executable"
    return 1
  fi

  pass
}

test_export_uri_reality() {
  if [[ ! -f "/usr/local/bin/sbx" ]]; then
    echo "  SKIP: sbx not installed"
    return 0
  fi

  local uri
  uri=$(/usr/local/bin/sbx export uri reality 2>/dev/null || echo "")

  if [[ -z "$uri" ]]; then
    fail "Failed to export Reality URI"
    return 1
  fi

  if [[ ! "$uri" =~ ^vless:// ]]; then
    fail "Invalid URI format: $uri"
    return 1
  fi

  if [[ ! "$uri" =~ security=reality ]]; then
    fail "URI missing security=reality"
    return 1
  fi

  if [[ ! "$uri" =~ flow=xtls-rprx-vision ]]; then
    fail "URI missing flow=xtls-rprx-vision"
    return 1
  fi

  echo "  URI exported successfully"
  pass
}

test_schema_validation() {
  # Load schema validator
  # shellcheck source=/dev/null
  source "$LIB_DIR/schema_validator.sh" 2>/dev/null || {
    echo "  SKIP: schema_validator.sh not available"
    return 0
  }

  if ! validate_reality_structure /etc/sing-box/config.json 2>/dev/null; then
    fail "Schema validation failed"
    return 1
  fi

  pass
}

test_version_compatibility() {
  # Load version module
  # shellcheck source=/dev/null
  source "$LIB_DIR/version.sh" 2>/dev/null || {
    echo "  SKIP: version.sh not available"
    return 0
  }

  local version
  version=$(get_singbox_version 2>/dev/null || echo "unknown")

  if [[ "$version" == "unknown" ]]; then
    echo "  SKIP: Could not detect version"
    return 0
  fi

  if ! version_meets_minimum "$version" "1.8.0"; then
    fail "Version $version does not meet minimum requirement (1.8.0)"
    return 1
  fi

  echo "  Version $version meets requirements"
  pass
}

#==============================================================================
# Test Runner
#==============================================================================

run_integration_tests() {
  echo ""
  echo "==============================================="
  echo "Reality Integration Test Suite"
  echo "==============================================="
  echo ""
  echo "Testing installed sing-box Reality configuration"
  echo ""

  echo "Binary and Configuration Tests"
  echo "--------------------------------"
  test_singbox_binary_exists
  test_singbox_version_check
  test_config_file_exists
  test_config_json_syntax
  test_singbox_config_validation

  echo ""
  echo "Reality Structure Tests"
  echo "-----------------------"
  test_reality_structure_validation
  test_schema_validation

  echo ""
  echo "Service Tests"
  echo "-------------"
  test_systemd_service_exists
  test_service_status
  test_port_listening
  test_service_logs_no_errors

  echo ""
  echo "Client Information Tests"
  echo "------------------------"
  test_client_info_file
  test_sbx_manager_exists
  test_export_uri_reality

  echo ""
  echo "Version Compatibility Tests"
  echo "---------------------------"
  test_version_compatibility

  # Report results
  echo ""
  echo "==============================================="
  echo "Integration Test Results"
  echo "==============================================="
  echo -e "Tests run:    ${BLUE}$TESTS_RUN${N}"
  echo -e "Passed:       ${G}$TESTS_PASSED${N}"
  echo -e "Failed:       ${R}$TESTS_FAILED${N}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${G}✓ All integration tests passed!${N}"
    echo ""
    echo "sing-box Reality configuration is working correctly."
    return 0
  else
    echo -e "${R}✗ Some integration tests failed${N}"
    echo ""
    echo "Please review the errors above and check:"
    echo "  - sing-box service status: systemctl status sing-box"
    echo "  - Configuration validity: sing-box check -c /etc/sing-box/config.json"
    echo "  - Service logs: journalctl -u sing-box -n 50"
    return 1
  fi
}

# Only run tests if sing-box is installed
if [[ ! -f "/usr/local/bin/sing-box" ]]; then
  echo "sing-box not installed. Integration tests require a working installation."
  echo ""
  echo "To install sing-box:"
  echo "  bash install.sh"
  echo ""
  exit 0
fi

# Execute integration tests
run_integration_tests
exit $?
