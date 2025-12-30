#!/usr/bin/env bash
# tests/unit/test_certificate_helpers.sh - Unit tests for lib/certificate.sh helpers
# Focuses on lightweight, non-destructive behaviors

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the certificate module
source "${PROJECT_ROOT}/lib/certificate.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/certificate.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local test_name="$1"
    local result="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
    fi
}

#==============================================================================
# check_cert_expiry
#==============================================================================

test_check_cert_expiry_missing_file() {
    echo ""
    echo "Testing check_cert_expiry with missing file..."

    if ! declare -f check_cert_expiry >/dev/null 2>&1; then
        test_result "check_cert_expiry defined" "fail"
        return
    fi

    if check_cert_expiry "/tmp/nonexistent-cert-$$.pem" 2>/dev/null; then
        test_result "check_cert_expiry rejects missing file" "fail"
    else
        test_result "check_cert_expiry rejects missing file" "pass"
    fi
}

test_check_cert_expiry_invalid_file() {
    echo ""
    echo "Testing check_cert_expiry with invalid file..."

    if ! declare -f check_cert_expiry >/dev/null 2>&1; then
        test_result "check_cert_expiry defined" "fail"
        return
    fi

    local temp_file
    temp_file=$(mktemp)
    echo "not a certificate" > "$temp_file"

    if check_cert_expiry "$temp_file" 2>/dev/null; then
        test_result "check_cert_expiry rejects invalid file" "fail"
    else
        test_result "check_cert_expiry rejects invalid file" "pass"
    fi

    rm -f "$temp_file"
}

#==============================================================================
# maybe_issue_cert (non-destructive existence check)
#==============================================================================

test_maybe_issue_cert_defined() {
    echo ""
    echo "Checking maybe_issue_cert definition..."

    if declare -f maybe_issue_cert >/dev/null 2>&1; then
        test_result "maybe_issue_cert defined" "pass"
    else
        test_result "maybe_issue_cert defined" "fail"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/certificate.sh Helpers"
echo "=========================================="

test_check_cert_expiry_missing_file
test_check_cert_expiry_invalid_file
test_maybe_issue_cert_defined

# Print summary
echo ""
echo "=========================================="
echo "           Test Summary"
echo "=========================================="
echo "Total tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "✓ All tests passed!"
    exit 0
else
    echo ""
    echo "✗ Some tests failed"
    exit 1
fi
