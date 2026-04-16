#!/usr/bin/env bash
# tests/unit/test_systemd_unit_helpers.sh - Guard generic systemd unit helpers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local name="$1"
  local result="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${result}" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${name}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${name}"
  fi
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      missing: ${needle}"
  fi
}

assert_file_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"

  if grep -q "${pattern}" "${file}"; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      missing pattern: ${pattern}"
  fi
}

echo "=== Generic Systemd Unit Helper Tests ==="

echo ""
echo "Testing helper definitions..."
assert_file_contains "install_systemd_unit helper exists" \
  "${PROJECT_ROOT}/lib/service.sh" \
  '^install_systemd_unit()'
assert_file_contains "remove_systemd_unit helper exists" \
  "${PROJECT_ROOT}/lib/service.sh" \
  '^remove_systemd_unit()'

echo ""
echo "Testing service module delegation..."
create_func=$(sed -n '/^create_service_file()/,/^}/p' "${PROJECT_ROOT}/lib/service.sh")
assert_contains "create_service_file delegates to install_systemd_unit" \
  "${create_func}" \
  'install_systemd_unit'

remove_func=$(sed -n '/^remove_service()/,/^}/p' "${PROJECT_ROOT}/lib/service.sh")
assert_contains "remove_service delegates to remove_systemd_unit" \
  "${remove_func}" \
  'remove_systemd_unit'

echo ""
echo "Testing subscription module delegation..."
sub_install_func=$(sed -n '/^subscription_install_unit()/,/^}/p' "${PROJECT_ROOT}/lib/subscription.sh")
assert_contains "subscription_install_unit delegates to install_systemd_unit" \
  "${sub_install_func}" \
  'install_systemd_unit'

sub_remove_func=$(sed -n '/^subscription_remove_unit()/,/^}/p' "${PROJECT_ROOT}/lib/subscription.sh")
assert_contains "subscription_remove_unit delegates to remove_systemd_unit" \
  "${sub_remove_func}" \
  'remove_systemd_unit'

echo ""
echo "Testing uninstall fallback reuse..."
install_snippet=$(awk '
  /if declare -f subscription_remove_unit/ { capture=1 }
  capture { print }
  /rm -f \/usr\/local\/bin\/sbx-sub-server/ { capture=0 }
' "${PROJECT_ROOT}/install.sh")
assert_contains "install.sh uninstall fallback reuses remove_systemd_unit" \
  "${install_snippet}" \
  'remove_systemd_unit'

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total:  ${TESTS_RUN}"
echo "Passed: ${TESTS_PASSED}"
echo "Failed: ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
fi

echo ""
echo "✗ Some tests failed"
exit 1
