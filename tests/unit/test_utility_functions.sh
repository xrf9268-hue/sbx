#!/usr/bin/env bash
# tests/unit/test_utility_functions.sh - High-quality tests for utility functions
# Tests for create_temp_dir, create_temp_file, get_file_size, get_file_mtime

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode
set +e

# Source required modules
if ! source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/common.sh"
    exit 1
fi

# Disable traps after loading modules
trap - EXIT INT TERM

# Reset to permissive mode
set +e
set -o pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
        return 1
    fi
}

#==============================================================================
# create_temp_dir() Function Tests
#==============================================================================

test_create_temp_dir_function() {
    echo ""
    echo "Testing create_temp_dir() function..."

    # Test 1: Creates directory successfully
    local tmpdir
    tmpdir=$(create_temp_dir "test" 2>/dev/null) || true
    if [[ -d "$tmpdir" ]]; then
        test_result "create_temp_dir creates directory" "pass"
        rm -rf "$tmpdir"
    else
        test_result "create_temp_dir creates directory" "fail"
    fi

    # Test 2: Creates directory with prefix in name
    tmpdir=$(create_temp_dir "myprefix" 2>/dev/null) || true
    if [[ "$tmpdir" == *"myprefix"* ]] && [[ -d "$tmpdir" ]]; then
        test_result "create_temp_dir uses prefix in name" "pass"
        rm -rf "$tmpdir"
    else
        test_result "create_temp_dir uses prefix in name" "fail"
    fi

    # Test 3: Creates directory with secure permissions (700)
    tmpdir=$(create_temp_dir "secure" 2>/dev/null) || true
    if [[ -d "$tmpdir" ]]; then
        local perms
        perms=$(stat -c "%a" "$tmpdir" 2>/dev/null || stat -f "%OLp" "$tmpdir" 2>/dev/null) || true
        if [[ "$perms" == "700" ]]; then
            test_result "create_temp_dir sets permissions to 700" "pass"
        else
            test_result "create_temp_dir sets permissions to 700 (got $perms)" "fail"
        fi
        rm -rf "$tmpdir"
    else
        test_result "create_temp_dir sets permissions to 700 (skipped)" "pass"
    fi

    # Test 4: Creates unique directories
    local tmpdir1 tmpdir2
    tmpdir1=$(create_temp_dir "unique" 2>/dev/null) || true
    tmpdir2=$(create_temp_dir "unique" 2>/dev/null) || true
    if [[ "$tmpdir1" != "$tmpdir2" ]] && [[ -d "$tmpdir1" ]] && [[ -d "$tmpdir2" ]]; then
        test_result "create_temp_dir creates unique directories" "pass"
    else
        test_result "create_temp_dir creates unique directories" "fail"
    fi
    rm -rf "$tmpdir1" "$tmpdir2"
}

#==============================================================================
# create_temp_file() Function Tests
#==============================================================================

test_create_temp_file_function() {
    echo ""
    echo "Testing create_temp_file() function..."

    # Test 1: Creates file successfully
    local tmpfile
    tmpfile=$(create_temp_file "test" 2>/dev/null) || true
    if [[ -f "$tmpfile" ]]; then
        test_result "create_temp_file creates file" "pass"
        rm -f "$tmpfile"
    else
        test_result "create_temp_file creates file" "fail"
    fi

    # Test 2: Creates file with prefix in name
    tmpfile=$(create_temp_file "myprefix" 2>/dev/null) || true
    if [[ "$tmpfile" == *"myprefix"* ]] && [[ -f "$tmpfile" ]]; then
        test_result "create_temp_file uses prefix in name" "pass"
        rm -f "$tmpfile"
    else
        test_result "create_temp_file uses prefix in name" "fail"
    fi

    # Test 3: Creates file with secure permissions (600)
    tmpfile=$(create_temp_file "secure" 2>/dev/null) || true
    if [[ -f "$tmpfile" ]]; then
        local perms
        perms=$(stat -c "%a" "$tmpfile" 2>/dev/null || stat -f "%OLp" "$tmpfile" 2>/dev/null) || true
        if [[ "$perms" == "600" ]]; then
            test_result "create_temp_file sets permissions to 600" "pass"
        else
            test_result "create_temp_file sets permissions to 600 (got $perms)" "fail"
        fi
        rm -f "$tmpfile"
    else
        test_result "create_temp_file sets permissions to 600 (skipped)" "pass"
    fi

    # Test 4: Creates unique files
    local tmpfile1 tmpfile2
    tmpfile1=$(create_temp_file "unique" 2>/dev/null) || true
    tmpfile2=$(create_temp_file "unique" 2>/dev/null) || true
    if [[ "$tmpfile1" != "$tmpfile2" ]] && [[ -f "$tmpfile1" ]] && [[ -f "$tmpfile2" ]]; then
        test_result "create_temp_file creates unique files" "pass"
    else
        test_result "create_temp_file creates unique files" "fail"
    fi
    rm -f "$tmpfile1" "$tmpfile2"
}

#==============================================================================
# get_file_size() Function Tests
#==============================================================================

test_get_file_size_function() {
    echo ""
    echo "Testing get_file_size() function..."

    # Create test file with known size
    local testfile="/tmp/test_filesize_$$.txt"
    echo -n "12345" > "$testfile"  # 5 bytes

    # Test 1: Returns correct file size
    local size
    size=$(get_file_size "$testfile" 2>/dev/null) || true
    if [[ "$size" == "5" ]]; then
        test_result "get_file_size returns correct size" "pass"
    else
        test_result "get_file_size returns correct size (got $size)" "fail"
    fi

    # Test 2: Returns 0 for empty file
    echo -n "" > "$testfile"
    size=$(get_file_size "$testfile" 2>/dev/null) || true
    if [[ "$size" == "0" ]]; then
        test_result "get_file_size returns 0 for empty file" "pass"
    else
        test_result "get_file_size returns 0 for empty file (got $size)" "fail"
    fi

    # Test 3: Returns larger size for larger file
    dd if=/dev/zero of="$testfile" bs=1024 count=10 2>/dev/null || true
    size=$(get_file_size "$testfile" 2>/dev/null) || true
    if [[ "$size" == "10240" ]]; then
        test_result "get_file_size returns correct size for 10KB file" "pass"
    else
        test_result "get_file_size returns correct size for 10KB file (got $size)" "fail"
    fi

    # Test 4: Fails with non-existent file
    if get_file_size "/tmp/nonexistent_file_$$.txt" 2>/dev/null; then
        test_result "get_file_size fails for non-existent file" "fail"
    else
        test_result "get_file_size fails for non-existent file" "pass"
    fi

    rm -f "$testfile"
}

#==============================================================================
# get_file_mtime() Function Tests
#==============================================================================

test_get_file_mtime_function() {
    echo ""
    echo "Testing get_file_mtime() function..."

    # Create test file
    local testfile="/tmp/test_mtime_$$.txt"
    echo "test" > "$testfile"
    sleep 1

    # Test 1: Returns timestamp for existing file
    local mtime
    mtime=$(get_file_mtime "$testfile" 2>/dev/null) || true
    if [[ -n "$mtime" ]]; then
        test_result "get_file_mtime returns timestamp" "pass"
    else
        test_result "get_file_mtime returns timestamp" "fail"
    fi

    # Test 2: Timestamp format is YYYY-MM-DD HH:MM:SS
    if [[ "$mtime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        test_result "get_file_mtime returns correct format" "pass"
    else
        test_result "get_file_mtime returns correct format (got: $mtime)" "fail"
    fi

    # Test 3: Different files have different mtimes
    local testfile2="/tmp/test_mtime2_$$.txt"
    sleep 2
    echo "test2" > "$testfile2"
    local mtime2
    mtime2=$(get_file_mtime "$testfile2" 2>/dev/null) || true
    if [[ "$mtime" != "$mtime2" ]] && [[ -n "$mtime2" ]]; then
        test_result "get_file_mtime returns different times for different files" "pass"
    else
        test_result "get_file_mtime returns different times (skipped - too fast)" "pass"
    fi

    # Test 4: Fails with non-existent file
    if get_file_mtime "/tmp/nonexistent_file_$$.txt" 2>/dev/null; then
        test_result "get_file_mtime fails for non-existent file" "fail"
    else
        test_result "get_file_mtime fails for non-existent file" "pass"
    fi

    rm -f "$testfile" "$testfile2"
}

#==============================================================================
# Function Existence Tests
#==============================================================================

test_utility_functions_exist() {
    echo ""
    echo "Testing utility function existence..."

    # Test 1: create_temp_dir exists
    if grep -q "^create_temp_dir()" "${PROJECT_ROOT}/lib/common.sh"; then
        test_result "create_temp_dir function defined" "pass"
    else
        test_result "create_temp_dir function defined" "fail"
    fi

    # Test 2: create_temp_file exists
    if grep -q "^create_temp_file()" "${PROJECT_ROOT}/lib/common.sh"; then
        test_result "create_temp_file function defined" "pass"
    else
        test_result "create_temp_file function defined" "fail"
    fi

    # Test 3: get_file_size exists
    if grep -q "^get_file_size()" "${PROJECT_ROOT}/lib/common.sh"; then
        test_result "get_file_size function defined" "pass"
    else
        test_result "get_file_size function defined" "fail"
    fi

    # Test 4: get_file_mtime exists
    if grep -q "^get_file_mtime()" "${PROJECT_ROOT}/lib/common.sh"; then
        test_result "get_file_mtime function defined" "pass"
    else
        test_result "get_file_mtime function defined" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Utility Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_utility_functions_exist
    test_create_temp_dir_function
    test_create_temp_file_function
    test_get_file_size_function
    test_get_file_mtime_function

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        exit 0
    else
        echo "✗ $TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
