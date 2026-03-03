#!/usr/bin/env bash
# tests/unit/test_coverage_suite_invocations.sh - Ensure kcov cases run scripts directly

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_SCRIPT="$PROJECT_ROOT/tests/ci/coverage_suite.sh"
CONTENT="$(cat "$SUITE_SCRIPT")"

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

assert_not_contains() {
  local needle="$1"
  local message="$2"
  if [[ "$CONTENT" == *"$needle"* ]]; then
    fail "$message (found: $needle)"
  else
    pass "$message"
  fi
}

main() {
  echo ""
  echo "=========================================="
  echo "Running test suite: coverage invocations"
  echo "=========================================="

  assert_contains 'run_case "reality" "$SCRIPT_DIR/tests/test_reality.sh"' "reality suite runs script directly"
  assert_contains 'run_case "bootstrap" "$SCRIPT_DIR/tests/unit/test_bootstrap_constants.sh"' "bootstrap suite runs script directly"
  assert_contains 'run_unit_cases() {' "unit suite has dedicated per-file runner"
  assert_contains "find \"\$unit_dir\" -maxdepth 1 -type f -name 'test_*.sh'" "unit suite discovers test files directly"
  assert_contains 'run_case "unit-${case_name}" "$unit_script"' "unit suite runs each test file directly"
  assert_not_contains 'run_case "unit" "$SCRIPT_DIR/tests/test-runner.sh" unit' "unit suite no longer wraps test-runner"
  assert_contains 'run_case "integration" "$SCRIPT_DIR/tests/ci/integration_checks.sh"' "integration suite runs script directly"
  assert_contains 'run_case "advanced" "$SCRIPT_DIR/tests/ci/advanced_features_checks.sh"' "advanced suite runs script directly"
  assert_contains 'run_case "docker" "$SCRIPT_DIR/tests/integration/test_docker_lifecycle_smoke.sh"' "docker suite runs script directly"

  assert_not_contains 'run_case "reality" bash ' "reality suite does not wrap with bash"
  assert_not_contains 'run_case "bootstrap" bash ' "bootstrap suite does not wrap with bash"
  assert_not_contains 'run_case "unit" bash ' "unit suite does not wrap with bash"
  assert_not_contains 'run_case "integration" bash ' "integration suite does not wrap with bash"
  assert_not_contains 'run_case "advanced" bash ' "advanced suite does not wrap with bash"
  assert_not_contains 'run_case "docker" bash ' "docker suite does not wrap with bash"

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
