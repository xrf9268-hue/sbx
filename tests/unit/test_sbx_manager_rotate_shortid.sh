#!/usr/bin/env bash
# tests/unit/test_sbx_manager_rotate_shortid.sh - Validate sbx-manager rotate-shortid routing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

setup_manager_rotate_shortid_mock() {
  TEST_TMP_DIR="$(mktemp -d /tmp/sbx-manager-rotate-shortid.XXXXXX)"
  STUB_LIB="${TEST_TMP_DIR}/lib"
  INVOCATION_LOG="${TEST_TMP_DIR}/invocations.log"

  mkdir -p "${STUB_LIB}"
  : >"${INVOCATION_LOG}"

  cat >"${STUB_LIB}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
need_root() { echo "need_root" >>"${INVOCATION_LOG}"; return 0; }
EOF

  cat >"${STUB_LIB}/reality_rotation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
reality_rotate_shortid() { echo "reality_rotate_shortid $*" >>"${INVOCATION_LOG}"; }
reality_rotation_schedule() { echo "reality_rotation_schedule $*" >>"${INVOCATION_LOG}"; }
EOF
}

teardown_manager_rotate_shortid_mock() {
  [[ -n "${TEST_TMP_DIR:-}" && -d "${TEST_TMP_DIR}" ]] && rm -rf "${TEST_TMP_DIR}"
}

test_help_lists_rotate_shortid_commands() {
  echo "Testing sbx-manager help includes rotate-shortid commands..."

  local output=""
  output="$(LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" help 2>&1)"

  assert_contains "${output}" "Reality Rotation" "help output lists Reality Rotation section"
  assert_contains "${output}" "rotate-shortid [--dry-run]" "help output shows rotate-shortid dry-run usage"
  assert_contains "${output}" "rotate-shortid --schedule <daily|weekly|monthly|off>" \
    "help output shows rotate-shortid schedule usage"
}

test_rotate_shortid_dry_run_routes_to_module() {
  echo "Testing sbx-manager rotate-shortid dry-run routing..."

  : >"${INVOCATION_LOG}"
  local rc=0
  LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" rotate-shortid --dry-run >/dev/null 2>&1 || rc=$?

  assert_equals "0" "${rc}" "rotate-shortid --dry-run exits successfully"

  local -a invocation_lines=()
  mapfile -t invocation_lines <"${INVOCATION_LOG}"
  assert_equals "2" "${#invocation_lines[@]}" "rotate-shortid --dry-run logs need_root and module invocation"
  assert_equals "need_root" "${invocation_lines[0]}" "rotate-shortid --dry-run calls need_root first"
  assert_equals "reality_rotate_shortid --dry-run" "${invocation_lines[1]}" \
    "rotate-shortid --dry-run dispatches to reality_rotate_shortid with only module args"
}

test_rotate_shortid_schedule_weekly_routes_to_module() {
  echo "Testing sbx-manager rotate-shortid schedule routing..."

  : >"${INVOCATION_LOG}"
  local rc=0
  LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" rotate-shortid --schedule weekly >/dev/null 2>&1 || rc=$?

  assert_equals "0" "${rc}" "rotate-shortid --schedule weekly exits successfully"

  local -a invocation_lines=()
  mapfile -t invocation_lines <"${INVOCATION_LOG}"
  assert_equals "2" "${#invocation_lines[@]}" "rotate-shortid --schedule weekly logs need_root and schedule invocation"
  assert_equals "need_root" "${invocation_lines[0]}" "rotate-shortid --schedule weekly calls need_root first"
  assert_equals "reality_rotation_schedule weekly" "${invocation_lines[1]}" \
    "rotate-shortid --schedule weekly dispatches to reality_rotation_schedule"
}

test_rotate_shortid_invalid_flag_combination_fails() {
  echo "Testing sbx-manager rotate-shortid invalid flag combination..."

  : >"${INVOCATION_LOG}"
  local rc=0
  local output=""
  output="$(LIB_DIR="${STUB_LIB}" INVOCATION_LOG="${INVOCATION_LOG}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" rotate-shortid --dry-run --schedule weekly 2>&1)" || rc=$?

  assert_equals "1" "${rc}" "rotate-shortid --dry-run --schedule weekly exits non-zero"
  assert_contains "${output}" "--schedule cannot be combined with other flags" \
    "rotate-shortid rejects combined --schedule and --dry-run flags"
  assert_equals "" "$(cat "${INVOCATION_LOG}")" "invalid flag combinations should not reach need_root or modules"
}

main() {
  set +e
  run_test_suite \
    "sbx-manager rotate-shortid help" \
    setup_manager_rotate_shortid_mock \
    test_help_lists_rotate_shortid_commands \
    teardown_manager_rotate_shortid_mock
  run_test_suite \
    "sbx-manager rotate-shortid dry-run" \
    setup_manager_rotate_shortid_mock \
    test_rotate_shortid_dry_run_routes_to_module \
    teardown_manager_rotate_shortid_mock
  run_test_suite \
    "sbx-manager rotate-shortid schedule" \
    setup_manager_rotate_shortid_mock \
    test_rotate_shortid_schedule_weekly_routes_to_module \
    teardown_manager_rotate_shortid_mock
  run_test_suite \
    "sbx-manager rotate-shortid invalid flags" \
    setup_manager_rotate_shortid_mock \
    test_rotate_shortid_invalid_flag_combination_fails \
    teardown_manager_rotate_shortid_mock
  print_test_summary
}

main "$@"
