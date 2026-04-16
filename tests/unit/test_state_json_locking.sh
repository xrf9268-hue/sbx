#!/usr/bin/env bash
# tests/unit/test_state_json_locking.sh
# Verifies the shared state.json write helper and that current writers use it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
STATE_FILE_PATH=""

setup_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-state-locking.XXXXXX)
  STATE_FILE_PATH="${TEST_TMP}/state.json"
  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "subscription": {
    "enabled": false,
    "port": 8838,
    "bind": "127.0.0.1",
    "token": "",
    "path": "/sub",
    "created_at": null
  },
  "protocols": {
    "hysteria2": {
      "enabled": true,
      "port": 8443,
      "port_range": null
    },
    "reality": {
      "users": [],
      "uuid": "legacy-uuid"
    }
  },
  "telegram": {
    "enabled": false,
    "username": "",
    "admin_chat_ids": []
  },
  "tunnel": {
    "enabled": false,
    "mode": null,
    "hostname": null,
    "upstream_port": null
  }
}
EOF
  chmod 600 "${STATE_FILE_PATH}"
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

test_state_json_apply_updates_fixture() {
  TEST_STATE_FILE="${STATE_FILE_PATH}" \
    bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      state_json_apply '${STATE_FILE_PATH}' '.subscription.enabled = true'
    "

  assert_success "jq -e '.subscription.enabled == true' '${STATE_FILE_PATH}' >/dev/null" \
    "state_json_apply updates the target file"
  local perm=''
  perm=$(stat -c '%a' "${STATE_FILE_PATH}" 2>/dev/null || stat -f '%Lp' "${STATE_FILE_PATH}" 2>/dev/null)
  assert_equals "600" "${perm}" "state_json_apply preserves secure permissions"
}

test_common_exports_state_locking_helpers() {
  local common_funcs=''
  common_funcs=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    declare -f with_state_lock
    printf '\\n--FUNC--\\n'
    declare -f state_json_apply
  ")

  assert_contains "${common_funcs}" "with_state_lock (" "with_state_lock helper exists"
  assert_contains "${common_funcs}" "sbx-state.lock" "state lock file is dedicated"
  assert_contains "${common_funcs}" "state_json_apply (" "state_json_apply helper exists"
}

test_state_writers_use_shared_helper() {
  local subscription_funcs=''
  subscription_funcs=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/subscription.sh'
    declare -f _subscription_state_set
    printf '\\n--FUNC--\\n'
    declare -f subscription_ensure_state_block
  ")
  assert_contains "${subscription_funcs}" "state_json_apply" \
    "subscription writers use shared state helper"

  local telegram_func=''
  telegram_func=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/telegram_bot.sh'
    declare -f _tg_update_state
  ")
  assert_contains "${telegram_func}" "state_json_apply" \
    "telegram writer uses shared state helper"

  local tunnel_func=''
  tunnel_func=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/cloudflare_tunnel.sh'
    declare -f cloudflared_update_state
  ")
  assert_contains "${tunnel_func}" "state_json_apply" \
    "tunnel writer uses shared state helper"

  local users_func=''
  users_func=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/users.sh'
    declare -f _save_users_locked
  ")
  assert_contains "${users_func}" "state_json_apply_locked" \
    "users writer uses shared state helper"

  assert_success "grep -q 'state_json_apply' '${PROJECT_ROOT}/bin/sbx-manager.sh'" \
    "sbx-manager uses shared state helper"
  assert_success "grep -Eq 'with_state_lock|state_json_apply' '${PROJECT_ROOT}/install.sh'" \
    "install state write uses state lock"
}

test_state_mutations_avoid_stale_pre_reads() {
  local user_mutators=''
  user_mutators=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/users.sh'
    declare -f user_add
    printf '\\n--FUNC--\\n'
    declare -f user_remove
    printf '\\n--FUNC--\\n'
    declare -f user_reset
  ")
  assert_not_contains "${user_mutators}" "_load_users" \
    "user mutators do not snapshot users outside the lock"

  local telegram_admin_mutators=''
  telegram_admin_mutators=$(bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    source '${PROJECT_ROOT}/lib/telegram_bot.sh'
    declare -f telegram_bot_admin_add
    printf '\\n--FUNC--\\n'
    declare -f telegram_bot_admin_remove
  ")
  assert_not_contains "${telegram_admin_mutators}" 'admins_json=$(jq -c' \
    "telegram admin mutators do not precompute admin arrays outside the lock"
}

main() {
  set +e
  setup_fixture
  echo "Running: state.json locking"
  test_state_json_apply_updates_fixture
  test_common_exports_state_locking_helpers
  test_state_writers_use_shared_helper
  test_state_mutations_avoid_stale_pre_reads
  teardown_fixture
  print_test_summary
}

main "$@"
