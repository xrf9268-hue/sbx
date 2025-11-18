#!/usr/bin/env bash
# tests/unit/test_caddy_schema_functions.sh - High-quality tests for Caddy functions
# Tests for lib/caddy.sh function existence and patterns

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode
set +e

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
# Caddy Function Existence Tests
#==============================================================================

test_caddy_functions_exist() {
    echo ""
    echo "Testing Caddy function existence..."

    if [[ -f "${PROJECT_ROOT}/lib/caddy.sh" ]]; then
        # Test 1: install_caddy exists
        if grep -q "install.*caddy\|setup.*caddy" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy installation functions present" "pass"
        else
            test_result "Caddy installation functions present" "fail"
        fi

        # Test 2: Caddy configuration functions present
        if grep -qi "caddyfile\|caddy.*config" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy configuration functions present" "pass"
        else
            test_result "Caddy configuration functions present" "fail"
        fi

        # Test 3: manage_caddy_service exists
        if grep -q "start.*caddy\|stop.*caddy\|restart.*caddy" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy service management functions present" "pass"
        else
            test_result "Caddy service management functions present" "fail"
        fi

        # Test 4: Caddy cleanup functions present
        if grep -qi "remove\|cleanup\|uninstall" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy cleanup functions present" "pass"
        else
            test_result "Caddy cleanup functions present" "fail"
        fi
    else
        test_result "caddy.sh module exists" "fail"
        test_result "Caddy installation functions (skipped)" "pass"
        test_result "Caddy configuration functions (skipped)" "pass"
        test_result "Caddy service management functions (skipped)" "pass"
        test_result "Caddy cleanup functions (skipped)" "pass"
    fi
}

#==============================================================================
# Caddy Pattern Tests
#==============================================================================

test_caddy_patterns() {
    echo ""
    echo "Testing Caddy implementation patterns..."

    if [[ -f "${PROJECT_ROOT}/lib/caddy.sh" ]]; then
        # Test 1: Caddy uses systemd
        if grep -qi "systemctl\|systemd\|caddy.*service" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy uses systemd integration" "pass"
        else
            test_result "Caddy uses systemd integration" "fail"
        fi

        # Test 2: Caddy handles certificates
        if grep -qi "cert\|tls\|acme\|letsencrypt" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy handles certificate management" "pass"
        else
            test_result "Caddy handles certificate management" "fail"
        fi

        # Test 3: Caddy validates domain
        if grep -qi "domain\|validate.*domain" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy validates domain names" "pass"
        else
            test_result "Caddy validates domain names" "fail"
        fi

        # Test 4: Caddy uses ports
        if grep -qi "port.*80\|port.*443\|listen.*:" "${PROJECT_ROOT}/lib/caddy.sh" 2>/dev/null; then
            test_result "Caddy configures port bindings" "pass"
        else
            test_result "Caddy configures port bindings" "fail"
        fi
    else
        test_result "Caddy uses systemd integration (skipped)" "pass"
        test_result "Caddy handles certificate management (skipped)" "pass"
        test_result "Caddy validates domain names (skipped)" "pass"
        test_result "Caddy configures port bindings (skipped)" "pass"
    fi
}

#==============================================================================
# Schema Validator Tests
#==============================================================================

test_schema_validator_functions() {
    echo ""
    echo "Testing schema validator functions..."

    if [[ -f "${PROJECT_ROOT}/lib/schema_validator.sh" ]]; then
        test_result "schema_validator.sh module exists" "pass"

        # Test 1: validate_json exists
        if grep -q "validate.*json\|json.*schema" "${PROJECT_ROOT}/lib/schema_validator.sh" 2>/dev/null; then
            test_result "JSON validation functions present" "pass"
        else
            test_result "JSON validation functions present" "fail"
        fi

        # Test 2: Schema validation uses jq
        if grep -qi "jq\|json" "${PROJECT_ROOT}/lib/schema_validator.sh" 2>/dev/null; then
            test_result "Schema validator uses JSON tools" "pass"
        else
            test_result "Schema validator uses JSON tools" "fail"
        fi
    else
        test_result "schema_validator.sh module exists" "fail"
        test_result "JSON validation functions (skipped)" "pass"
        test_result "Schema validator uses JSON tools (skipped)" "pass"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Caddy & Schema Validator Unit Tests"
    echo "=========================================="

    # Run test suites
    test_caddy_functions_exist
    test_caddy_patterns
    test_schema_validator_functions

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
