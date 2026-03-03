#!/usr/bin/env bash
# Unit tests for install.sh ERR trap error context handler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
INSTALL_SH="${PROJECT_ROOT}/install.sh"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    local test_func="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "Test ${TOTAL_TESTS}: ${name}"

    if "${test_func}"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "✓ PASSED"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "✗ FAILED"
    fi
}

extract_error_handler() {
    sed -n '/^_error_handler() {/,/^}/p' "${INSTALL_SH}"
}

test_error_handler_function_exists() {
    grep -q '^_error_handler() {' "${INSTALL_SH}"
}

test_err_trap_is_registered() {
    grep -q "trap '_error_handler' ERR" "${INSTALL_SH}"
}

test_errtrace_is_enabled() {
    grep -q 'set -o errtrace' "${INSTALL_SH}"
}

test_error_handler_captures_context() {
    local handler
    handler="$(extract_error_handler)"
    echo "${handler}" | grep -q 'BASH_LINENO' \
        && echo "${handler}" | grep -q 'BASH_COMMAND' \
        && echo "${handler}" | grep -q 'FUNCNAME' \
        && echo "${handler}" | grep -q 'BASH_SOURCE'
}

test_error_handler_includes_issue_link() {
    local handler
    handler="$(extract_error_handler)"
    echo "${handler}" | grep -q 'https://github.com/xrf9268-hue/sbx/issues'
}

main() {
    echo "=========================================="
    echo "install.sh Error Handler Unit Tests"
    echo "=========================================="

    run_test "ERR handler function exists" test_error_handler_function_exists
    run_test "ERR trap is registered" test_err_trap_is_registered
    run_test "errtrace is enabled for function-level errors" test_errtrace_is_enabled
    run_test "ERR handler captures line/command/function/source context" test_error_handler_captures_context
    run_test "ERR handler includes issue reporting link" test_error_handler_includes_issue_link

    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  ${TOTAL_TESTS}"
    echo "Passed: ${PASSED_TESTS}"
    echo "Failed: ${FAILED_TESTS}"

    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        echo ""
        echo "✓ All tests passed!"
        exit 0
    fi

    echo ""
    echo "✗ Some tests failed"
    exit 1
}

main "$@"
