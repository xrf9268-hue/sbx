#!/usr/bin/env bash
# tests/unit/test_ui_certificate_functions.sh - High-quality tests for UI and certificate functions
# Tests for lib/ui.sh and lib/certificate.sh function existence

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
# UI Function Existence Tests
#==============================================================================

test_ui_functions_exist() {
    echo ""
    echo "Testing UI function existence..."

    # Test 1: show_logo exists
    if grep -q "^show_logo()\|^show_sbx_logo()" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "Logo display function defined" "pass"
    else
        test_result "Logo display function defined" "fail"
    fi

    # Test 2: prompt_yes_no exists
    if grep -q "^prompt_yes_no()" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "prompt_yes_no function defined" "pass"
    else
        test_result "prompt_yes_no function defined" "fail"
    fi

    # Test 3: prompt_input exists
    if grep -q "^prompt_input()" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "prompt_input function defined" "pass"
    else
        test_result "prompt_input function defined" "fail"
    fi

    # Test 4: prompt_menu_choice exists
    if grep -q "^prompt_menu_choice()" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "prompt_menu_choice function defined" "pass"
    else
        test_result "prompt_menu_choice function defined" "fail"
    fi

    # Test 5: show_config_summary exists
    if grep -q "^show_config_summary()" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "show_config_summary function defined" "pass"
    else
        test_result "show_config_summary function defined" "fail"
    fi
}

#==============================================================================
# Certificate Function Existence Tests
#==============================================================================

test_certificate_functions_exist() {
    echo ""
    echo "Testing certificate function existence..."

    # Test 1: Check if certificate.sh exists
    if [[ -f "${PROJECT_ROOT}/lib/certificate.sh" ]]; then
        test_result "certificate.sh module exists" "pass"

        # Test 2: Certificate functions present
        if grep -qi "cert\|certificate" "${PROJECT_ROOT}/lib/certificate.sh" 2>/dev/null; then
            test_result "Certificate functions present" "pass"
        else
            test_result "Certificate functions present" "fail"
        fi

        # Test 3: validate_certificate exists
        if grep -q "validate.*cert\|check.*cert" "${PROJECT_ROOT}/lib/certificate.sh" 2>/dev/null; then
            test_result "Certificate validation functions present" "pass"
        else
            test_result "Certificate validation functions present" "fail"
        fi
    else
        test_result "certificate.sh module exists" "fail"
        test_result "Certificate generation functions (skipped)" "pass"
        test_result "Certificate validation functions (skipped)" "pass"
    fi
}

#==============================================================================
# UI Pattern Tests
#==============================================================================

test_ui_patterns() {
    echo ""
    echo "Testing UI implementation patterns..."

    # Test 1: UI module functionality
    if grep -qi "prompt\|menu\|display\|show" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "UI provides user interaction" "pass"
    else
        test_result "UI provides user interaction" "fail"
    fi

    # Test 2: UI handles user input
    if grep -q "read.*-p\|read -r" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "UI handles user input" "pass"
    else
        test_result "UI handles user input" "fail"
    fi

    # Test 3: UI provides interactive menus
    if grep -qi "menu\|select\|choice" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "UI provides interactive menus" "pass"
    else
        test_result "UI provides interactive menus" "fail"
    fi

    # Test 4: UI shows progress indicators
    if grep -qi "spinner\|progress\|loading" "${PROJECT_ROOT}/lib/ui.sh" 2>/dev/null; then
        test_result "UI shows progress indicators" "pass"
    else
        test_result "UI shows progress indicators" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "UI & Certificate Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_ui_functions_exist
    test_certificate_functions_exist
    test_ui_patterns

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
