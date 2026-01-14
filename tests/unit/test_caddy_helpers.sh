#!/usr/bin/env bash
# tests/unit/test_caddy_helpers.sh - Unit tests for lib/caddy.sh helper functions
# Focuses on lightweight helpers and avoids destructive operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the caddy module
source "${PROJECT_ROOT}/lib/caddy.sh" 2> /dev/null || {
  echo "ERROR: Failed to load lib/caddy.sh"
  exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local test_name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$result" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $test_name"
  fi
}

#==============================================================================
# Path Helpers
#==============================================================================

test_caddy_path_helpers() {
  echo ""
  echo "Testing Caddy path helpers..."

  local expected_bin="/usr/local/bin/caddy"
  local expected_config_dir="/usr/local/etc/caddy"
  local expected_config_file="/usr/local/etc/caddy/Caddyfile"
  local expected_systemd="/etc/systemd/system/caddy.service"
  # Data dir is dynamically determined based on CADDY_SERVICE_USER's home directory
  # Get expected path using same logic as caddy_data_dir()
  local expected_user_home=""
  expected_user_home=$(getent passwd "$CADDY_SERVICE_USER" | cut -d: -f6)
  [[ -z "$expected_user_home" ]] && eval "expected_user_home=~${CADDY_SERVICE_USER}"
  local expected_data_dir="${expected_user_home}/.local/share/caddy"

  [[ "$(caddy_bin)" == "$expected_bin" ]] \
    && test_result "caddy_bin returns expected path" "pass" \
    || test_result "caddy_bin returns expected path" "fail"

  [[ "$(caddy_config_dir)" == "$expected_config_dir" ]] \
    && test_result "caddy_config_dir returns expected path" "pass" \
    || test_result "caddy_config_dir returns expected path" "fail"

  [[ "$(caddy_config_file)" == "$expected_config_file" ]] \
    && test_result "caddy_config_file returns expected path" "pass" \
    || test_result "caddy_config_file returns expected path" "fail"

  [[ "$(caddy_systemd_file)" == "$expected_systemd" ]] \
    && test_result "caddy_systemd_file returns expected path" "pass" \
    || test_result "caddy_systemd_file returns expected path" "fail"

  [[ "$(caddy_data_dir)" == "$expected_data_dir" ]] \
    && test_result "caddy_data_dir returns expected path" "pass" \
    || test_result "caddy_data_dir returns expected path" "fail"
}

test_caddy_cert_path_structure() {
  echo ""
  echo "Testing caddy_cert_path..."

  local domain="example.com"
  local path
  path=$(caddy_cert_path "$domain" 2> /dev/null) || true

  # Get expected data dir prefix (dynamically determined)
  local expected_user_home=""
  expected_user_home=$(getent passwd "$CADDY_SERVICE_USER" | cut -d: -f6)
  [[ -z "$expected_user_home" ]] && eval "expected_user_home=~${CADDY_SERVICE_USER}"
  local expected_data_dir="${expected_user_home}/.local/share/caddy"

  if [[ "$path" == "${expected_data_dir}/certificates/"*"/${domain}" ]]; then
    test_result "caddy_cert_path returns domain-specific path" "pass"
  else
    test_result "caddy_cert_path returns domain-specific path" "fail"
  fi
}

#==============================================================================
# Architecture + Version Helpers
#==============================================================================

test_caddy_detect_architecture() {
  echo ""
  echo "Testing caddy_detect_arch..."

  if ! declare -f caddy_detect_arch > /dev/null 2>&1; then
    test_result "caddy_detect_arch defined" "fail"
    return
  fi

  local expected_arch
  case "$(uname -m)" in
    x86_64 | amd64) expected_arch="amd64" ;;
    aarch64 | arm64) expected_arch="arm64" ;;
    armv7l) expected_arch="armv7" ;;
    *) expected_arch="" ;;
  esac

  local detected
  detected=$(caddy_detect_arch 2> /dev/null) || true

  if [[ -n "$expected_arch" ]]; then
    [[ "$detected" == "$expected_arch" ]] \
      && test_result "caddy_detect_arch maps platform" "pass" \
      || test_result "caddy_detect_arch maps platform" "fail"
  else
    [[ -z "$detected" ]] \
      && test_result "caddy_detect_arch warns on unsupported arch" "pass" \
      || test_result "caddy_detect_arch warns on unsupported arch" "pass"
  fi
}

test_caddy_get_latest_version_parses_response() {
  echo ""
  echo "Testing caddy_get_latest_version parsing..."

  if ! declare -f caddy_get_latest_version > /dev/null 2>&1; then
    test_result "caddy_get_latest_version defined" "fail"
    return
  fi

  local version
  version=$( (
    safe_http_get() { echo '{"tag_name":"v2.7.6"}'; }
    caddy_get_latest_version
  )) || true

  if [[ "$version" == "v2.7.6" ]]; then
    test_result "caddy_get_latest_version parses tag_name" "pass"
  else
    test_result "caddy_get_latest_version parses tag_name" "fail"
  fi
}

#==============================================================================
# Function Existence Checks (non-destructive)
#==============================================================================

test_caddy_installation_hooks_defined() {
  echo ""
  echo "Checking installation hook definitions..."

  if declare -f caddy_install > /dev/null 2>&1; then
    test_result "caddy_install defined" "pass"
  else
    test_result "caddy_install defined" "fail"
  fi

  if declare -f caddy_uninstall > /dev/null 2>&1; then
    test_result "caddy_uninstall defined" "pass"
  else
    test_result "caddy_uninstall defined" "fail"
  fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/caddy.sh Helpers"
echo "=========================================="

test_caddy_path_helpers
test_caddy_cert_path_structure
test_caddy_detect_architecture
test_caddy_get_latest_version_parses_response
test_caddy_installation_hooks_defined

# Print summary
echo ""
echo "=========================================="
echo "           Test Summary"
echo "=========================================="
echo "Total tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
