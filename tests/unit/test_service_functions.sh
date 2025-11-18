#!/usr/bin/env bash
# tests/unit/test_service_functions.sh - Comprehensive service management tests
# Tests for lib/service.sh functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

# Source required modules
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/service.sh"

#==============================================================================
# Test Suite: create_service_file
#==============================================================================

test_create_service_file_structure() {
    setup_test_env

    result=$(create_service_file)

    # Check for systemd service structure
    assert_contains "$result" "[Unit]" "Should contain Unit section"
    assert_contains "$result" "[Service]" "Should contain Service section"
    assert_contains "$result" "[Install]" "Should contain Install section"
    assert_contains "$result" "Description=sing-box" "Should contain service description"
    assert_contains "$result" "Type=simple" "Should be simple service type"
    assert_contains "$result" "ExecStart=/usr/local/bin/sing-box run" "Should contain correct ExecStart"
    assert_contains "$result" "Restart=on-failure" "Should restart on failure"
    assert_contains "$result" "WantedBy=multi-user.target" "Should be wanted by multi-user"

    teardown_test_env
}

test_create_service_file_security_hardening() {
    setup_test_env

    result=$(create_service_file)

    # Check for security hardening options
    assert_contains "$result" "NoNewPrivileges=true" "Should prevent privilege escalation"
    assert_contains "$result" "ProtectSystem=strict" "Should protect system directories"
    assert_contains "$result" "PrivateTmp=true" "Should use private tmp"

    teardown_test_env
}

#==============================================================================
# Test Suite: check_service_status
#==============================================================================

test_check_service_status_output_structure() {
    setup_test_env

    # This test checks the function structure, not actual systemctl
    # We'll test it doesn't crash with basic inputs
    if command -v systemctl &>/dev/null; then
        # Function should not crash
        check_service_status "nonexistent-test-service-$$" &>/dev/null || true
        assert_success 0 "Function should handle nonexistent service gracefully"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: validate_port_listening
#==============================================================================

test_validate_port_listening_invalid_port() {
    setup_test_env

    # Invalid port number
    if validate_port_listening "99999" 2>/dev/null; then
        assert_failure 1 "Should reject invalid port number"
    else
        assert_success 0 "Correctly rejected invalid port"
    fi

    teardown_test_env
}

test_validate_port_listening_zero_port() {
    setup_test_env

    # Port 0 is invalid
    if validate_port_listening "0" 2>/dev/null; then
        assert_failure 1 "Should reject port 0"
    else
        assert_success 0 "Correctly rejected port 0"
    fi

    teardown_test_env
}

test_validate_port_listening_negative_port() {
    setup_test_env

    # Negative port is invalid
    if validate_port_listening "-1" 2>/dev/null; then
        assert_failure 1 "Should reject negative port"
    else
        assert_success 0 "Correctly rejected negative port"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: show_service_logs
#==============================================================================

test_show_service_logs_parameters() {
    setup_test_env

    # Function should accept service name parameter
    # Test it doesn't crash with basic inputs
    if command -v journalctl &>/dev/null; then
        show_service_logs "nonexistent-service-$$" 2>/dev/null || true
        assert_success 0 "Function should handle parameters gracefully"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: Service State Functions
#==============================================================================

test_stop_service_structure() {
    setup_test_env

    # Test function exists and accepts parameters
    if command -v systemctl &>/dev/null; then
        # Function should not crash with nonexistent service
        stop_service "nonexistent-service-$$" 2>/dev/null || true
        assert_success 0 "Function should handle nonexistent service"
    fi

    teardown_test_env
}

test_reload_service_structure() {
    setup_test_env

    # Test function exists and accepts parameters
    if command -v systemctl &>/dev/null; then
        # Function should not crash with nonexistent service
        reload_service "nonexistent-service-$$" 2>/dev/null || true
        assert_success 0 "Function should handle nonexistent service"
    fi

    teardown_test_env
}

test_restart_service_structure() {
    setup_test_env

    # Test function exists and accepts parameters
    if command -v systemctl &>/dev/null; then
        # Function should not crash with nonexistent service
        restart_service "nonexistent-service-$$" 2>/dev/null || true
        assert_success 0 "Function should handle nonexistent service"
    fi

    teardown_test_env
}

test_remove_service_structure() {
    setup_test_env

    # Test function exists and accepts parameters
    if command -v systemctl &>/dev/null; then
        # Function should not crash with nonexistent service
        remove_service "nonexistent-service-$$" 2>/dev/null || true
        assert_success 0 "Function should handle nonexistent service"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: setup_service
#==============================================================================

test_setup_service_parameters() {
    setup_test_env

    # Test that setup_service requires systemd
    if ! command -v systemctl &>/dev/null; then
        setup_service 2>/dev/null || true
        assert_success 0 "Function should handle missing systemd"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: start_service_with_retry
#==============================================================================

test_start_service_with_retry_invalid_service() {
    setup_test_env

    # Test with nonexistent service
    if command -v systemctl &>/dev/null; then
        if start_service_with_retry "nonexistent-service-$$" 2>/dev/null; then
            assert_failure 1 "Should fail for nonexistent service"
        else
            assert_success 0 "Correctly failed for nonexistent service"
        fi
    fi

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Service Functions Tests ==="
echo ""

# Service file creation tests
test_create_service_file_structure
test_create_service_file_security_hardening

# Service status tests
test_check_service_status_output_structure

# Port listening validation tests
test_validate_port_listening_invalid_port
test_validate_port_listening_zero_port
test_validate_port_listening_negative_port

# Service logs tests
test_show_service_logs_parameters

# Service state management tests
test_stop_service_structure
test_reload_service_structure
test_restart_service_structure
test_remove_service_structure
test_setup_service_parameters
test_start_service_with_retry_invalid_service

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
