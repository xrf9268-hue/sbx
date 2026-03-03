#!/usr/bin/env bash
# tests/unit/test_ci_workflows.sh - Validate CI workflow guardrails
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  ✓ $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  ✗ $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message (missing: $needle)"
  fi
}

extract_block() {
  local file="$1"
  local start="$2"
  local end="$3"

  awk -v start="$start" -v end="$end" '
    $0 ~ start { in_block=1; next }
    $0 ~ end && in_block { in_block=0; exit }
    in_block { print }
  ' "$file"
}

main() {
  local test_workflow="$PROJECT_ROOT/.github/workflows/test.yml"
  local shellcheck_workflow="$PROJECT_ROOT/.github/workflows/shellcheck.yml"

  echo "=== CI Workflow Policy Validation ==="

  local push_block
  push_block="$(extract_block "$test_workflow" '^  push:$' '^  pull_request:$')"

  local pr_block
  pr_block="$(extract_block "$test_workflow" '^  pull_request:$' '^# Cancel in-progress runs')"

  assert_contains "$push_block" 'paths-ignore:' 'test.yml push trigger defines paths-ignore'
  assert_contains "$push_block" "'docs/**'" 'test.yml push ignores docs changes'
  assert_contains "$push_block" "'**/*.md'" 'test.yml push ignores markdown changes'
  assert_contains "$push_block" "'LICENSE*'" 'test.yml push ignores LICENSE changes'

  assert_contains "$pr_block" 'paths-ignore:' 'test.yml pull_request trigger defines paths-ignore'
  assert_contains "$pr_block" "'docs/**'" 'test.yml pull_request ignores docs changes'
  assert_contains "$pr_block" "'**/*.md'" 'test.yml pull_request ignores markdown changes'
  assert_contains "$pr_block" "'LICENSE*'" 'test.yml pull_request ignores LICENSE changes'

  local shellcheck_content
  shellcheck_content="$(cat "$shellcheck_workflow")"

  assert_contains "$shellcheck_content" 'format-check:' 'shellcheck.yml includes format-check job'
  assert_contains "$shellcheck_content" 'SHFMT_VERSION: "v3.12.0"' 'format-check pins shfmt version'
  assert_contains "$shellcheck_content" 'SHFMT_SHA256: "d9fbb2a9c33d13f47e7618cf362a914d029d02a6df124064fff04fd688a745ea"' 'format-check pins shfmt checksum'
  assert_contains "$shellcheck_content" 'sha256sum -c /tmp/shfmt.sha256' 'format-check verifies shfmt checksum'
  assert_contains "$shellcheck_content" 'git diff --name-only' 'format-check scopes to changed files'
  assert_contains "$shellcheck_content" 'No changed shell scripts to format-check.' 'format-check skips when no shell files changed'
  assert_contains "$shellcheck_content" 'shfmt -i 2 -ci -d' 'format-check uses repository shfmt style options'
  assert_contains "$shellcheck_content" '-d "${scripts[@]}"' 'format-check enforces diff-based style validation'

  echo ""
  echo "=== Summary ==="
  echo "  Tests run:    $TESTS_RUN"
  echo "  Tests passed: $TESTS_PASSED"
  echo "  Tests failed: $TESTS_FAILED"

  if [[ $TESTS_FAILED -ne 0 ]]; then
    exit 1
  fi
}

main
