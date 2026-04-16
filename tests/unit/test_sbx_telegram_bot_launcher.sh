#!/usr/bin/env bash
# tests/unit/test_sbx_telegram_bot_launcher.sh - Validate bot launcher entrypoint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

setup_launcher_mock() {
  TEST_TMP_DIR="$(mktemp -d /tmp/sbx-telegram-launcher.XXXXXX)"
  STUB_LIB="${TEST_TMP_DIR}/lib"
  INVOCATION_LOG="${TEST_TMP_DIR}/launcher.log"

  mkdir -p "${STUB_LIB}"
  : >"${INVOCATION_LOG}"

  cat >"${STUB_LIB}/telegram_bot.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
telegram_bot_run() {
  echo "telegram_bot_run" >>"${INVOCATION_LOG}"
}
EOF
}

teardown_launcher_mock() {
  [[ -n "${TEST_TMP_DIR:-}" && -d "${TEST_TMP_DIR}" ]] && rm -rf "${TEST_TMP_DIR}"
}

test_launcher_executes_telegram_bot_run() {
  echo "Testing sbx-telegram-bot launcher..."

  local rc=0
  LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-telegram-bot" >/dev/null 2>&1 || rc=$?

  assert_equals "0" "${rc}" "launcher exits successfully"
  assert_contains "$(cat "${INVOCATION_LOG}")" "telegram_bot_run" \
    "launcher delegates to telegram_bot_run"
}

main() {
  set +e
  run_test_suite \
    "sbx-telegram-bot launcher" \
    setup_launcher_mock \
    test_launcher_executes_telegram_bot_run \
    teardown_launcher_mock
  print_test_summary
}

main "$@"
