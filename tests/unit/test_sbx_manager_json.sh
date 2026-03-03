#!/usr/bin/env bash
# tests/unit/test_sbx_manager_json.sh - Validate --json output for sbx-manager commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

setup_json_mock() {
    MOCK_DIR=$(mktemp -d /tmp/sbx-test-json.XXXXXX)
    LIB_DIR_STUB="${MOCK_DIR}/lib"
    BACKUP_DIR_STUB="${MOCK_DIR}/backups"
    CONFIG_FILE="${MOCK_DIR}/config.json"
    CLIENT_INFO_FILE="${MOCK_DIR}/client-info.txt"
    CERT_FILE="${MOCK_DIR}/fullchain.pem"
    : > "${CERT_FILE}"
    mkdir -p "${LIB_DIR_STUB}" "${BACKUP_DIR_STUB}"

    cat >"${CLIENT_INFO_FILE}" <<'EOF'
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="pubkey123"
SHORT_ID="abcd1234"
SNI="www.microsoft.com"
REALITY_PORT="443"
WS_PORT="8444"
HY2_PORT="8443"
HY2_PASS="hy2pass123"
CERT_FULLCHAIN="/tmp/fake-fullchain.pem"
CERT_KEY="/tmp/fake-key.pem"
EOF
    chmod 600 "${CLIENT_INFO_FILE}"

    cat >"${CONFIG_FILE}" <<EOF
{
  "inbounds": [
    {"tag": "in-reality", "type": "vless", "listen_port": 443},
    {"tag": "in-ws", "type": "vless", "listen_port": 8444, "tls": {"certificate_path": "${CERT_FILE}"}},
    {"tag": "in-hy2", "type": "hysteria2", "listen_port": 8443}
  ],
  "outbounds": [{"type": "direct"}],
  "route": {"rules": []}
}
EOF

    # Minimal modules for sbx-manager loading
    cat >"${LIB_DIR_STUB}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

    cat >"${LIB_DIR_STUB}/export.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
load_client_info() {
  source "${TEST_CLIENT_INFO:?}"
  REALITY_PORT="${REALITY_PORT:-443}"
  SNI="${SNI:-www.microsoft.com}"
  WS_PORT="${WS_PORT:-8444}"
  HY2_PORT="${HY2_PORT:-8443}"
}
export_uri() {
  case "${1:-all}" in
    reality) echo "vless://reality-uri" ;;
    ws) echo "vless://ws-uri" ;;
    hy2) echo "hysteria2://hy2-uri" ;;
    *) echo "vless://all-uri" ;;
  esac
}
EOF

    cat >"${LIB_DIR_STUB}/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
backup_create() { :; }
backup_list() { :; }
backup_restore() { :; }
backup_cleanup() { :; }
EOF

    chmod +x "${LIB_DIR_STUB}/common.sh" "${LIB_DIR_STUB}/export.sh" "${LIB_DIR_STUB}/backup.sh"

    # backup list fixtures
    touch "${BACKUP_DIR_STUB}/sbx-backup-20260101-010101.tar.gz"
    touch "${BACKUP_DIR_STUB}/sbx-backup-20260102-010101.tar.gz.enc"

    # Mock binaries
    cat >"${MOCK_DIR}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "is-active" ]]; then
  [[ "${MOCK_SERVICE_ACTIVE:-1}" == "1" ]] && exit 0 || exit 3
fi
if [[ "$1" == "show" ]]; then
  echo "1234"
  exit 0
fi
if [[ "$1" == "status" ]]; then
  [[ "${MOCK_SERVICE_ACTIVE:-1}" == "1" ]] && echo "Active: active (running)" || echo "Active: inactive (dead)"
  [[ "${MOCK_SERVICE_ACTIVE:-1}" == "1" ]] && exit 0 || exit 3
fi
exit 0
EOF

    cat >"${MOCK_DIR}/sing-box" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "check" ]]; then
  [[ "${MOCK_CONFIG_VALID:-1}" == "1" ]] && exit 0 || exit 1
fi
exit 0
EOF

    cat >"${MOCK_DIR}/ss" <<'EOF'
#!/usr/bin/env bash
ports="${MOCK_LISTEN_PORTS:-443/tcp,8444/tcp,8443/udp}"
if [[ "$*" == *"-lntp"* ]]; then
  for entry in ${ports//,/ }; do
    p="${entry%/*}"
    proto="${entry#*/}"
    [[ "$proto" == "tcp" ]] || continue
    echo "LISTEN 0 128 0.0.0.0:${p} 0.0.0.0:*"
  done
  exit 0
fi
if [[ "$*" == *"-lnup"* ]]; then
  for entry in ${ports//,/ }; do
    p="${entry%/*}"
    proto="${entry#*/}"
    [[ "$proto" == "udp" ]] || continue
    echo "UNCONN 0 0 0.0.0.0:${p} 0.0.0.0:*"
  done
  exit 0
fi
exit 0
EOF

    cat >"${MOCK_DIR}/openssl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "x509" && "$*" == *"-checkend"* ]]; then
  [[ "${MOCK_CERT_VALID:-1}" == "1" ]] && exit 0 || exit 1
fi
exit 0
EOF

    chmod +x "${MOCK_DIR}/systemctl" "${MOCK_DIR}/sing-box" "${MOCK_DIR}/ss" "${MOCK_DIR}/openssl"
}

teardown_json_mock() {
    [[ -n "${MOCK_DIR:-}" && -d "${MOCK_DIR}" ]] && rm -rf "${MOCK_DIR}"
}

run_sbx_json() {
    local cmd=("$@")
    PATH="${MOCK_DIR}:$PATH" \
    LIB_DIR="${LIB_DIR_STUB}" \
    TEST_CLIENT_INFO="${CLIENT_INFO_FILE}" \
    SBX_BIN="${MOCK_DIR}/sing-box" \
    SBX_CONFIG_PATH="${CONFIG_FILE}" \
    BACKUP_DIR="${BACKUP_DIR_STUB}" \
    bash "${PROJECT_ROOT}/bin/sbx-manager.sh" "${cmd[@]}"
}

test_json_output_commands() {
    echo "Testing --json command outputs..."

    export MOCK_SERVICE_ACTIVE=1
    export MOCK_CONFIG_VALID=1
    export MOCK_CERT_VALID=1
    export MOCK_LISTEN_PORTS="443/tcp,8444/tcp,8443/udp"

    # info --json
    info_json=$(run_sbx_json info --json 2>/dev/null)
    assert_success "printf '%s' \"\$info_json\" | jq empty" "info --json returns valid JSON"
    assert_equals "info" "$(echo "$info_json" | jq -r '.command')" "info --json includes command field"
    assert_equals "vless://reality-uri" "$(echo "$info_json" | jq -r '.protocols.reality.uri')" "info --json includes reality URI"

    # --json status (global flag form)
    status_json=$(run_sbx_json --json status 2>/dev/null)
    assert_success "printf '%s' \"\$status_json\" | jq empty" "status --json returns valid JSON"
    assert_equals "true" "$(echo "$status_json" | jq -r '.active')" "status --json includes active=true"
    assert_equals "1234" "$(echo "$status_json" | jq -r '.pid')" "status --json includes pid"

    # health --json
    health_json=$(run_sbx_json health --json 2>/dev/null)
    assert_success "printf '%s' \"\$health_json\" | jq empty" "health --json returns valid JSON"
    assert_equals "health" "$(echo "$health_json" | jq -r '.command')" "health --json includes command field"
    assert_equals "pass" "$(echo "$health_json" | jq -r '.overall')" "health --json includes overall=pass"

    # check --json
    check_json=$(run_sbx_json check --json 2>/dev/null)
    assert_success "printf '%s' \"\$check_json\" | jq empty" "check --json returns valid JSON"
    assert_equals "true" "$(echo "$check_json" | jq -r '.valid')" "check --json includes valid=true"

    # backup list --json
    backup_json=$(run_sbx_json backup list --json 2>/dev/null)
    assert_success "printf '%s' \"\$backup_json\" | jq empty" "backup list --json returns valid JSON"
    assert_equals "2" "$(echo "$backup_json" | jq -r '.count')" "backup list --json includes backup count"
    assert_equals "true" "$(echo "$backup_json" | jq -r '.backups | any(.encrypted == true)')" "backup list --json includes encrypted entry"
}

main() {
    # Disable strict mode to allow assertion tracking
    set +e

    run_test_suite "sbx-manager --json outputs" setup_json_mock test_json_output_commands teardown_json_mock
    print_test_summary
}

main "$@"
