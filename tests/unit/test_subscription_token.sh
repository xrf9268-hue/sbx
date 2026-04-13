#!/usr/bin/env bash
# tests/unit/test_subscription_token.sh
# Verifies token lifecycle (generate, enable, rotate, url) against a
# fixture state.json. Uses SUB_UNIT_DRY_RUN to avoid touching systemd.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
STATE_FILE_PATH=""
CACHE_DIR=""

setup_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-sub-token.XXXXXX)
  STATE_FILE_PATH="${TEST_TMP}/state.json"
  CACHE_DIR="${TEST_TMP}/cache"
  mkdir -p "${CACHE_DIR}"

  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-01T00:00:00Z",
  "mode": "multi_protocol",
  "server": {
    "domain": "example.com",
    "ip": null
  },
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "public_key": "pubkey_fixture",
      "short_id": "cafebabe",
      "sni": "www.microsoft.com"
    },
    "ws_tls": {"enabled": false, "port": null, "certificate": null, "key": null},
    "hysteria2": {"enabled": false, "port": null, "password": null, "port_range": null},
    "tuic": {"enabled": false, "port": null, "password": null},
    "trojan": {"enabled": false, "port": null, "password": null}
  },
  "subscription": {
    "enabled": false,
    "port": 8838,
    "bind": "127.0.0.1",
    "token": "",
    "path": "/sub",
    "created_at": null
  }
}
EOF
  chmod 600 "${STATE_FILE_PATH}"
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

_run_subscription() {
  local cmd="$1"
  TEST_STATE_FILE="${STATE_FILE_PATH}" \
    TEST_CLIENT_INFO="${TEST_TMP}/nope" \
    SUB_UNIT_DRY_RUN=1 \
    SUB_CACHE_DIR_OVERRIDE="${CACHE_DIR}" \
    bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      source '${PROJECT_ROOT}/lib/subscription.sh'
      ${cmd}
    "
}

test_enable_generates_token_and_sets_enabled() {
  local output=''
  output=$(_run_subscription "subscription_enable 2>&1")
  assert_success "jq -e '.subscription.enabled == true' '${STATE_FILE_PATH}' >/dev/null" \
    "subscription.enabled becomes true"
  local token=''
  token=$(jq -r '.subscription.token' "${STATE_FILE_PATH}")
  assert_matches "${token}" '^[a-f0-9]{32}$' "token is 32 hex chars"
  assert_contains "${output}" "http://127.0.0.1:8838/sub/${token}" "url is printed with token"
}

test_url_prints_current_token() {
  local url=''
  url=$(_run_subscription "subscription_url")
  local token=''
  token=$(jq -r '.subscription.token' "${STATE_FILE_PATH}")
  assert_contains "${url}" "${token}" "subscription_url includes current token"
}

test_rotate_changes_token_but_keeps_enabled() {
  local first=''
  first=$(jq -r '.subscription.token' "${STATE_FILE_PATH}")
  _run_subscription "subscription_rotate" >/dev/null
  local second=''
  second=$(jq -r '.subscription.token' "${STATE_FILE_PATH}")
  assert_matches "${second}" '^[a-f0-9]{32}$' "rotated token is 32 hex"
  [[ "${first}" != "${second}" ]] && {
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo "  ✓ rotate changes token"
  } || {
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    FAILED_TESTS+=("rotate did not change token")
    echo "  ✗ rotate changes token"
  }
  assert_success "jq -e '.subscription.enabled == true' '${STATE_FILE_PATH}' >/dev/null" \
    "rotate keeps subscription enabled"
}

test_disable_clears_enabled_and_cache() {
  # Seed a fake cache file so we can verify it gets removed
  echo "stale" >"${CACHE_DIR}/base64"
  echo "stale" >"${CACHE_DIR}/clash.yaml"
  echo "stale" >"${CACHE_DIR}/uri.txt"

  _run_subscription "subscription_disable" >/dev/null
  assert_success "jq -e '.subscription.enabled == false' '${STATE_FILE_PATH}' >/dev/null" \
    "disable sets enabled=false"
  assert_file_not_exists "${CACHE_DIR}/base64" "cache base64 removed"
  assert_file_not_exists "${CACHE_DIR}/clash.yaml" "cache clash.yaml removed"
  assert_file_not_exists "${CACHE_DIR}/uri.txt" "cache uri.txt removed"
}

main() {
  set +e
  setup_fixture
  echo "Running: subscription token lifecycle"
  test_enable_generates_token_and_sets_enabled
  test_url_prints_current_token
  test_rotate_changes_token_but_keeps_enabled
  test_disable_clears_enabled_and_cache
  teardown_fixture
  print_test_summary
}

main "$@"
