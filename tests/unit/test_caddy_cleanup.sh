#!/usr/bin/env bash
# tests/unit/test_caddy_cleanup.sh - Unit tests for lib/caddy_cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MODULE_PATH="${PROJECT_ROOT}/lib/caddy_cleanup.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TMP_DIR=""
MOCK_BIN=""
CALL_LOG=""
ORIGINAL_PATH="${PATH}"

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  ✓ $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  ✗ $1"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local name="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    pass "${name}"
  else
    fail "${name} (expected: ${expected}, got: ${actual})"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local name="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${name}"
  else
    fail "${name} (missing: ${needle})"
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local name="$3"
  if grep -Fq "${needle}" "${file}"; then
    pass "${name}"
  else
    fail "${name} (missing: ${needle})"
  fi
}

create_mock_scripts() {
  cat >"${MOCK_BIN}/getent" <<'EOF_GETENT'
#!/usr/bin/env bash
set -euo pipefail
echo "getent $*" >> "${CALL_LOG:?}"

if [[ "${MOCK_GETENT_MODE:-default}" == "empty" ]]; then
  exit 0
fi

if [[ "${1:-}" == "passwd" && "${2:-}" == "root" ]]; then
  printf '%s\n' "${MOCK_GETENT_OUTPUT:-root:x:0:0:root:/root:/bin/bash}"
fi
EOF_GETENT

  cat >"${MOCK_BIN}/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
echo "systemctl $*" >> "${CALL_LOG:?}"

if [[ "${MOCK_SYSTEMCTL_FAIL_NON_RELOAD:-0}" == "1" && "${1:-}" != "daemon-reload" ]]; then
  exit 1
fi
exit 0
EOF_SYSTEMCTL

  cat >"${MOCK_BIN}/rm" <<'EOF_RM'
#!/usr/bin/env bash
set -euo pipefail
echo "rm $*" >> "${CALL_LOG:?}"
exit 0
EOF_RM

  chmod +x "${MOCK_BIN}/getent" "${MOCK_BIN}/systemctl" "${MOCK_BIN}/rm"
}

setup() {
  TMP_DIR="$(mktemp -d)"
  MOCK_BIN="${TMP_DIR}/mock-bin"
  CALL_LOG="${TMP_DIR}/calls.log"
  mkdir -p "${MOCK_BIN}"
  : >"${CALL_LOG}"
  export CALL_LOG

  create_mock_scripts

  export PATH="${MOCK_BIN}:${ORIGINAL_PATH}"

  # shellcheck source=/dev/null
  source "${MODULE_PATH}"
  trap - EXIT INT TERM

  # Deterministic logging output for assertions.
  msg() { echo "$*"; }
  warn() { echo "$*"; }
  success() { echo "$*"; }
}

teardown() {
  PATH="${ORIGINAL_PATH}"
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    /bin/rm -rf "${TMP_DIR}"
  fi
}

test_caddy_data_dir_uses_getent_home() {
  echo ""
  echo "Testing _caddy_data_dir uses home from getent..."

  : >"${CALL_LOG}"
  export MOCK_GETENT_MODE="default"
  export MOCK_GETENT_OUTPUT="root:x:0:0:root:/srv/caddy-root:/bin/bash"

  local data_dir
  data_dir="$(_caddy_data_dir)"

  assert_equals "/srv/caddy-root/.local/share/caddy" "${data_dir}" "getent home directory is used"
  assert_file_contains "${CALL_LOG}" "getent passwd root" "queries root account with getent"
}

test_caddy_data_dir_falls_back_to_root() {
  echo ""
  echo "Testing _caddy_data_dir fallback path..."

  : >"${CALL_LOG}"
  export MOCK_GETENT_MODE="empty"
  unset MOCK_GETENT_OUTPUT || true

  local data_dir
  data_dir="$(_caddy_data_dir)"

  assert_equals "/root/.local/share/caddy" "${data_dir}" "falls back to /root when getent has no home"
}

test_caddy_uninstall_runs_cleanup_sequence() {
  echo ""
  echo "Testing caddy_uninstall cleanup sequence..."

  : >"${CALL_LOG}"
  export MOCK_GETENT_MODE="default"
  export MOCK_GETENT_OUTPUT="root:x:0:0:root:/srv/caddy-root:/bin/bash"
  export MOCK_SYSTEMCTL_FAIL_NON_RELOAD="0"

  local output
  local status
  set +e
  output="$(caddy_uninstall 2>&1)"
  status=$?
  set -e

  assert_equals "0" "${status}" "caddy_uninstall returns success"
  assert_file_contains "${CALL_LOG}" "systemctl stop caddy" "stops caddy service"
  assert_file_contains "${CALL_LOG}" "systemctl disable caddy" "disables caddy service"
  assert_file_contains "${CALL_LOG}" "systemctl stop caddy-cert-sync.timer" "stops cert sync timer"
  assert_file_contains "${CALL_LOG}" "systemctl disable caddy-cert-sync.timer" "disables cert sync timer"
  assert_file_contains "${CALL_LOG}" "rm -f /usr/local/bin/caddy" "removes caddy binary"
  assert_file_contains "${CALL_LOG}" "rm -f /etc/systemd/system/caddy.service" "removes caddy service file"
  assert_file_contains "${CALL_LOG}" "rm -rf /usr/local/etc/caddy" "removes caddy config directory"
  assert_file_contains "${CALL_LOG}" "systemctl daemon-reload" "reloads systemd after cleanup"
  assert_contains "${output}" "Certificate data preserved in: /srv/caddy-root/.local/share/caddy" "prints preserved cert data path"
  assert_contains "${output}" "Remove manually if needed: rm -rf /srv/caddy-root/.local/share/caddy" "prints manual removal guidance"
}

test_caddy_uninstall_tolerates_noncritical_systemctl_failures() {
  echo ""
  echo "Testing caddy_uninstall tolerates stop/disable failures..."

  : >"${CALL_LOG}"
  export MOCK_GETENT_MODE="default"
  export MOCK_GETENT_OUTPUT="root:x:0:0:root:/root:/bin/bash"
  export MOCK_SYSTEMCTL_FAIL_NON_RELOAD="1"

  local status
  set +e
  caddy_uninstall >/dev/null 2>&1
  status=$?
  set -e

  assert_equals "0" "${status}" "caddy_uninstall ignores stop/disable failures"
  assert_file_contains "${CALL_LOG}" "systemctl daemon-reload" "still performs daemon-reload"
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: caddy cleanup module"
  echo "=========================================="

  setup
  trap 'teardown' EXIT INT TERM

  test_caddy_data_dir_uses_getent_home
  test_caddy_data_dir_falls_back_to_root
  test_caddy_uninstall_runs_cleanup_sequence
  test_caddy_uninstall_tolerates_noncritical_systemctl_failures

  echo ""
  echo "=========================================="
  echo "           Test Summary"
  echo "=========================================="
  echo "Total tests:  ${TESTS_RUN}"
  echo "Passed:       ${TESTS_PASSED}"
  echo "Failed:       ${TESTS_FAILED}"

  if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo ""
    echo "✓ All tests passed!"
    return 0
  fi

  echo ""
  echo "✗ Some tests failed"
  return 1
}

main "$@"
