#!/usr/bin/env bash
# tests/unit/test_sbx_manager_uninstall.sh - Validate sbx-manager uninstall path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

test_uninstall_does_not_reassign_readonly_bootstrap_paths() {
  echo "Testing sbx-manager uninstall source does not reassign readonly bootstrap paths..."

  local matches=""
  matches=$(rg -n '^[[:space:]]+(SB_BIN|SB_CONF_DIR|SB_CONF|SB_SVC|CERT_DIR_BASE)=' \
    "${PROJECT_ROOT}/bin/sbx-manager.sh" 2>/dev/null || true)

  assert_not_contains "${matches}" "1173:" "uninstall must not reassign SB_BIN"
  assert_not_contains "${matches}" "1174:" "uninstall must not reassign SB_CONF_DIR"
  assert_not_contains "${matches}" "1175:" "uninstall must not reassign SB_CONF"
  assert_not_contains "${matches}" "1176:" "uninstall must not reassign SB_SVC"
  assert_not_contains "${matches}" "1177:" "uninstall must not reassign CERT_DIR_BASE"
}

main() {
  set +e
  run_test_suite \
    "sbx-manager uninstall path" \
    true \
    test_uninstall_does_not_reassign_readonly_bootstrap_paths \
    true
  print_test_summary
}

main "$@"
