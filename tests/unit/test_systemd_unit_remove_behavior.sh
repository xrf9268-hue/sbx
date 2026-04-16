#!/usr/bin/env bash
# tests/unit/test_systemd_unit_remove_behavior.sh
# Verifies strict vs best-effort daemon-reload behavior after unit removal.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
UNIT_PATH=""

setup_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-systemd-remove.XXXXXX)
  UNIT_PATH="${TEST_TMP}/test.service"
  printf '[Unit]\nDescription=test\n' >"${UNIT_PATH}"
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

run_remove_service_with_reload_failure() {
  TEST_UNIT_PATH="${UNIT_PATH}" \
    bash -c "
      export SB_SVC='${UNIT_PATH}'
      export SB_BIN='/bin/true'
      export SB_CONF='${TEST_TMP}/config.json'
      export LOG_VIEW_DEFAULT_HISTORY='1h'
      source '${PROJECT_ROOT}/lib/service.sh'
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      set +e
      systemctl() {
        case \"\$1\" in
          is-active|is-enabled) return 1 ;;
          daemon-reload) return 1 ;;
          *) return 0 ;;
        esac
      }
      remove_service
    "
}

run_subscription_remove_with_reload_failure() {
  TEST_UNIT_PATH="${UNIT_PATH}" \
    bash -c "
      export SB_SVC='${TEST_TMP}/sing-box.service'
      export SB_BIN='/bin/true'
      export SB_CONF='${TEST_TMP}/config.json'
      export LOG_VIEW_DEFAULT_HISTORY='1h'
      source '${PROJECT_ROOT}/lib/subscription.sh'
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      set +e
      _subscription_unit_path() { echo '${UNIT_PATH}'; }
      systemctl() {
        case \"\$1\" in
          is-active|is-enabled) return 1 ;;
          daemon-reload) return 1 ;;
          *) return 0 ;;
        esac
      }
      subscription_remove_unit
    "
}

test_remove_service_fails_when_daemon_reload_fails() {
  local status=0
  run_remove_service_with_reload_failure >/dev/null 2>&1
  status=$?
  assert_equals "1" "${status}" "remove_service surfaces daemon-reload failure"
}

test_subscription_remove_unit_is_best_effort() {
  local status=0
  run_subscription_remove_with_reload_failure >/dev/null 2>&1
  status=$?
  assert_equals "0" "${status}" "subscription_remove_unit tolerates daemon-reload failure"
}

main() {
  set +e
  setup_fixture
  echo "Running: systemd unit remove behavior"
  test_remove_service_fails_when_daemon_reload_fails
  test_subscription_remove_unit_is_best_effort
  teardown_fixture
  print_test_summary
}

main "$@"
