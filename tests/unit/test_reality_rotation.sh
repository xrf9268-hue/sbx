#!/usr/bin/env bash
# tests/unit/test_reality_rotation.sh
# Fixture-driven tests for Reality short ID rotation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
FAKE_BIN_DIR=""
STATE_FILE_PATH=""
CONFIG_FILE_PATH=""
CLIENT_INFO_PATH=""
LOCK_FILE_PATH=""
LAST_ROTATION_OUTPUT=""

setup_fixture() {
  LAST_ROTATION_OUTPUT=""
  TEST_TMP=$(mktemp -d /tmp/sbx-reality-rotate.XXXXXX)
  FAKE_BIN_DIR="${TEST_TMP}/bin"
  STATE_FILE_PATH="${TEST_TMP}/state.json"
  CONFIG_FILE_PATH="${TEST_TMP}/config.json"
  CLIENT_INFO_PATH="${TEST_TMP}/client-info.txt"
  LOCK_FILE_PATH="${TEST_TMP}/sbx-state.lock"

  mkdir -p "${FAKE_BIN_DIR}"

  cat >"${FAKE_BIN_DIR}/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "check" && "${2:-}" == "-c" && -n "${3:-}" ]]; then
  jq empty "${3}"
  exit 0
fi

exit 0
EOF
  chmod +x "${FAKE_BIN_DIR}/sing-box"

  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-18T00:00:00Z",
  "mode": "single_protocol",
  "server": {"domain": "example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "public_key": "fixture_public_key",
      "short_id": "abcd1234",
      "sni": "www.microsoft.com",
      "short_id_rotation": {
        "history": []
      }
    }
  },
  "subscription": {
    "enabled": true,
    "port": 8838,
    "bind": "127.0.0.1",
    "token": "deadbeefdeadbeefdeadbeefdeadbeef",
    "path": "/sub",
    "created_at": "2026-04-18T00:00:00Z"
  }
}
EOF

  cat >"${CLIENT_INFO_PATH}" <<'EOF'
UUID="11111111-2222-3333-4444-555555555555"
SHORT_ID="abcd1234"
SNI="www.microsoft.com"
EOF

  cat >"${CONFIG_FILE_PATH}" <<'EOF'
{
  "log": {"level": "warn", "timestamp": true},
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-2222-3333-4444-555555555555",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "private_key": "fixture_private_key",
          "short_id": ["abcd1234"],
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          }
        }
      }
    }
  ],
  "outbounds": [
    {"type": "direct"}
  ]
}
EOF

  chmod 600 "${STATE_FILE_PATH}" "${CLIENT_INFO_PATH}" "${CONFIG_FILE_PATH}"

  export PATH="${FAKE_BIN_DIR}:${PATH}"
  export SBX_TEST_MODE=1
  export SB_BIN="${FAKE_BIN_DIR}/sing-box"
  export TEST_SB_BIN="${FAKE_BIN_DIR}/sing-box"
  export SB_CONF="${CONFIG_FILE_PATH}"
  export SB_CONF_DIR="${TEST_TMP}"
  export CLIENT_INFO="${CLIENT_INFO_PATH}"
  export STATE_FILE="${STATE_FILE_PATH}"
  export TEST_CONFIG_FILE="${CONFIG_FILE_PATH}"
  export TEST_STATE_FILE="${STATE_FILE_PATH}"
  export TEST_CLIENT_INFO="${CLIENT_INFO_PATH}"
  export SBX_STATE_LOCK_FILE="${LOCK_FILE_PATH}"
  export SBX_LOCK_TIMEOUT_SEC=1

  bash -c "
    set -euo pipefail
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/validation.sh'
    source '${PROJECT_ROOT}/lib/service.sh'
    source '${PROJECT_ROOT}/lib/reality_rotation.sh'
    declare -f reality_rotate_shortid >/dev/null
  "
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

current_state_short_id() {
  jq -r '.protocols.reality.short_id' "${STATE_FILE_PATH}"
}

current_client_short_id() {
  grep '^SHORT_ID=' "${CLIENT_INFO_PATH}" | head -1 | cut -d= -f2- | tr -d '"'
}

current_config_short_id() {
  jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.short_id[0]' "${CONFIG_FILE_PATH}"
}

run_rotation() {
  LAST_ROTATION_OUTPUT=$(
    MOCK_RESTART_RESULT="${MOCK_RESTART_RESULT:-0}" bash -c '
      set -euo pipefail
      source "'"${PROJECT_ROOT}"'/lib/common.sh"
      source "'"${PROJECT_ROOT}"'/lib/validation.sh"
      source "'"${PROJECT_ROOT}"'/lib/service.sh"
      source "'"${PROJECT_ROOT}"'/lib/reality_rotation.sh"
      restart_service() {
        if [[ "${MOCK_RESTART_RESULT:-0}" != "0" ]]; then
          return 1
        fi
        return 0
      }
      subscription_refresh_cache() {
        printf "subscription_refresh_cache\n" >>"'"${TEST_TMP}"'/subscription-refresh.log"
      }
      reality_rotate_shortid "$@"
    ' -- "$@"
  )
}

test_manual_rotation_updates_files() {
  local before_state=''
  local before_client=''
  local before_config=''
  local old_sid=''
  old_sid=$(current_state_short_id)
  before_state=$(cat "${STATE_FILE_PATH}")
  before_client=$(cat "${CLIENT_INFO_PATH}")
  before_config=$(cat "${CONFIG_FILE_PATH}")

  run_rotation

  local new_sid=''
  new_sid=$(current_state_short_id)

  assert_matches "${new_sid}" '^[0-9a-f]{8}$' "rotation writes an 8-char hex short ID"
  assert_not_contains "${new_sid}" "${old_sid}" "rotation picks a different short ID"
  assert_equals "${new_sid}" "$(current_client_short_id)" "client-info.txt short ID updated"
  assert_equals "${new_sid}" "$(current_config_short_id)" "config.json Reality inbound short ID updated"
  assert_equals "${new_sid}" "$(jq -r '.protocols.reality.short_id_rotation.current_short_id' "${STATE_FILE_PATH}")" \
    "state.json rotation metadata records the new short ID"
  assert_equals "${old_sid}" "$(jq -r '.protocols.reality.short_id_rotation.previous_short_id' "${STATE_FILE_PATH}")" \
    "state.json rotation metadata records the previous short ID"
  assert_file_exists "${TEST_TMP}/subscription-refresh.log" "subscription cache refresh is triggered when enabled"
  assert_contains "$(cat "${TEST_TMP}/subscription-refresh.log")" "subscription_refresh_cache" \
    "subscription cache refresh is triggered when enabled"
  assert_not_contains "$(cat "${STATE_FILE_PATH}")" "${before_state}" "state.json changed"
  assert_not_contains "$(cat "${CLIENT_INFO_PATH}")" "${before_client}" "client-info.txt changed"
  assert_not_contains "$(cat "${CONFIG_FILE_PATH}")" "${before_config}" "config.json changed"
}

test_dry_run_leaves_files_untouched() {
  local before_state=''
  local before_client=''
  local before_config=''
  before_state=$(cat "${STATE_FILE_PATH}")
  before_client=$(cat "${CLIENT_INFO_PATH}")
  before_config=$(cat "${CONFIG_FILE_PATH}")

  run_rotation --dry-run

  assert_equals "${before_state}" "$(cat "${STATE_FILE_PATH}")" "dry-run leaves state.json untouched"
  assert_equals "${before_client}" "$(cat "${CLIENT_INFO_PATH}")" "dry-run leaves client-info.txt untouched"
  assert_equals "${before_config}" "$(cat "${CONFIG_FILE_PATH}")" "dry-run leaves config.json untouched"
  assert_file_not_exists "${TEST_TMP}/subscription-refresh.log" "dry-run does not refresh subscription cache"
  assert_equals "abcd1234" "$(current_state_short_id)" "dry-run preserves original state short ID"
  assert_equals "abcd1234" "$(current_client_short_id)" "dry-run preserves original client short ID"
  assert_equals "abcd1234" "$(current_config_short_id)" "dry-run preserves original config short ID"
}

test_restart_failure_rolls_back_files() {
  local before_state=''
  local before_client=''
  local before_config=''
  before_state=$(cat "${STATE_FILE_PATH}")
  before_client=$(cat "${CLIENT_INFO_PATH}")
  before_config=$(cat "${CONFIG_FILE_PATH}")

  MOCK_RESTART_RESULT=1 run_rotation

  assert_equals "${before_state}" "$(cat "${STATE_FILE_PATH}")" "restart failure rolls back state.json"
  assert_equals "${before_client}" "$(cat "${CLIENT_INFO_PATH}")" "restart failure rolls back client-info.txt"
  assert_equals "${before_config}" "$(cat "${CONFIG_FILE_PATH}")" "restart failure rolls back config.json"
  assert_file_not_exists "${TEST_TMP}/subscription-refresh.log" "rollback path skips subscription cache refresh"
  assert_equals "abcd1234" "$(current_state_short_id)" "rollback restores original state short ID"
  assert_equals "abcd1234" "$(current_client_short_id)" "rollback restores original client short ID"
  assert_equals "abcd1234" "$(current_config_short_id)" "rollback restores original config short ID"
}

main() {
  set +e
  echo "Running: reality rotation"
  setup_fixture
  test_manual_rotation_updates_files
  teardown_fixture
  setup_fixture
  test_dry_run_leaves_files_untouched
  teardown_fixture
  setup_fixture
  test_restart_failure_rolls_back_files
  teardown_fixture
  print_test_summary
}

main "$@"
