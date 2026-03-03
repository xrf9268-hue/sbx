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

main() {
    set +e
    run_test_suite "install state persistence" setup_state_persistence_fixture test_save_state_info_writes_json teardown_state_persistence_fixture
    print_test_summary
}

main "$@"
