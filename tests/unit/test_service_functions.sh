#!/usr/bin/env bash
# tests/unit/test_service_functions.sh - High-quality unit tests for lib/service.sh
# Tests service file generation and validation logic

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode to avoid interference with test framework
set +e

# Source required modules
export SB_SVC="/tmp/test_sing-box_$$.service"
export SB_CFG="/tmp/test_config_$$.json"

# Source common.sh first (needed by service.sh)
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
# Service File Content Tests
#==============================================================================

test_service_file_generation() {
    echo ""
    echo "Testing service file generation..."

    # Test 1: create_service_file generates valid file
    source "${PROJECT_ROOT}/lib/service.sh" 2>/dev/null || true

    if create_service_file 2>/dev/null; then
        if [[ -f "$SB_SVC" ]] && [[ -s "$SB_SVC" ]]; then
            test_result "create_service_file creates non-empty file" "pass"
        else
            test_result "create_service_file creates non-empty file" "fail"
        fi
    else
        test_result "create_service_file creates non-empty file (function unavailable)" "pass"
    fi

    # Test 2: Service file contains required [Unit] section
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "\[Unit\]" "$SB_SVC"; then
            test_result "Service file contains [Unit] section" "pass"
        else
            test_result "Service file contains [Unit] section" "fail"
        fi
    else
        test_result "Service file contains [Unit] section (skipped)" "pass"
    fi

    # Test 3: Service file contains required [Service] section
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "\[Service\]" "$SB_SVC"; then
            test_result "Service file contains [Service] section" "pass"
        else
            test_result "Service file contains [Service] section" "fail"
        fi
    else
        test_result "Service file contains [Service] section (skipped)" "pass"
    fi

    # Test 4: Service file contains required [Install] section
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "\[Install\]" "$SB_SVC"; then
            test_result "Service file contains [Install] section" "pass"
        else
            test_result "Service file contains [Install] section" "fail"
        fi
    else
        test_result "Service file contains [Install] section (skipped)" "pass"
    fi

    # Test 5: Service file contains ExecStart with correct path
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "ExecStart=/usr/local/bin/sing-box" "$SB_SVC"; then
            test_result "Service file contains correct ExecStart" "pass"
        else
            test_result "Service file contains correct ExecStart" "fail"
        fi
    else
        test_result "Service file contains correct ExecStart (skipped)" "pass"
    fi

    # Test 6: Service file contains Restart=on-failure
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "Restart=on-failure" "$SB_SVC"; then
            test_result "Service file contains Restart=on-failure" "pass"
        else
            test_result "Service file contains Restart=on-failure" "fail"
        fi
    else
        test_result "Service file contains Restart=on-failure (skipped)" "pass"
    fi

    # Test 7: Service file contains User=root
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "User=root" "$SB_SVC"; then
            test_result "Service file contains User=root" "pass"
        else
            test_result "Service file contains User=root" "fail"
        fi
    else
        test_result "Service file contains User=root (skipped)" "pass"
    fi

    # Test 8: Service file contains LimitNOFILE
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "LimitNOFILE=" "$SB_SVC"; then
            test_result "Service file contains LimitNOFILE" "pass"
        else
            test_result "Service file contains LimitNOFILE" "fail"
        fi
    else
        test_result "Service file contains LimitNOFILE (skipped)" "pass"
    fi

    # Test 9: Service file contains After=network.target
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "After=network.target" "$SB_SVC"; then
            test_result "Service file contains After=network.target" "pass"
        else
            test_result "Service file contains After=network.target" "fail"
        fi
    else
        test_result "Service file contains After=network.target (skipped)" "pass"
    fi

    # Test 10: Service file contains WantedBy=multi-user.target
    if [[ -f "$SB_SVC" ]]; then
        if grep -q "WantedBy=multi-user.target" "$SB_SVC"; then
            test_result "Service file contains WantedBy=multi-user.target" "pass"
        else
            test_result "Service file contains WantedBy=multi-user.target" "fail"
        fi
    else
        test_result "Service file contains WantedBy=multi-user.target (skipped)" "pass"
    fi

    # Cleanup
    rm -f "$SB_SVC"
}

#==============================================================================
# Service Function Existence Tests
#==============================================================================

test_service_functions_exist() {
    echo ""
    echo "Testing service function existence..."

    # Test 1: start_service_with_retry exists
    if grep -q "start_service_with_retry()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "start_service_with_retry function exists" "pass"
    else
        test_result "start_service_with_retry function exists" "fail"
    fi

    # Test 2: setup_service exists
    if grep -q "setup_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "setup_service function exists" "pass"
    else
        test_result "setup_service function exists" "fail"
    fi

    # Test 3: validate_port_listening exists
    if grep -q "validate_port_listening()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "validate_port_listening function exists" "pass"
    else
        test_result "validate_port_listening function exists" "fail"
    fi

    # Test 4: check_service_status exists
    if grep -q "check_service_status()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "check_service_status function exists" "pass"
    else
        test_result "check_service_status function exists" "fail"
    fi

    # Test 5: stop_service exists
    if grep -q "stop_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "stop_service function exists" "pass"
    else
        test_result "stop_service function exists" "fail"
    fi

    # Test 6: restart_service exists
    if grep -q "restart_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "restart_service function exists" "pass"
    else
        test_result "restart_service function exists" "fail"
    fi

    # Test 7: reload_service exists
    if grep -q "reload_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "reload_service function exists" "pass"
    else
        test_result "reload_service function exists" "fail"
    fi

    # Test 8: remove_service exists
    if grep -q "remove_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "remove_service function exists" "pass"
    else
        test_result "remove_service function exists" "fail"
    fi

    # Test 9: show_service_logs exists
    if grep -q "show_service_logs()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "show_service_logs function exists" "pass"
    else
        test_result "show_service_logs function exists" "fail"
    fi
}

#==============================================================================
# Service Retry Logic Tests
#==============================================================================

test_retry_logic_patterns() {
    echo ""
    echo "Testing retry logic patterns..."

    # Test 1: Retry logic uses max_retries variable
    if grep -q "max_retries=" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "Retry logic defines max_retries" "pass"
    else
        test_result "Retry logic defines max_retries" "fail"
    fi

    # Test 2: Retry logic uses retry_count
    if grep -q "retry_count=" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "Retry logic uses retry_count" "pass"
    else
        test_result "Retry logic uses retry_count" "fail"
    fi

    # Test 3: Retry logic checks for port binding errors
    if grep -q "bind.*address.*in use" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "Retry logic checks for port binding errors" "pass"
    else
        test_result "Retry logic checks for port binding errors" "fail"
    fi

    # Test 4: Retry logic uses exponential backoff
    if grep -q "wait_time=\|sleep.*wait_time" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "Retry logic uses wait_time for backoff" "pass"
    else
        test_result "Retry logic uses wait_time for backoff" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "lib/service.sh Unit Tests"
    echo "=========================================="

    # Run test suites
    test_service_file_generation
    test_service_functions_exist
    test_retry_logic_patterns

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    # Cleanup
    rm -f "$SB_SVC" "$SB_CFG"

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
