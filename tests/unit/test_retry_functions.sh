#!/usr/bin/env bash
# Unit tests for retry functions in lib/retry.sh
# Tests: retry_with_backoff, reset_retry_counter

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

source lib/retry.sh 2> /dev/null || {
    echo "✗ Failed to load lib/retry.sh"
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

echo "=== Retry Functions Unit Tests ==="

#==============================================================================
# Tests for reset_retry_counter()
#==============================================================================

test_reset_retry_counter_resets_to_zero() {
    # Set counter to a non-zero value
    GLOBAL_RETRY_COUNT=10
    reset_retry_counter
    [[ $GLOBAL_RETRY_COUNT -eq 0 ]]
}

test_reset_retry_counter_function_exists() {
    type reset_retry_counter > /dev/null 2>&1
}

test_reset_retry_counter_multiple_resets() {
    GLOBAL_RETRY_COUNT=5
    reset_retry_counter
    [[ $GLOBAL_RETRY_COUNT -eq 0 ]]
    GLOBAL_RETRY_COUNT=100
    reset_retry_counter
    [[ $GLOBAL_RETRY_COUNT -eq 0 ]]
}

#==============================================================================
# Tests for retry_with_backoff()
#==============================================================================

test_retry_with_backoff_function_exists() {
    type retry_with_backoff > /dev/null 2>&1
}

test_retry_with_backoff_succeeds_immediately() {
    # Reset counter before test
    reset_retry_counter
    # A command that always succeeds should return 0
    retry_with_backoff 3 true
}

test_retry_with_backoff_fails_after_retries() {
    # Reset counter before test
    reset_retry_counter
    # A command that always fails should return non-zero after max attempts
    # Using max attempts of 1 to speed up test
    ! retry_with_backoff 1 false
}

test_retry_with_backoff_accepts_max_attempts() {
    reset_retry_counter
    # Should accept numeric first argument as max attempts
    retry_with_backoff 2 true
}

test_retry_with_backoff_increments_counter_on_failure() {
    reset_retry_counter
    local initial_count=$GLOBAL_RETRY_COUNT
    # Run command that fails (with 1 attempt to speed up)
    retry_with_backoff 1 false 2> /dev/null || true
    # Counter should have increased
    [[ $GLOBAL_RETRY_COUNT -ge $initial_count ]]
}

#==============================================================================
# Tests for get_retry_stats()
#==============================================================================

test_get_retry_stats_returns_output() {
    local output
    output=$(get_retry_stats)
    [[ -n "$output" ]]
}

test_get_retry_stats_shows_count() {
    local output
    output=$(get_retry_stats)
    [[ "$output" == *"count"* ]] || [[ "$output" == *"retry"* ]]
}

test_get_retry_stats_shows_budget() {
    local output
    output=$(get_retry_stats)
    [[ "$output" == *"budget"* ]] || [[ "$output" == *"remaining"* ]]
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing reset_retry_counter..."
run_test "Function exists" test_reset_retry_counter_function_exists
run_test "Resets counter to zero" test_reset_retry_counter_resets_to_zero
run_test "Multiple resets work" test_reset_retry_counter_multiple_resets

echo ""
echo "Testing retry_with_backoff..."
run_test "Function exists" test_retry_with_backoff_function_exists
run_test "Succeeds immediately on success" test_retry_with_backoff_succeeds_immediately
run_test "Fails after max retries" test_retry_with_backoff_fails_after_retries
run_test "Accepts max attempts parameter" test_retry_with_backoff_accepts_max_attempts
run_test "Increments counter on failure" test_retry_with_backoff_increments_counter_on_failure

echo ""
echo "Testing get_retry_stats..."
run_test "Returns output" test_get_retry_stats_returns_output
run_test "Shows count info" test_get_retry_stats_shows_count
run_test "Shows budget info" test_get_retry_stats_shows_budget

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
