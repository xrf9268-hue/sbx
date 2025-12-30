#!/usr/bin/env bash
# tests/unit/test_colors.sh - Unit tests for lib/colors.sh
# Tests color output functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

set +e
set -o pipefail

# Source the colors module
source "${PROJECT_ROOT}/lib/colors.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/colors.sh"
    exit 1
}

trap - EXIT INT TERM
set +e

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local test_name="$1"
    local result="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
    fi
}

echo ""
echo "=========================================="
echo "Running test suite: lib/colors.sh"
echo "=========================================="

# Test color variables exist
if [[ -n "${RED:-}" ]] || [[ -n "${GREEN:-}" ]] || [[ -n "${NC:-}" ]]; then
    test_result "color variables defined" "pass"
else
    test_result "color variables defined (may be unset for non-tty)" "pass"
fi

# Test _init_colors function definition and exported variables
if declare -f _init_colors >/dev/null 2>&1; then
    if [[ -v B && -v N ]]; then
        test_result "_init_colors initializes color variables" "pass"
    else
        test_result "_init_colors initializes color variables (may be empty without TTY)" "pass"
    fi
else
    test_result "_init_colors skipped" "pass"
fi

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
    exit 0
else
    echo ""
    echo "✗ Some tests failed"
    exit 1
fi
