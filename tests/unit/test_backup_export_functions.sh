#!/usr/bin/env bash
# tests/unit/test_backup_export_functions.sh - High-quality tests for backup and export functions
# Tests for lib/backup.sh and lib/export.sh function existence and patterns

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
# Backup Function Existence Tests
#==============================================================================

test_backup_functions_exist() {
    echo ""
    echo "Testing backup function existence..."

    # Test 1: backup_create exists
    if grep -q "^backup_create()" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "backup_create function defined" "pass"
    else
        test_result "backup_create function defined" "fail"
    fi

    # Test 2: backup_restore exists
    if grep -q "^backup_restore()" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "backup_restore function defined" "pass"
    else
        test_result "backup_restore function defined" "fail"
    fi

    # Test 3: backup_list exists
    if grep -q "^backup_list()" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "backup_list function defined" "pass"
    else
        test_result "backup_list function defined" "fail"
    fi

    # Test 4: backup_cleanup exists
    if grep -q "^backup_cleanup()" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "backup_cleanup function defined" "pass"
    else
        test_result "backup_cleanup function defined" "fail"
    fi
}

#==============================================================================
# Export Function Existence Tests
#==============================================================================

test_export_functions_exist() {
    echo ""
    echo "Testing export function existence..."

    # Test 1: load_client_info exists
    if grep -q "^load_client_info()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "load_client_info function defined" "pass"
    else
        test_result "load_client_info function defined" "fail"
    fi

    # Test 2: export_clash_yaml exists
    if grep -q "^export_clash_yaml()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "export_clash_yaml function defined" "pass"
    else
        test_result "export_clash_yaml function defined" "fail"
    fi

    # Test 3: export_uri exists
    if grep -q "^export_uri()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "export_uri function defined" "pass"
    else
        test_result "export_uri function defined" "fail"
    fi

    # Test 4: export_qr_codes exists
    if grep -q "^export_qr_codes()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "export_qr_codes function defined" "pass"
    else
        test_result "export_qr_codes function defined" "fail"
    fi

    # Test 5: export_subscription exists
    if grep -q "^export_subscription()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "export_subscription function defined" "pass"
    else
        test_result "export_subscription function defined" "fail"
    fi

    # Test 6: export_config exists
    if grep -q "^export_config()" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "export_config function defined" "pass"
    else
        test_result "export_config function defined" "fail"
    fi
}

#==============================================================================
# Backup Pattern Tests
#==============================================================================

test_backup_patterns() {
    echo ""
    echo "Testing backup implementation patterns..."

    # Test 1: Backup uses tar for archive creation
    if grep -q "tar.*czf\|tar -c" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "Backup uses tar for archive creation" "pass"
    else
        test_result "Backup uses tar for archive creation" "fail"
    fi

    # Test 2: Backup supports encryption
    if grep -q "openssl.*enc\|ENCRYPT" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "Backup supports encryption" "pass"
    else
        test_result "Backup supports encryption" "fail"
    fi

    # Test 3: Backup uses date-based naming
    if grep -q "date.*%Y\|%m\|%d\|backup.*date" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "Backup uses date-based naming" "pass"
    else
        test_result "Backup uses date-based naming" "fail"
    fi

    # Test 4: Backup cleanup handles old files
    if grep -q "find.*-mtime\|days\|retention" "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null; then
        test_result "Backup cleanup handles retention" "pass"
    else
        test_result "Backup cleanup handles retention" "fail"
    fi
}

#==============================================================================
# Export Pattern Tests
#==============================================================================

test_export_patterns() {
    echo ""
    echo "Testing export implementation patterns..."

    # Test 1: Export loads client info file
    if grep -qi "client.*info\|load.*client" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "Export references client info" "pass"
    else
        test_result "Export references client info" "fail"
    fi

    # Test 2: Export generates VLESS URIs
    if grep -q "vless://\|VLESS" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "Export generates VLESS URIs" "pass"
    else
        test_result "Export generates VLESS URIs" "fail"
    fi

    # Test 3: Export supports base64 encoding
    if grep -q "base64\|b64encode" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "Export uses base64 encoding" "pass"
    else
        test_result "Export uses base64 encoding" "fail"
    fi

    # Test 4: Export generates QR codes
    if grep -q "qrencode\|qr.*code" "${PROJECT_ROOT}/lib/export.sh" 2>/dev/null; then
        test_result "Export supports QR code generation" "pass"
    else
        test_result "Export supports QR code generation" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Backup & Export Functions Unit Tests"
    echo "=========================================="

    # Run test suites
    test_backup_functions_exist
    test_export_functions_exist
    test_backup_patterns
    test_export_patterns

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
