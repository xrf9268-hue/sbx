#!/usr/bin/env bash
# tests/unit/test_install_state_persistence.sh - Validate install state.json persistence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

TEST_TMP=""

setup_state_persistence_fixture() {
    TEST_TMP=$(mktemp -d /tmp/sbx-install-state.XXXXXX)
}

teardown_state_persistence_fixture() {
    [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

test_save_client_info_creates_parent_dir() {
    local output='' rc=0
    set +e
    output=$(bash -c '
      msg() { :; }
      success() { :; }

      source <(sed -n "/^save_client_info()/,/^}/p" "'"${PROJECT_ROOT}"'/install.sh")

      export CLIENT_INFO="'"${TEST_TMP}"'/nested/client-info.txt"
      export SECURE_FILE_PERMISSIONS=600
      export DOMAIN="1.1.1.1"
      export UUID="11111111-2222-3333-4444-555555555555"
      export PUB="pubkey123"
      export SID="abcd1234"
      export SNI="www.microsoft.com"
      export SNI_DEFAULT="www.microsoft.com"
      export REALITY_PORT_CHOSEN=443
      export REALITY_ONLY_MODE=1

      save_client_info
      test -f "${CLIENT_INFO}"
      sed -n "1,10p" "${CLIENT_INFO}"
    ' 2>&1)
    rc=$?

    assert_equals "0" "${rc}" "save_client_info succeeds when parent directory is missing"
    assert_file_exists "${TEST_TMP}/nested/client-info.txt" "client-info.txt is created in nested directory"
    assert_contains "${output}" 'DOMAIN="1.1.1.1"' "client-info.txt stores the selected domain"
}

test_save_state_info_writes_json() {
    local output='' rc=0
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/install.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      export TEST_STATE_FILE="'"${TEST_TMP}"'/state.json"
      export DOMAIN="example.com"
      export REALITY_ONLY_MODE=0
      export UUID="11111111-2222-3333-4444-555555555555"
      export PUB="pubkey123"
      export SID="abcd1234"
      export SNI="www.microsoft.com"
      export REALITY_PORT_CHOSEN=443
      export WS_PORT_CHOSEN=8444
      export HY2_PORT_CHOSEN=8443
      export HY2_PASS="hy2pass123"
      export CERT_FULLCHAIN="/tmp/fake-fullchain.pem"
      export CERT_KEY="/tmp/fake-key.pem"
      save_state_info
      jq -r ".protocols.reality.public_key" "${TEST_STATE_FILE}"
    ' 2>&1)
    rc=$?

    assert_equals "0" "${rc}" "save_state_info command succeeds"
    assert_file_exists "${TEST_TMP}/state.json" "state.json is created"
    assert_contains "${output}" "pubkey123" "state.json stores reality public key"
}

test_save_state_info_acme_marks_ws_hy2_enabled() {
    local output='' rc=0
    set +e
    output=$(bash -c '
      source "'"${PROJECT_ROOT}"'/install.sh" >/dev/null 2>&1
      trap - EXIT INT TERM HUP QUIT ERR RETURN
      export TEST_STATE_FILE="'"${TEST_TMP}"'/state-acme.json"
      export DOMAIN="example.com"
      export REALITY_ONLY_MODE=0
      export ENABLE_WS=1
      export ENABLE_HY2=1
      export UUID="11111111-2222-3333-4444-555555555555"
      export PUB="pubkey123"
      export SID="abcd1234"
      export SNI="www.microsoft.com"
      export REALITY_PORT_CHOSEN=443
      export WS_PORT_CHOSEN=8444
      export HY2_PORT_CHOSEN=8443
      export HY2_PASS="hy2pass123"
      export CERT_FULLCHAIN=""
      export CERT_KEY=""
      save_state_info
      jq -r ".protocols.ws_tls.enabled, .protocols.ws_tls.port, .protocols.hysteria2.enabled, .protocols.hysteria2.port" "${TEST_STATE_FILE}"
    ' 2>&1)
    rc=$?

    assert_equals "0" "${rc}" "save_state_info ACME scenario succeeds"
    assert_file_exists "${TEST_TMP}/state-acme.json" "ACME state.json is created"
    assert_contains "${output}" $'true\n8444\ntrue\n8443' "ACME state marks ws/hy2 enabled with ports"
}

main() {
    set +e
    run_test_suite "install client info persistence" setup_state_persistence_fixture test_save_client_info_creates_parent_dir teardown_state_persistence_fixture
    run_test_suite "install state persistence" setup_state_persistence_fixture test_save_state_info_writes_json teardown_state_persistence_fixture
    run_test_suite "install state persistence (acme ws/hy2)" setup_state_persistence_fixture test_save_state_info_acme_marks_ws_hy2_enabled teardown_state_persistence_fixture
    print_test_summary
}

main "$@"
