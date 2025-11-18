#!/usr/bin/env bash
# tests/unit/test_service_functions.sh - High-quality unit tests for lib/service.sh
# Tests service file generation and validation logic

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode to avoid interference with test framework
set +e

# Source common.sh first (defines readonly SB_SVC)
if ! source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/common.sh"
    exit 1
fi

# Disable traps after loading modules
trap - EXIT INT TERM

# Reset to permissive mode
set +e
set -o pipefail

# Source service.sh
source "${PROJECT_ROOT}/lib/service.sh" 2>/dev/null || true

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

    # Extract the entire create_service_file function for testing
    local service_func=$(sed -n '/^create_service_file()/,/^}/p' "${PROJECT_ROOT}/lib/service.sh")

    # Test 1: Function defines correct ExecStart
    if echo "$service_func" | grep -q "ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json"; then
        test_result "create_service_file defines correct ExecStart" "pass"
    else
        test_result "create_service_file defines correct ExecStart" "fail"
    fi

    # Test 2: Service template contains [Unit] section
    if echo "$service_func" | grep -q "\[Unit\]"; then
        test_result "Service template contains [Unit] section" "pass"
    else
        test_result "Service template contains [Unit] section" "fail"
    fi

    # Test 3: Service template contains [Service] section
    if echo "$service_func" | grep -q "\[Service\]"; then
        test_result "Service template contains [Service] section" "pass"
    else
        test_result "Service template contains [Service] section" "fail"
    fi

    # Test 4: Service template contains [Install] section
    if echo "$service_func" | grep -q "\[Install\]"; then
        test_result "Service template contains [Install] section" "pass"
    else
        test_result "Service template contains [Install] section" "fail"
    fi

    # Test 5: Service template uses correct binary path
    if echo "$service_func" | grep -q "ExecStart=/usr/local/bin/sing-box"; then
        test_result "Service template uses correct binary path" "pass"
    else
        test_result "Service template uses correct binary path" "fail"
    fi

    # Test 6: Service template contains Restart=on-failure
    if echo "$service_func" | grep -q "Restart=on-failure"; then
        test_result "Service template contains Restart=on-failure" "pass"
    else
        test_result "Service template contains Restart=on-failure" "fail"
    fi

    # Test 7: Service template sets User=root
    if echo "$service_func" | grep -q "User=root"; then
        test_result "Service template sets User=root" "pass"
    else
        test_result "Service template sets User=root" "fail"
    fi

    # Test 8: Service template sets LimitNOFILE
    if echo "$service_func" | grep -q "LimitNOFILE"; then
        test_result "Service template sets LimitNOFILE" "pass"
    else
        test_result "Service template sets LimitNOFILE" "fail"
    fi

    # Test 9: Service template contains After=network.target
    if echo "$service_func" | grep -q "After=network.target"; then
        test_result "Service template contains After=network.target" "pass"
    else
        test_result "Service template contains After=network.target" "fail"
    fi

    # Test 10: Service template contains WantedBy=multi-user.target
    if echo "$service_func" | grep -q "WantedBy=multi-user.target"; then
        test_result "Service template contains WantedBy=multi-user.target" "pass"
    else
        test_result "Service template contains WantedBy=multi-user.target" "fail"
    fi
}

#==============================================================================
# Service Function Existence Tests
#==============================================================================

test_service_functions_exist() {
    echo ""
    echo "Testing service function existence..."

    # Test 1: start_service_with_retry exists
    if grep -q "^start_service_with_retry()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "start_service_with_retry function exists" "pass"
    else
        test_result "start_service_with_retry function exists" "fail"
    fi

    # Test 2: setup_service exists
    if grep -q "^setup_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "setup_service function exists" "pass"
    else
        test_result "setup_service function exists" "fail"
    fi

    # Test 3: validate_port_listening exists
    if grep -q "^validate_port_listening()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "validate_port_listening function exists" "pass"
    else
        test_result "validate_port_listening function exists" "fail"
    fi

    # Test 4: check_service_status exists
    if grep -q "^check_service_status()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "check_service_status function exists" "pass"
    else
        test_result "check_service_status function exists" "fail"
    fi

    # Test 5: stop_service exists
    if grep -q "^stop_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "stop_service function exists" "pass"
    else
        test_result "stop_service function exists" "fail"
    fi

    # Test 6: restart_service exists
    if grep -q "^restart_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "restart_service function exists" "pass"
    else
        test_result "restart_service function exists" "fail"
    fi

    # Test 7: reload_service exists
    if grep -q "^reload_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "reload_service function exists" "pass"
    else
        test_result "reload_service function exists" "fail"
    fi

    # Test 8: remove_service exists
    if grep -q "^remove_service()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "remove_service function exists" "pass"
    else
        test_result "remove_service function exists" "fail"
    fi

    # Test 9: show_service_logs exists
    if grep -q "^show_service_logs()" "${PROJECT_ROOT}/lib/service.sh"; then
        test_result "show_service_logs function exists" "pass"
    else
        test_result "show_service_logs function exists" "fail"
    fi
}

#==============================================================================
# Retry Logic Pattern Tests
#==============================================================================

test_retry_logic() {
    echo ""
    echo "Testing retry logic patterns..."

    # Extract the start_service_with_retry function
    local retry_func=$(sed -n '/^start_service_with_retry()/,/^}/p' "${PROJECT_ROOT}/lib/service.sh")

    # Test 1: Retry logic defines max_retries
    if echo "$retry_func" | grep -q "max_retries"; then
        test_result "Retry logic defines max_retries" "pass"
    else
        test_result "Retry logic defines max_retries" "fail"
    fi

    # Test 2: Retry logic uses retry_count
    if echo "$retry_func" | grep -q "retry_count"; then
        test_result "Retry logic uses retry_count" "pass"
    else
        test_result "Retry logic uses retry_count" "fail"
    fi

    # Test 3: Retry logic checks for port binding errors
    if echo "$retry_func" | grep -q "bind\|port.*already.*in.*use"; then
        test_result "Retry logic checks for port binding errors" "pass"
    else
        test_result "Retry logic checks for port binding errors" "fail"
    fi

    # Test 4: Retry logic uses wait_time for backoff
    if echo "$retry_func" | grep -q "wait_time\|sleep"; then
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
    test_retry_logic

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
