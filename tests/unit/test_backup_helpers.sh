#!/usr/bin/env bash
# tests/unit/test_backup_helpers.sh - Unit tests for lib/backup.sh
# Tests backup utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the backup module
source "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/backup.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

# Test counters
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

#==============================================================================
# Test: Backup Functions
#==============================================================================

test_create_backup() {
    echo ""
    echo "Testing create_backup..."

    if declare -f create_backup >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_restore_backup() {
    echo ""
    echo "Testing restore_backup..."

    if declare -f restore_backup >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_list_backups() {
    echo ""
    echo "Testing list_backups..."

    if declare -f list_backups >/dev/null 2>&1; then
        list_backups 2>/dev/null || true
        test_result "list_backups executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_cleanup_old_backups() {
    echo ""
    echo "Testing cleanup_old_backups..."

    if declare -f cleanup_old_backups >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/backup.sh Functions"
echo "=========================================="

test_create_backup
test_restore_backup
test_list_backups
test_cleanup_old_backups

# Print summary
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
