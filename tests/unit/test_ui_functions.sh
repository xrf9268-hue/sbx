#!/usr/bin/env bash
# Unit tests for UI module functions
# Tests: show_existing_installation_menu, prompt_password, show_spinner,
#        show_progress, show_installation_summary, show_error

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

source lib/ui.sh 2> /dev/null || {
    echo "✗ Failed to load lib/ui.sh"
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

echo "=== UI Module Functions Unit Tests ==="

#==============================================================================
# Tests for show_existing_installation_menu()
#==============================================================================

test_show_existing_installation_menu_exists() {
    type show_existing_installation_menu > /dev/null 2>&1
}

test_show_existing_installation_menu_defined() {
    grep -q "show_existing_installation_menu()" lib/ui.sh
}

#==============================================================================
# Tests for prompt_password()
#==============================================================================

test_prompt_password_exists() {
    type prompt_password > /dev/null 2>&1
}

test_prompt_password_defined() {
    grep -q "prompt_password()" lib/ui.sh
}

test_prompt_password_hides_input() {
    # Should use -s flag for silent/hidden input (e.g., read -rsp)
    grep "prompt_password" lib/ui.sh -A 10 | grep -E "(read.*-.*s|-s|stty)" | grep -q ""
}

#==============================================================================
# Tests for show_spinner()
#==============================================================================

test_show_spinner_exists() {
    type show_spinner > /dev/null 2>&1
}

test_show_spinner_defined() {
    grep -q "show_spinner()" lib/ui.sh
}

#==============================================================================
# Tests for show_progress()
#==============================================================================

test_show_progress_exists() {
    type show_progress > /dev/null 2>&1
}

test_show_progress_defined() {
    grep -q "show_progress()" lib/ui.sh
}

#==============================================================================
# Tests for show_installation_summary()
#==============================================================================

test_show_installation_summary_exists() {
    type show_installation_summary > /dev/null 2>&1
}

test_show_installation_summary_defined() {
    grep -q "show_installation_summary()" lib/ui.sh
}

#==============================================================================
# Tests for show_error()
#==============================================================================

test_show_error_exists() {
    type show_error > /dev/null 2>&1
}

test_show_error_defined() {
    grep -q "show_error()" lib/ui.sh
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing show_existing_installation_menu..."
run_test "Function exists" test_show_existing_installation_menu_exists
run_test "Defined in UI module" test_show_existing_installation_menu_defined

echo ""
echo "Testing prompt_password..."
run_test "Function exists" test_prompt_password_exists
run_test "Defined in UI module" test_prompt_password_defined
run_test "Hides input (uses -s or stty)" test_prompt_password_hides_input

echo ""
echo "Testing show_spinner..."
run_test "Function exists" test_show_spinner_exists
run_test "Defined in UI module" test_show_spinner_defined

echo ""
echo "Testing show_progress..."
run_test "Function exists" test_show_progress_exists
run_test "Defined in UI module" test_show_progress_defined

echo ""
echo "Testing show_installation_summary..."
run_test "Function exists" test_show_installation_summary_exists
run_test "Defined in UI module" test_show_installation_summary_defined

echo ""
echo "Testing show_error..."
run_test "Function exists" test_show_error_exists
run_test "Defined in UI module" test_show_error_defined

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
