#!/usr/bin/env bash
# tests/unit/test_config_functions.sh - Simple functional tests for lib/config.sh

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

# Source additional modules
source "${PROJECT_ROOT}/lib/validation.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/config.sh" 2>/dev/null || true

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
# Configuration Validation Tests
#==============================================================================

test_validate_config_vars() {
    echo ""
    echo "Testing validate_config_vars function..."

    # Test 1: Accepts valid configuration
    ENABLE_REALITY=1
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key-12345678901234567890123456"
    SID="a1b2c3d4"
    REALITY_PORT_CHOSEN="443"

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars accepts valid config" "pass"
    else
        test_result "validate_config_vars accepts valid config" "fail"
    fi

    # Test 2: Rejects empty UUID
    ENABLE_REALITY=1
    UUID=""
    PRIV="test-private-key"
    SID="a1b2c3d4"
    REALITY_PORT_CHOSEN="443"

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars rejects empty UUID" "fail"
    else
        test_result "validate_config_vars rejects empty UUID" "pass"
    fi

    # Test 3: Rejects empty private key
    ENABLE_REALITY=1
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV=""
    SID="a1b2c3d4"
    REALITY_PORT_CHOSEN="443"

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars rejects empty PRIV" "fail"
    else
        test_result "validate_config_vars rejects empty PRIV" "pass"
    fi

    # Test 4: Rejects empty short ID
    ENABLE_REALITY=1
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key"
    SID=""
    REALITY_PORT_CHOSEN="443"

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars rejects empty SID" "fail"
    else
        test_result "validate_config_vars rejects empty SID" "pass"
    fi

    # Test 5: Allows empty Reality vars when ENABLE_REALITY=0 (e.g. CF_MODE WS-only)
    ENABLE_REALITY=0
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV=""
    SID=""
    REALITY_PORT_CHOSEN=""

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars allows Reality disabled without vars" "pass"
    else
        test_result "validate_config_vars allows Reality disabled without vars" "fail"
    fi

    # Test 6: Rejects empty port when Reality enabled
    ENABLE_REALITY=1
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key"
    SID="a1b2c3d4"
    REALITY_PORT_CHOSEN=""

    if validate_config_vars 2>/dev/null; then
        test_result "validate_config_vars rejects empty port (Reality enabled)" "fail"
    else
        test_result "validate_config_vars rejects empty port (Reality enabled)" "pass"
    fi
}

#==============================================================================
# Function Existence Tests
#==============================================================================

test_config_functions_exist() {
    echo ""
    echo "Testing config function existence..."

    # Test 1: validate_config_vars exists
    if grep -q "^validate_config_vars()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "validate_config_vars function defined" "pass"
    else
        test_result "validate_config_vars function defined" "fail"
    fi

    # Test 2: create_reality_inbound exists
    if grep -q "^create_reality_inbound()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "create_reality_inbound function defined" "pass"
    else
        test_result "create_reality_inbound function defined" "fail"
    fi

    # Test 3: create_ws_inbound exists
    if grep -q "^create_ws_inbound()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "create_ws_inbound function defined" "pass"
    else
        test_result "create_ws_inbound function defined" "fail"
    fi

    # Test 4: create_hysteria2_inbound exists
    if grep -q "^create_hysteria2_inbound()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "create_hysteria2_inbound function defined" "pass"
    else
        test_result "create_hysteria2_inbound function defined" "fail"
    fi

    # Test 5: add_outbound_config exists
    if grep -q "^add_outbound_config()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "add_outbound_config function defined" "pass"
    else
        test_result "add_outbound_config function defined" "fail"
    fi

    # Test 6: add_route_config exists
    if grep -q "^add_route_config()" "${PROJECT_ROOT}/lib/config.sh"; then
        test_result "add_route_config function defined" "pass"
    else
        test_result "add_route_config function defined" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Configuration Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_config_functions_exist
    test_validate_config_vars

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
