#!/usr/bin/env bash
# tests/unit/test_reality_rotation_installation.sh - Validate reality rotation registration in install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

noop() {
  :
}

test_reality_rotation_installation() {
  local install_sh="${PROJECT_ROOT}/install.sh"
  local module_line=''
  local contract_line=''
  local timer_line=''
  local service_line=''
  local helper_call_line=''

  module_line=$(grep -F 'subscription reality_rotation stats' "${install_sh}" || true)
  contract_line=$(grep -F '["reality_rotation"]="reality_rotate_shortid reality_rotation_schedule reality_rotation_remove_units"' "${install_sh}" || true)
  helper_call_line=$(grep -F 'if declare -f reality_rotation_remove_units' "${install_sh}" || true)
  timer_line=$(grep -F 'rm -f "/etc/systemd/system/${ROTATION_TIMER_NAME}"' "${install_sh}" || true)
  service_line=$(grep -F 'rm -f "/etc/systemd/system/${ROTATION_SERVICE_NAME}"' "${install_sh}" || true)

  assert_not_empty "${module_line}" "install.sh module list includes reality_rotation after subscription and before stats"
  assert_not_empty "${contract_line}" "install.sh API contract includes reality_rotation"
  assert_not_empty "${helper_call_line}" "uninstall_flow calls reality_rotation_remove_units when available"
  assert_not_empty "${timer_line}" "install.sh uninstall flow removes sbx-shortid-rotate.timer"
  assert_not_empty "${service_line}" "install.sh uninstall flow removes sbx-shortid-rotate.service"
}

main() {
  set +e
  run_test_suite "reality rotation install registration" noop test_reality_rotation_installation noop
  print_test_summary
}

main "$@"
