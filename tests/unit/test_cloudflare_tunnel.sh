#!/usr/bin/env bash
# tests/unit/test_cloudflare_tunnel.sh - Unit tests for lib/cloudflare_tunnel.sh
#
# Validates arch detection, config writers and state.json updates without
# touching the real system. Mirrors the structure used by other lib unit
# tests (see test_service_functions.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Per-run sandbox so the test never writes to /etc/cloudflared.
TEST_TMP_DIR=$(mktemp -d -t sbx-cf-tunnel-test-XXXXXX)

export CLOUDFLARED_BIN="${TEST_TMP_DIR}/cloudflared"
export CLOUDFLARED_SVC="${TEST_TMP_DIR}/cloudflared.service"
export CLOUDFLARED_CONF_DIR="${TEST_TMP_DIR}/etc-cloudflared"
export CLOUDFLARED_CONFIG="${CLOUDFLARED_CONF_DIR}/config.yml"
export CLOUDFLARED_ENV_FILE="${CLOUDFLARED_CONF_DIR}/tunnel.env"
mkdir -p "${CLOUDFLARED_CONF_DIR}"

# Source modules. Each re-enables strict mode and may install its own EXIT trap;
# we override both after all sources complete so the test driver itself can run
# negative-path assertions without aborting.
source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
  echo "ERROR: Failed to load lib/common.sh"
  exit 1
}
source "${PROJECT_ROOT}/lib/network.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/download.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/checksum.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/cloudflare_tunnel.sh" 2>/dev/null || {
  echo "ERROR: Failed to source lib/cloudflare_tunnel.sh"
  exit 1
}

set +eu
set -o pipefail
trap - EXIT INT TERM
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${result}" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${name}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${name}"
  fi
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      expected: ${expected}"
    echo "      actual:   ${actual}"
  fi
}

assert_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      missing: ${needle}"
  fi
}

echo "=== Cloudflare Tunnel Module Unit Tests ==="

#==============================================================================
# Arch detection
#==============================================================================
echo ""
echo "Testing cloudflared_detect_arch..."

SBX_FAKE_UNAME_M="x86_64" assert_eq "x86_64 -> amd64" "amd64" "$(SBX_FAKE_UNAME_M=x86_64 cloudflared_detect_arch)"
SBX_FAKE_UNAME_M="aarch64" assert_eq "aarch64 -> arm64" "arm64" "$(SBX_FAKE_UNAME_M=aarch64 cloudflared_detect_arch)"
SBX_FAKE_UNAME_M="armv7l" assert_eq "armv7l -> arm" "arm" "$(SBX_FAKE_UNAME_M=armv7l cloudflared_detect_arch)"
SBX_FAKE_UNAME_M="i686" assert_eq "i686 -> 386" "386" "$(SBX_FAKE_UNAME_M=i686 cloudflared_detect_arch)"
out=$(SBX_FAKE_UNAME_M="sparc64" cloudflared_detect_arch 2>/dev/null)
rc=$?
if [[ ${rc} -ne 0 && -z "${out}" ]]; then
  test_result "unsupported arch returns nonzero" "pass"
else
  test_result "unsupported arch returns nonzero" "fail"
fi

#==============================================================================
# config.yml writer
#==============================================================================
echo ""
echo "Testing cloudflared_write_config_yml..."

cloudflared_write_config_yml "h.example.com" 8444 >/dev/null 2>&1
yml_content=""
[[ -f "${CLOUDFLARED_CONFIG}" ]] && yml_content=$(cat "${CLOUDFLARED_CONFIG}")
assert_contains "config.yml has hostname" "hostname: h.example.com" "${yml_content}"
assert_contains "config.yml has localhost upstream" "service: http://127.0.0.1:8444" "${yml_content}"
assert_contains "config.yml has 404 catch-all" "service: http_status:404" "${yml_content}"

perm=$(stat -c '%a' "${CLOUDFLARED_CONFIG}" 2>/dev/null || stat -f '%Lp' "${CLOUDFLARED_CONFIG}" 2>/dev/null)
assert_eq "config.yml is mode 600" "600" "${perm}"

#==============================================================================
# env file writer
#==============================================================================
echo ""
echo "Testing cloudflared_write_env_file..."

cloudflared_write_env_file "test-token-abc123" >/dev/null 2>&1
env_content=""
[[ -f "${CLOUDFLARED_ENV_FILE}" ]] && env_content=$(cat "${CLOUDFLARED_ENV_FILE}")
assert_contains "env file has TUNNEL_TOKEN" "TUNNEL_TOKEN=test-token-abc123" "${env_content}"
perm=$(stat -c '%a' "${CLOUDFLARED_ENV_FILE}" 2>/dev/null || stat -f '%Lp' "${CLOUDFLARED_ENV_FILE}" 2>/dev/null)
assert_eq "env file is mode 600" "600" "${perm}"

#==============================================================================
# systemd unit writer
#==============================================================================
echo ""
echo "Testing cloudflared_write_service_file..."

cloudflared_write_service_file "token" >/dev/null 2>&1
unit_content=""
[[ -f "${CLOUDFLARED_SVC}" ]] && unit_content=$(cat "${CLOUDFLARED_SVC}")
assert_contains "unit has [Unit]" "[Unit]" "${unit_content}"
assert_contains "unit has [Service]" "[Service]" "${unit_content}"
assert_contains "unit has [Install]" "[Install]" "${unit_content}"
assert_contains "unit references EnvironmentFile" "EnvironmentFile=-${CLOUDFLARED_ENV_FILE}" "${unit_content}"
assert_contains "unit ExecStart uses tunnel run --token" 'tunnel run --token ${TUNNEL_TOKEN}' "${unit_content}"
assert_contains "unit hardened with NoNewPrivileges" "NoNewPrivileges=true" "${unit_content}"
assert_contains "unit hardened with ProtectSystem" "ProtectSystem=strict" "${unit_content}"

cloudflared_write_service_file "quick" >/dev/null 2>&1
unit_quick=""
[[ -f "${CLOUDFLARED_SVC}" ]] && unit_quick=$(cat "${CLOUDFLARED_SVC}")
assert_contains "quick mode ExecStart uses --url" "tunnel --url http://127.0.0.1:" "${unit_quick}"

# Negative: bogus mode
out=$(cloudflared_write_service_file "bogus" 2>&1)
rc=$?
if [[ ${rc} -ne 0 ]]; then
  test_result "unknown mode returns nonzero" "pass"
else
  test_result "unknown mode returns nonzero" "fail"
fi

#==============================================================================
# State updates
#==============================================================================
echo ""
echo "Testing cloudflared_update_state..."

if command -v jq >/dev/null 2>&1; then
  state_file="${TEST_TMP_DIR}/state.json"
  cat >"${state_file}" <<'JSON'
{
  "version": "1.0",
  "server": {"domain": null, "ip": "203.0.113.1"},
  "protocols": {"reality": {"enabled": true}}
}
JSON
  TEST_STATE_FILE="${state_file}" cloudflared_update_state "true" "token" "abc.example.com" 8444 >/dev/null 2>&1
  enabled=$(jq -r '.tunnel.enabled' "${state_file}")
  mode=$(jq -r '.tunnel.mode' "${state_file}")
  hostname=$(jq -r '.tunnel.hostname' "${state_file}")
  upstream=$(jq -r '.tunnel.upstream_port' "${state_file}")
  assert_eq "state.tunnel.enabled" "true" "${enabled}"
  assert_eq "state.tunnel.mode" "token" "${mode}"
  assert_eq "state.tunnel.hostname" "abc.example.com" "${hostname}"
  assert_eq "state.tunnel.upstream_port" "8444" "${upstream}"

  # Disable path: nulls out hostname/mode but keeps file valid JSON
  TEST_STATE_FILE="${state_file}" cloudflared_update_state "false" "" "" 0 >/dev/null 2>&1
  enabled=$(jq -r '.tunnel.enabled' "${state_file}")
  hostname=$(jq -r '.tunnel.hostname' "${state_file}")
  assert_eq "state.tunnel.enabled after disable" "false" "${enabled}"
  assert_eq "state.tunnel.hostname after disable" "null" "${hostname}"
  jq empty "${state_file}" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    test_result "state.json remains valid JSON after disable" "pass"
  else
    test_result "state.json remains valid JSON after disable" "fail"
  fi
else
  echo "  (skipping state tests: jq not installed)"
fi

#==============================================================================
# Function exports
#==============================================================================
echo ""
echo "Testing exported API surface..."

for fn in cloudflared_install cloudflared_enable_token cloudflared_disable \
  cloudflared_status cloudflared_update_state cloudflared_current_hostname \
  cloudflared_detect_arch cloudflared_write_config_yml \
  cloudflared_write_service_file cloudflared_write_env_file; do
  if declare -F "${fn}" >/dev/null 2>&1; then
    test_result "${fn} is defined" "pass"
  else
    test_result "${fn} is defined" "fail"
  fi
done

#==============================================================================
# Module is registered in install.sh modules array
#==============================================================================
echo ""
echo "Testing install.sh registration..."

if grep -qE 'local modules=\(.*\bcloudflare_tunnel\b.*\)' "${PROJECT_ROOT}/install.sh"; then
  test_result "cloudflare_tunnel registered in install.sh modules array" "pass"
else
  test_result "cloudflare_tunnel registered in install.sh modules array" "fail"
fi

if grep -q '\["cloudflare_tunnel"\]=' "${PROJECT_ROOT}/install.sh"; then
  test_result "cloudflare_tunnel API contract registered" "pass"
else
  test_result "cloudflare_tunnel API contract registered" "fail"
fi

#==============================================================================
# Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -eq 0 ]]; then
  exit 0
else
  exit 1
fi
