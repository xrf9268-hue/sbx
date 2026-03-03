#!/usr/bin/env bash
# tests/unit/test_run_with_kcov_flags.sh - Guard kcov invocation options for shell coverage

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER_SCRIPT="$PROJECT_ROOT/tests/ci/run_with_kcov.sh"
CONTENT="$(cat "$RUNNER_SCRIPT")"

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

assert_contains() {
  local needle="$1"
  local message="$2"
  if [[ "$CONTENT" == *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message (missing: $needle)"
  fi
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: run_with_kcov flags"
  echo "=========================================="

  assert_contains "--bash-method=DEBUG" "uses DEBUG trap bash collection method"
  assert_contains "--include-pattern=" "sets include-pattern for repository scripts"
  assert_contains "install.sh" "includes install.sh in coverage scope"
  assert_contains "lib/" "includes lib directory in coverage scope"
  assert_contains "--exclude-pattern=" "sets exclude-pattern for non-target paths"
  assert_contains "tests/" "excludes test scripts from reported coverage"
  assert_contains "docs/" "excludes docs from reported coverage"
  assert_contains ".git/" "excludes .git from reported coverage"

  echo ""
  echo "=========================================="
  echo "           Test Summary"
  echo "=========================================="
  echo "Total tests:  $TESTS_RUN"
  echo "Passed:       $TESTS_PASSED"
  echo "Failed:       $TESTS_FAILED"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "✓ All tests passed!"
    return 0
  fi

  echo ""
  echo "✗ Some tests failed"
  return 1
}

main "$@"
