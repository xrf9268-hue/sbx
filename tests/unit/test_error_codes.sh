#!/usr/bin/env bash
# tests/unit/test_error_codes.sh - Validate structured error code behavior

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

test_die_with_code_function_exists() {
    grep -q '^die_with_code() {' "${PROJECT_ROOT}/lib/logging.sh"
}

test_die_with_code_text_output() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/lib/colors.sh"
      source "'"${PROJECT_ROOT}"'/lib/logging.sh"
      die_with_code "SBX-CONFIG-001" "Invalid domain" "Use a public FQDN" "DOMAIN=example.com bash install.sh"
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] \
      && [[ "${output}" == *"SBX-CONFIG-001"* ]] \
      && [[ "${output}" == *"Reason: Invalid domain"* ]] \
      && [[ "${output}" == *"Resolution: Use a public FQDN"* ]] \
      && [[ "${output}" == *"Example: DOMAIN=example.com bash install.sh"* ]]
}

test_die_with_code_json_output() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/lib/colors.sh"
      source "'"${PROJECT_ROOT}"'/lib/logging.sh"
      export LOG_FORMAT=json
      die_with_code "SBX-NETWORK-001" "Download failed" "Check outbound network" "curl -I https://github.com"
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] \
      && [[ "${output}" == *'"code":"SBX-NETWORK-001"'* ]] \
      && [[ "${output}" == *'"reason":"Download failed"'* ]]
}

test_download_singbox_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/install.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      create_temp_dir() { mktemp -d /tmp/sbx-test-dl.XXXXXX; }
      resolve_singbox_version() { return 1; }
      download_singbox
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-DOWNLOAD-001"* ]]
}

test_config_validation_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/lib/config.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      export CERT_MODE=cf_dns
      export DOMAIN=example.com
      export ENABLE_WS=0
      export ENABLE_HY2=0
      unset CF_API_TOKEN || true
      _validate_certificate_config "" ""
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-CERT-001"* ]]
}

test_service_setup_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/lib/service.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      create_service_file() { return 1; }
      setup_service
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-SERVICE-001"* ]]
}

test_export_load_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      tmp=$(mktemp -d /tmp/sbx-test-export.XXXXXX)
      export TEST_STATE_FILE="${tmp}/missing-state.json"
      export TEST_CLIENT_INFO="${tmp}/missing-client-info.txt"
      source "'"${PROJECT_ROOT}"'/lib/export.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      load_client_info
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-EXPORT-021"* ]]
}

test_backup_restore_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      tmp=$(mktemp -d /tmp/sbx-test-error-codes.XXXXXX)
      export SBX_LOCK_FILE="${tmp}/sbx.lock"
      source "'"${PROJECT_ROOT}"'/lib/backup.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      backup_restore /tmp/sbx-missing-backup.tar.gz
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-BACKUP-017"* ]]
}

test_install_server_ip_detection_uses_structured_code() {
    local output=''
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/install.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      export AUTO_INSTALL=1
      unset DOMAIN || true
      get_public_ip() { return 1; }
      _configure_server_address
    ' 2>&1)
    local rc=$?
    set -e

    [[ ${rc} -ne 0 ]] && [[ "${output}" == *"SBX-NETWORK-002"* ]]
}

main() {
    echo "=========================================="
    echo "Structured Error Code Unit Tests"
    echo "=========================================="

    run_test "die_with_code function exists" test_die_with_code_function_exists
    run_test "die_with_code text output includes remediation" test_die_with_code_text_output
    run_test "die_with_code emits machine-readable JSON" test_die_with_code_json_output
    run_test "download_singbox emits structured code on version failure" test_download_singbox_uses_structured_code
    run_test "config certificate validation emits structured code" test_config_validation_uses_structured_code
    run_test "service setup emits structured code on create failure" test_service_setup_uses_structured_code
    run_test "export loader emits structured code on missing client info" test_export_load_uses_structured_code
    run_test "backup restore emits structured code on missing archive" test_backup_restore_uses_structured_code
    run_test "install IP detection emits structured code on failure" test_install_server_ip_detection_uses_structured_code

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
