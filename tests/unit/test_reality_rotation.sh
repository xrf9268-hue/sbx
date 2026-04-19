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
SYSTEMD_DIR_PATH=""
LOCK_FILE_PATH=""
LAST_ROTATION_OUTPUT=""
LAST_SCHEDULE_OUTPUT=""
ROTATION_SERVICE_UNIT_NAME="sbx-shortid-rotate.service"
ROTATION_TIMER_UNIT_NAME="sbx-shortid-rotate.timer"

setup_fixture() {
  LAST_ROTATION_OUTPUT=""
  TEST_TMP=$(mktemp -d /tmp/sbx-reality-rotate.XXXXXX)
  FAKE_BIN_DIR="${TEST_TMP}/bin"
  STATE_FILE_PATH="${TEST_TMP}/state.json"
  CONFIG_FILE_PATH="${TEST_TMP}/config.json"
  CLIENT_INFO_PATH="${TEST_TMP}/client-info.txt"
  SYSTEMD_DIR_PATH="${TEST_TMP}/systemd"
  LOCK_FILE_PATH="${TEST_TMP}/sbx-state.lock"

  mkdir -p "${FAKE_BIN_DIR}"
  mkdir -p "${SYSTEMD_DIR_PATH}"

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
  export TEST_SYSTEMD_DIR="${SYSTEMD_DIR_PATH}"
  export SBX_SYSTEMD_DIR="${SYSTEMD_DIR_PATH}"
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

rotation_service_unit_path() {
  printf '%s/%s\n' "${SYSTEMD_DIR_PATH}" "${ROTATION_SERVICE_UNIT_NAME}"
}

rotation_timer_unit_path() {
  printf '%s/%s\n' "${SYSTEMD_DIR_PATH}" "${ROTATION_TIMER_UNIT_NAME}"
}

seed_rotation_history() {
  local count="$1"
  local history_json='[]'
  local i=1
  local second=''

  while [[ "${i}" -le "${count}" ]]; do
    printf -v second '%02d' "${i}"
    history_json=$(
      jq -c \
        --arg short_id "seed-${i}" \
        --arg rotated_at "2026-04-18T00:00:${second}Z" \
        --arg trigger "manual" \
        '. + [{short_id: $short_id, rotated_at: $rotated_at, trigger: $trigger}]' \
        <<<"${history_json}"
    )
    i=$((i + 1))
  done

  jq --argjson history "${history_json}" \
    '.protocols.reality.short_id_rotation.history = $history' \
    "${STATE_FILE_PATH}" >"${STATE_FILE_PATH}.tmp"
  mv -f "${STATE_FILE_PATH}.tmp" "${STATE_FILE_PATH}"
}

run_rotation() {
  LAST_ROTATION_OUTPUT=$(
    TEST_CONFIG_FILE="${TEST_CONFIG_FILE:-}" MOCK_RESTART_RESULT="${MOCK_RESTART_RESULT:-0}" MOCK_RESTART_STYLE="${MOCK_RESTART_STYLE:-return}" bash -c '
      set -euo pipefail
      source "'"${PROJECT_ROOT}"'/lib/common.sh"
      source "'"${PROJECT_ROOT}"'/lib/validation.sh"
      source "'"${PROJECT_ROOT}"'/lib/service.sh"
      source "'"${PROJECT_ROOT}"'/lib/reality_rotation.sh"
      restart_attempts_file="'"${TEST_TMP}"'/restart-attempts.log"
      restart_invocations_file="'"${TEST_TMP}"'/restart-invocations.count"
      restart_config_file="${TEST_CONFIG_FILE:-${SB_CONF}}"
      restart_service() {
        local attempt=0
        if [[ -f "${restart_invocations_file}" ]]; then
          attempt=$(cat "${restart_invocations_file}")
        fi
        attempt=$((attempt + 1))
        printf "%s\n" "${attempt}" >"${restart_invocations_file}"
        jq -r ".inbounds[] | select(.tls.reality) | .tls.reality.short_id[0]" "${restart_config_file}" >>"${restart_attempts_file}"
        if [[ "${MOCK_RESTART_STYLE:-return}" == "exit" ]]; then
          if [[ "${attempt}" -eq 1 ]]; then
            exit 17
          fi
          return 0
        fi
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

run_schedule() {
  LAST_SCHEDULE_OUTPUT=$(
    bash -c '
      set -euo pipefail
      source "'"${PROJECT_ROOT}"'/lib/common.sh"
      source "'"${PROJECT_ROOT}"'/lib/validation.sh"
      source "'"${PROJECT_ROOT}"'/lib/service.sh"
      source "'"${PROJECT_ROOT}"'/lib/reality_rotation.sh"
      systemctl() {
        printf "systemctl %s\n" "$*" >>"'"${TEST_TMP}"'/systemctl.log"
        if [[ "${SYSTEMCTL_FAIL_ENABLE_NOW:-0}" == "1" && "${1:-}" == "enable" && "${2:-}" == "--now" ]]; then
          return 1
        fi
        return 0
      }
      install_systemd_unit() {
        local unit_path="$1"
        local unit_content="${2:-}"
        printf "install_systemd_unit %s\n" "${unit_path}" >>"'"${TEST_TMP}"'/systemd.log"
        printf "%s\n" "${unit_content}" >"${unit_path}"
        chmod 644 "${unit_path}"
      }
      remove_systemd_unit() {
        local unit_name="$1"
        local unit_path="${2:-}"
        printf "remove_systemd_unit %s %s\n" "${unit_name}" "${unit_path}" >>"'"${TEST_TMP}"'/systemd.log"
        rm -f "${unit_path}"
      }
      reality_rotation_schedule "$@"
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
  assert_equals "manual" "$(jq -r '.protocols.reality.short_id_rotation.trigger' "${STATE_FILE_PATH}")" \
    "manual rotations are labeled manual"
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

test_restart_failure_with_exit_rolls_back_and_restarts_restored_config() {
  local before_state=''
  local before_client=''
  local before_config=''
  before_state=$(cat "${STATE_FILE_PATH}")
  before_client=$(cat "${CLIENT_INFO_PATH}")
  before_config=$(cat "${CONFIG_FILE_PATH}")

  MOCK_RESTART_STYLE=exit assert_failure "run_rotation" "non-returning restart failure still triggers rollback"

  assert_equals "${before_state}" "$(cat "${STATE_FILE_PATH}")" "non-returning restart failure rolls back state.json"
  assert_equals "${before_client}" "$(cat "${CLIENT_INFO_PATH}")" "non-returning restart failure rolls back client-info.txt"
  assert_equals "${before_config}" "$(cat "${CONFIG_FILE_PATH}")" "non-returning restart failure rolls back config.json"
  assert_file_exists "${TEST_TMP}/restart-attempts.log" "restart attempts are logged"
  assert_equals "2" "$(wc -l <"${TEST_TMP}/restart-attempts.log" | tr -d '[:space:]')" \
    "rotation retries restart after restoring backups"
  assert_matches "$(sed -n '1p' "${TEST_TMP}/restart-attempts.log")" '^[0-9a-f]{8}$' \
    "first restart saw a rotated short ID"
  assert_not_contains "$(sed -n '1p' "${TEST_TMP}/restart-attempts.log")" "abcd1234" \
    "first restart did not see the original short ID"
  assert_equals "abcd1234" "$(sed -n '2p' "${TEST_TMP}/restart-attempts.log")" \
    "second restart saw restored config"
  assert_file_not_exists "${TEST_TMP}/subscription-refresh.log" "failed rotation does not refresh subscription cache"
  assert_equals "abcd1234" "$(current_state_short_id)" "non-returning restart failure restores original state short ID"
}

test_scheduled_run_records_timer_trigger() {
  run_rotation --scheduled-run

  assert_equals "timer" "$(jq -r '.protocols.reality.short_id_rotation.trigger' "${STATE_FILE_PATH}")" \
    "scheduled rotations are labeled timer"
  assert_equals "timer" "$(jq -r '.protocols.reality.short_id_rotation.history[0].trigger' "${STATE_FILE_PATH}")" \
    "rotation history records timer trigger"
}

test_reality_rotation_schedule_weekly_installs_units_and_updates_state() {
  run_schedule weekly

  assert_equals "weekly" "$(jq -r '.protocols.reality.short_id_rotation.schedule' "${STATE_FILE_PATH}")" \
    "state.json records weekly schedule"
  assert_equals "true" "$(jq -r '.protocols.reality.short_id_rotation.enabled' "${STATE_FILE_PATH}")" \
    "state.json records enabled schedule"
  assert_equals "weekly" "$(jq -r '.protocols.reality.short_id_rotation.on_calendar' "${STATE_FILE_PATH}")" \
    "state.json records weekly on-calendar"
  assert_file_exists "$(rotation_service_unit_path)" "service unit is rendered"
  assert_file_exists "$(rotation_timer_unit_path)" "timer unit is rendered"
  assert_contains "$(cat "$(rotation_timer_unit_path)")" "OnCalendar=weekly" \
    "timer unit contains weekly OnCalendar"
  assert_contains "$(cat "$(rotation_timer_unit_path)")" "Persistent=true" \
    "timer unit contains Persistent=true"
}

test_reality_rotation_schedule_off_removes_units_and_disables_state() {
  local before_log_lines=0
  local after_log_lines=0
  local after_off_log=''

  run_schedule weekly

  assert_file_exists "$(rotation_service_unit_path)" "precondition: service unit exists before disabling"
  assert_file_exists "$(rotation_timer_unit_path)" "precondition: timer unit exists before disabling"
  before_log_lines=$(wc -l <"${TEST_TMP}/systemd.log" | tr -d '[:space:]')

  run_schedule off
  after_log_lines=$(wc -l <"${TEST_TMP}/systemd.log" | tr -d '[:space:]')
  after_off_log=$(sed -n "$((before_log_lines + 1)),${after_log_lines}p" "${TEST_TMP}/systemd.log")

  assert_equals "off" "$(jq -r '.protocols.reality.short_id_rotation.schedule' "${STATE_FILE_PATH}")" \
    "state.json records off schedule"
  assert_equals "false" "$(jq -r '.protocols.reality.short_id_rotation.enabled' "${STATE_FILE_PATH}")" \
    "state.json records disabled schedule"
  assert_equals "null" "$(jq -r '.protocols.reality.short_id_rotation.on_calendar' "${STATE_FILE_PATH}")" \
    "state.json clears on-calendar when disabled"
  assert_file_exists "${TEST_TMP}/systemd.log" "off schedule logs unit removal"
  assert_not_contains "${after_off_log}" "install_systemd_unit" \
    "off schedule does not render units"
  assert_contains "${after_off_log}" "remove_systemd_unit" \
    "off schedule exercises unit removal"
  assert_file_not_exists "$(rotation_service_unit_path)" "service unit is removed"
  assert_file_not_exists "$(rotation_timer_unit_path)" "timer unit is removed"
}

test_invalid_schedule_leaves_state_and_units_untouched() {
  local before_state=''
  local before_service=''
  local before_timer=''

  run_schedule weekly
  before_state=$(cat "${STATE_FILE_PATH}")
  before_service=$(cat "$(rotation_service_unit_path)")
  before_timer=$(cat "$(rotation_timer_unit_path)")

  assert_failure "run_schedule hourly" "invalid schedule should fail"

  assert_equals "${before_state}" "$(cat "${STATE_FILE_PATH}")" "invalid schedule leaves state.json untouched"
  assert_equals "${before_service}" "$(cat "$(rotation_service_unit_path)")" "invalid schedule leaves service unit untouched"
  assert_equals "${before_timer}" "$(cat "$(rotation_timer_unit_path)")" "invalid schedule leaves timer unit untouched"
}

test_schedule_enable_failure_rolls_back_state_and_units() {
  local before_state=''

  before_state=$(cat "${STATE_FILE_PATH}")

  SYSTEMCTL_FAIL_ENABLE_NOW=1 assert_failure "run_schedule weekly" "failed timer activation should fail"

  assert_equals "${before_state}" "$(cat "${STATE_FILE_PATH}")" "failed activation leaves state.json untouched"
  assert_equals "[]" "$(jq -c '.protocols.reality.short_id_rotation.history' "${STATE_FILE_PATH}")" \
    "failed activation keeps history unchanged"
  assert_file_not_exists "$(rotation_service_unit_path)" "failed activation rolls back service unit"
  assert_file_not_exists "$(rotation_timer_unit_path)" "failed activation rolls back timer unit"
  assert_contains "$(cat "${TEST_TMP}/systemd.log")" "remove_systemd_unit" \
    "failed activation exercises rollback removal"
}

test_history_trimming_keeps_twenty_entries() {
  local history_count=''

  seed_rotation_history 25
  run_rotation

  history_count=$(jq '.protocols.reality.short_id_rotation.history | length' "${STATE_FILE_PATH}")
  assert_equals "20" "${history_count}" "rotation history is trimmed to 20 entries"
  assert_equals "abcd1234" "$(jq -r '.protocols.reality.short_id_rotation.history[0].short_id' "${STATE_FILE_PATH}")" \
    "newest history entry stays first"
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
  setup_fixture
  test_restart_failure_with_exit_rolls_back_and_restarts_restored_config
  teardown_fixture
  setup_fixture
  test_scheduled_run_records_timer_trigger
  teardown_fixture
  setup_fixture
  test_reality_rotation_schedule_weekly_installs_units_and_updates_state
  teardown_fixture
  setup_fixture
  test_reality_rotation_schedule_off_removes_units_and_disables_state
  teardown_fixture
  setup_fixture
  test_invalid_schedule_leaves_state_and_units_untouched
  teardown_fixture
  setup_fixture
  test_schedule_enable_failure_rolls_back_state_and_units
  teardown_fixture
  setup_fixture
  test_history_trimming_keeps_twenty_entries
  teardown_fixture
  print_test_summary
}

main "$@"
