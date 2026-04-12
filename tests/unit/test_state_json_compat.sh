#!/usr/bin/env bash
# tests/unit/test_state_json_compat.sh - Validate state.json compatibility layer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

TEST_TMP=""
STATE_FILE=""
LIB_STUB=""

setup_state_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-state-json.XXXXXX)
  STATE_FILE="${TEST_TMP}/state.json"
  LIB_STUB="${TEST_TMP}/lib"
  mkdir -p "${LIB_STUB}"

  cat > "${STATE_FILE}" << 'EOF'
{
  "version": "1.0",
  "installed_at": "2026-03-03T00:00:00Z",
  "mode": "multi_protocol",
  "server": {
    "domain": "example.com",
    "ip": null
  },
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "public_key": "pubkey123",
      "short_id": "abcd1234",
      "sni": "www.microsoft.com"
    },
    "ws_tls": {
      "enabled": true,
      "port": 8444,
      "certificate": "/tmp/fake-fullchain.pem",
      "key": "/tmp/fake-key.pem"
    },
    "hysteria2": {
      "enabled": true,
      "port": 8443,
      "password": "hy2pass123",
      "port_range": "20000-40000"
    },
    "tuic": {
      "enabled": true,
      "port": 8445,
      "password": "tuicpass123"
    }
  }
}
EOF
  chmod 600 "${STATE_FILE}"

  cat > "${LIB_STUB}/common.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
  cat > "${LIB_STUB}/backup.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
backup_create() { :; }
backup_list() { :; }
backup_restore() { :; }
backup_cleanup() { :; }
EOF
  chmod +x "${LIB_STUB}/common.sh" "${LIB_STUB}/backup.sh"
}

teardown_state_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

test_sbx_manager_reads_state_json() {
  local output=''
  set +e
  output=$(LIB_DIR="${LIB_STUB}" TEST_STATE_FILE="${STATE_FILE}" TEST_CLIENT_INFO="${TEST_TMP}/missing-client-info.txt" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" info 2>&1)
  local rc=$?

  assert_equals "0" "${rc}" "sbx-manager info works with state.json fallback"
  assert_contains "${output}" "Domain    : example.com" "state.json provides domain"
  assert_contains "${output}" "PublicKey = pubkey123" "state.json provides reality public key"
  assert_contains "${output}" "INBOUND   : TUIC V5        8445/udp" "state.json provides tuic inbound"
}

test_export_reads_state_json() {
  local uri=''
  set +e
  uri=$(TEST_STATE_FILE="${STATE_FILE}" TEST_CLIENT_INFO="${TEST_TMP}/missing-client-info.txt" \
    bash -c "source \"${PROJECT_ROOT}/lib/export.sh\"; export_uri reality" 2>&1)
  local rc=$?

  assert_equals "0" "${rc}" "export_uri works with state.json fallback"
  assert_contains "${uri}" "vless://" "state.json export returns reality URI"
  assert_contains "${uri}" "pbk=pubkey123" "state.json export includes public key"

  local tuic_uri=''
  set +e
  tuic_uri=$(TEST_STATE_FILE="${STATE_FILE}" TEST_CLIENT_INFO="${TEST_TMP}/missing-client-info.txt" \
    bash -c "source \"${PROJECT_ROOT}/lib/export.sh\"; export_uri tuic" 2>&1)
  rc=$?

  assert_equals "0" "${rc}" "tuic export works with state.json fallback"
  assert_contains "${tuic_uri}" "tuic://" "state.json export returns tuic URI"
  assert_contains "${tuic_uri}" "tuicpass123" "state.json export includes tuic password"

  # Verify port_range field is readable from state.json
  local port_range_val=""
  port_range_val=$(jq -r '.protocols.hysteria2.port_range // empty' "${STATE_FILE}")
  assert_equals "20000-40000" "${port_range_val}" "state.json port_range field is readable"
}

main() {
  set +e
  run_test_suite "state.json compatibility" setup_state_fixture test_sbx_manager_reads_state_json teardown_state_fixture
  run_test_suite "state.json export compatibility" setup_state_fixture test_export_reads_state_json teardown_state_fixture
  print_test_summary
}

main "$@"
