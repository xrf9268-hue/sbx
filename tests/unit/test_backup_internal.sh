#!/usr/bin/env bash
# Unit tests for backup module functions
# Tests: _decrypt_backup, _validate_backup_archive, _prepare_rollback,
#        _apply_restored_config, _restore_service_state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test environment flag
export SBX_TEST_MODE=1

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Load required modules
source lib/common.sh 2> /dev/null || {
    echo "✗ Failed to load lib/common.sh"
    exit 1
}

source lib/backup.sh 2> /dev/null || {
    echo "✗ Failed to load lib/backup.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo ""
    echo "Test $((TOTAL_TESTS + 1)): $test_name"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if $test_func 2> /dev/null; then
        echo "✓ PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
  else
        echo "✗ FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
  fi
}

echo "=== Backup Module Internal Functions Tests ==="

#==============================================================================
# Tests for _decrypt_backup()
#==============================================================================

test_decrypt_backup_function_exists() {
    type _decrypt_backup > /dev/null 2>&1
}

test_decrypt_backup_defined() {
    grep -q "_decrypt_backup()" lib/backup.sh
}

#==============================================================================
# Tests for _validate_backup_archive()
#==============================================================================

test_validate_backup_archive_exists() {
    type _validate_backup_archive > /dev/null 2>&1
}

test_validate_backup_archive_defined() {
    grep -q "_validate_backup_archive()" lib/backup.sh
}

#==============================================================================
# Tests for _prepare_rollback()
#==============================================================================

test_prepare_rollback_exists() {
    type _prepare_rollback > /dev/null 2>&1
}

test_prepare_rollback_defined() {
    grep -q "_prepare_rollback()" lib/backup.sh
}

#==============================================================================
# Tests for _apply_restored_config()
#==============================================================================

test_apply_restored_config_exists() {
    type _apply_restored_config > /dev/null 2>&1
}

test_apply_restored_config_defined() {
    grep -q "_apply_restored_config()" lib/backup.sh
}

#==============================================================================
# Tests for _restore_service_state()
#==============================================================================

test_restore_service_state_exists() {
    type _restore_service_state > /dev/null 2>&1
}

test_restore_service_state_defined() {
    grep -q "_restore_service_state()" lib/backup.sh
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing _decrypt_backup..."
run_test "Function exists" test_decrypt_backup_function_exists
run_test "Defined in backup module" test_decrypt_backup_defined

echo ""
echo "Testing _validate_backup_archive..."
run_test "Function exists" test_validate_backup_archive_exists
run_test "Defined in backup module" test_validate_backup_archive_defined

echo ""
echo "Testing _prepare_rollback..."
run_test "Function exists" test_prepare_rollback_exists
run_test "Defined in backup module" test_prepare_rollback_defined

echo ""
echo "Testing _apply_restored_config..."
run_test "Function exists" test_apply_restored_config_exists
run_test "Defined in backup module" test_apply_restored_config_defined

echo ""
echo "Testing _restore_service_state..."
run_test "Function exists" test_restore_service_state_exists
run_test "Defined in backup module" test_restore_service_state_defined

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "------------------------------------------"
echo "Total:   $TOTAL_TESTS"
echo "Passed:  $PASSED_TESTS"
echo "Failed:  $FAILED_TESTS"
echo "=========================================="

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi

exit 0
