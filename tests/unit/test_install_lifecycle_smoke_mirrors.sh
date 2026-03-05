#!/usr/bin/env bash
# tests/unit/test_install_lifecycle_smoke_mirrors.sh
# Regression checks for docker smoke mirror fallback definitions.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SMOKE_SCRIPT="${PROJECT_ROOT}/scripts/e2e/install-lifecycle-smoke.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

mirror_block() {
  awk '/^[[:space:]]*mirrors=\(/,/^[[:space:]]*\)/ { print }' "${SMOKE_SCRIPT}"
}

has_https_fallback_mirror() {
  mirror_block | grep -Eq '"https://mirrors\.[^"]+"'
}

has_http_fallback_mirror() {
  mirror_block | grep -Eq '"http://mirrors\.[^"]+"'
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: smoke mirror fallbacks"
  echo "=========================================="

  if has_https_fallback_mirror; then
    pass "smoke mirror fallbacks include HTTPS mirrors"
  else
    fail "smoke mirror fallbacks include HTTPS mirrors"
  fi

  if has_http_fallback_mirror; then
    pass "smoke mirror fallbacks include HTTP mirrors"
  else
    fail "smoke mirror fallbacks include HTTP mirrors"
  fi

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
