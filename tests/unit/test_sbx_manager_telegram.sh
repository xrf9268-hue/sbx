#!/usr/bin/env bash
# tests/unit/test_sbx_manager_telegram.sh - Validate sbx-manager telegram routing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

setup_manager_telegram_mock() {
  TEST_TMP_DIR="$(mktemp -d /tmp/sbx-manager-telegram.XXXXXX)"
  STUB_LIB="${TEST_TMP_DIR}/lib"
  INVOCATION_LOG="${TEST_TMP_DIR}/invocations.log"

  mkdir -p "${STUB_LIB}"
  : >"${INVOCATION_LOG}"

  cat >"${STUB_LIB}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
need_root() { echo "need_root" >>"${INVOCATION_LOG}"; return 0; }
EOF

  cat >"${STUB_LIB}/telegram_bot.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
telegram_bot_setup() { echo "telegram_bot_setup" >>"${INVOCATION_LOG}"; }
telegram_bot_enable() { echo "telegram_bot_enable" >>"${INVOCATION_LOG}"; }
telegram_bot_disable() { echo "telegram_bot_disable" >>"${INVOCATION_LOG}"; }
telegram_bot_status() { echo "telegram_bot_status" >>"${INVOCATION_LOG}"; }
telegram_bot_logs() { echo "telegram_bot_logs" >>"${INVOCATION_LOG}"; }
telegram_bot_admin_add() { echo "telegram_bot_admin_add $*" >>"${INVOCATION_LOG}"; }
telegram_bot_admin_remove() { echo "telegram_bot_admin_remove $*" >>"${INVOCATION_LOG}"; }
telegram_bot_admin_list() { echo "telegram_bot_admin_list" >>"${INVOCATION_LOG}"; }
EOF
}

teardown_manager_telegram_mock() {
  [[ -n "${TEST_TMP_DIR:-}" && -d "${TEST_TMP_DIR}" ]] && rm -rf "${TEST_TMP_DIR}"
}

test_help_lists_telegram_commands() {
  echo "Testing sbx-manager help includes telegram commands..."

  local output=""
  output="$(LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" help 2>&1)"

  assert_contains "${output}" "Telegram Bot" "help output lists Telegram Bot section"
  assert_contains "${output}" "sbx telegram {setup|enable|disable|status|logs|admin ...}" \
    "help output shows telegram usage"
}

test_telegram_status_routes_to_module() {
  echo "Testing sbx-manager telegram status routing..."

  local rc=0
  LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" telegram status >/dev/null 2>&1 || rc=$?

  assert_equals "0" "${rc}" "telegram status exits successfully"
  assert_contains "$(cat "${INVOCATION_LOG}")" "telegram_bot_status" \
    "telegram status dispatches to telegram_bot_status"
}

test_telegram_admin_add_routes_to_module() {
  echo "Testing sbx-manager telegram admin add routing..."

  : >"${INVOCATION_LOG}"
  local rc=0
  LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" telegram admin add 12345 >/dev/null 2>&1 || rc=$?

  assert_equals "0" "${rc}" "telegram admin add exits successfully"
  assert_contains "$(cat "${INVOCATION_LOG}")" "need_root" \
    "telegram admin add enforces need_root"
  assert_contains "$(cat "${INVOCATION_LOG}")" "telegram_bot_admin_add 12345" \
    "telegram admin add dispatches to telegram_bot_admin_add"
}

main() {
  set +e
  run_test_suite \
    "sbx-manager telegram command routing" \
    setup_manager_telegram_mock \
    test_help_lists_telegram_commands \
    test_telegram_status_routes_to_module \
    test_telegram_admin_add_routes_to_module \
    teardown_manager_telegram_mock
  print_test_summary
}

main "$@"
