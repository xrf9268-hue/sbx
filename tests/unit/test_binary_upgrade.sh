#!/usr/bin/env bash
# tests/unit/test_binary_upgrade.sh - Tests for binary upgrade functionality
# Validates fix for "Text file busy" error during binary upgrade
# Issue: cp fails when service is running because binary is in use

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode
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
# Binary Upgrade Tests - Validates "Text file busy" fix
#==============================================================================

test_binary_upgrade_service_stop() {
    echo ""
    echo "Testing binary upgrade service stop logic..."

    # Extract the download_singbox function from install.sh
    local func_content
    func_content=$(sed -n '/^download_singbox()/,/^}/p' "${PROJECT_ROOT}/install.sh")

    # Test 1: Function checks service status before copy
    if echo "$func_content" | grep -q "check_service_status"; then
        test_result "download_singbox() checks service status before copy" "pass"
    else
        test_result "download_singbox() checks service status before copy" "fail"
    fi

    # Test 2: Function stops service before copy
    if echo "$func_content" | grep -q "stop_service"; then
        test_result "download_singbox() stops service before binary replacement" "pass"
    else
        test_result "download_singbox() stops service before binary replacement" "fail"
    fi

    # Test 3: Function has comment explaining why service is stopped
    if echo "$func_content" | grep -q "Text file busy"; then
        test_result "download_singbox() has comment explaining Text file busy fix" "pass"
    else
        test_result "download_singbox() has comment explaining Text file busy fix" "fail"
    fi

    # Test 4: Function tracks service_was_running state
    if echo "$func_content" | grep -q "service_was_running"; then
        test_result "download_singbox() tracks service_was_running state" "pass"
    else
        test_result "download_singbox() tracks service_was_running state" "fail"
    fi

    # Test 5: Binary copy has error handling
    if echo "$func_content" | grep -q 'cp.*||'; then
        test_result "download_singbox() has error handling for cp command" "pass"
    else
        test_result "download_singbox() has error handling for cp command" "fail"
    fi

    # Test 6: Error handler tries to restart service if it was running
    if echo "$func_content" | grep -q 'start_service_with_retry'; then
        test_result "download_singbox() error handler restarts service if it was stopped" "pass"
    else
        test_result "download_singbox() error handler restarts service if it was stopped" "fail"
    fi
}

#==============================================================================
# Service Management Integration Tests
#==============================================================================

test_service_management_exports() {
    echo ""
    echo "Testing service management functions availability..."

    # Source common.sh and service.sh
    source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || true
    trap - EXIT INT TERM
    source "${PROJECT_ROOT}/lib/service.sh" 2>/dev/null || true

    # Test 1: check_service_status is available
    if type check_service_status &>/dev/null; then
        test_result "check_service_status function is available" "pass"
    else
        test_result "check_service_status function is available" "fail"
    fi

    # Test 2: stop_service is available
    if type stop_service &>/dev/null; then
        test_result "stop_service function is available" "pass"
    else
        test_result "stop_service function is available" "fail"
    fi

    # Test 3: start_service_with_retry is available
    if type start_service_with_retry &>/dev/null; then
        test_result "start_service_with_retry function is available" "pass"
    else
        test_result "start_service_with_retry function is available" "fail"
    fi
}

#==============================================================================
# Upgrade Flow Tests
#==============================================================================

test_upgrade_flow_options() {
    echo ""
    echo "Testing upgrade flow options..."

    local install_sh="${PROJECT_ROOT}/install.sh"

    # Test 1: Option 2 sets SKIP_CONFIG_GEN=1
    if grep -A 5 "2).*# Upgrade binary only" "$install_sh" | grep -q "SKIP_CONFIG_GEN=1"; then
        test_result "Option 2 (upgrade) sets SKIP_CONFIG_GEN=1" "pass"
    else
        test_result "Option 2 (upgrade) sets SKIP_CONFIG_GEN=1" "fail"
    fi

    # Test 2: Option 2 sets SKIP_BINARY_DOWNLOAD=0
    if grep -A 5 "2).*# Upgrade binary only" "$install_sh" | grep -q "SKIP_BINARY_DOWNLOAD=0"; then
        test_result "Option 2 (upgrade) sets SKIP_BINARY_DOWNLOAD=0" "pass"
    else
        test_result "Option 2 (upgrade) sets SKIP_BINARY_DOWNLOAD=0" "fail"
    fi

    # Test 3: Binary upgrade path calls restart_service
    if grep -B 3 -A 3 "Binary upgrade completed" "$install_sh" | grep -q "restart_service"; then
        test_result "Binary upgrade path calls restart_service" "pass"
    else
        test_result "Binary upgrade path calls restart_service" "fail"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

main() {
    echo "=============================================="
    echo "Binary Upgrade Tests (Text file busy fix)"
    echo "=============================================="

    test_binary_upgrade_service_stop
    test_service_management_exports
    test_upgrade_flow_options

    echo ""
    echo "=============================================="
    echo "Test Summary"
    echo "=============================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo "✓ All tests passed!"
        exit 0
    else
        echo ""
        echo "✗ Some tests failed"
        exit 1
    fi
}

main "$@"
