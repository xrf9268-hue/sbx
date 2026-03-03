#!/usr/bin/env bash
# tests/unit/test_sbx_manager_health.sh - Validate sbx-manager health command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

setup_health_mock() {
    MOCK_DIR=$(mktemp -d /tmp/sbx-test-health.XXXXXX)
    CONFIG_FILE="$MOCK_DIR/config.json"
    CERT_FILE="$MOCK_DIR/fullchain.pem"
    : > "$CERT_FILE"

    cat >"$MOCK_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "is-active" ]]; then
    if [[ "${MOCK_SERVICE_ACTIVE:-1}" == "1" ]]; then
        exit 0
    fi
    exit 3
fi
if [[ "$1" == "show" ]]; then
    echo "1234"
    exit 0
fi
if [[ "$1" == "status" ]]; then
    if [[ "${MOCK_SERVICE_ACTIVE:-1}" == "1" ]]; then
        echo "Active: active (running)"
        exit 0
    fi
    echo "Active: inactive (dead)"
    exit 3
fi
exit 0
EOF

    cat >"$MOCK_DIR/sing-box" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "check" ]]; then
    if [[ "${MOCK_CONFIG_VALID:-1}" == "1" ]]; then
        exit 0
    fi
    echo "config invalid" >&2
    exit 1
fi
exit 0
EOF

    cat >"$MOCK_DIR/ss" <<'EOF'
#!/usr/bin/env bash
ports="${MOCK_LISTEN_PORTS:-443/tcp}"
if [[ "$*" == *"-lntp"* ]]; then
    for entry in ${ports//,/ }; do
        port="${entry%/*}"
        proto="${entry#*/}"
        [[ "$proto" == "tcp" ]] || continue
        echo "LISTEN 0 128 0.0.0.0:${port} 0.0.0.0:*"
    done
    exit 0
fi
if [[ "$*" == *"-lnup"* ]]; then
    for entry in ${ports//,/ }; do
        port="${entry%/*}"
        proto="${entry#*/}"
        [[ "$proto" == "udp" ]] || continue
        echo "UNCONN 0 0 0.0.0.0:${port} 0.0.0.0:*"
    done
    exit 0
fi
exit 0
EOF

    cat >"$MOCK_DIR/openssl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "x509" && "$*" == *"-checkend"* ]]; then
    if [[ "${MOCK_CERT_VALID:-1}" == "1" ]]; then
        exit 0
    fi
    exit 1
fi
exit 0
EOF

    chmod +x "$MOCK_DIR/systemctl" "$MOCK_DIR/sing-box" "$MOCK_DIR/ss" "$MOCK_DIR/openssl"
}

teardown_health_mock() {
    [[ -n "${MOCK_DIR:-}" && -d "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"
}

run_health() {
    local config_path="$1"
    set +e
    HEALTH_OUTPUT=$(PATH="$MOCK_DIR:$PATH" \
      SBX_BIN="$MOCK_DIR/sing-box" \
      SBX_CONFIG_PATH="$config_path" \
      bash "$PROJECT_ROOT/bin/sbx-manager.sh" health 2>&1)
    HEALTH_EXIT_CODE=$?
}

write_healthy_config() {
    cat >"$CONFIG_FILE" <<'EOF'
{
  "inbounds": [
    {"tag": "in-reality", "type": "vless", "listen_port": 443},
    {"tag": "in-ws", "type": "vless", "listen_port": 8444},
    {"tag": "in-hy2", "type": "hysteria2", "listen_port": 8443}
  ],
  "outbounds": [{"type": "direct"}],
  "route": {"rules": []}
}
EOF
}

write_warn_config() {
    cat >"$CONFIG_FILE" <<EOF
{
  "inbounds": [
    {"tag": "in-reality", "type": "vless", "listen_port": 443, "sniff": true},
    {"tag": "in-ws", "type": "vless", "listen_port": 8444, "tls": {"certificate_path": "${CERT_FILE}"}}
  ],
  "outbounds": [{"type": "direct"}],
  "route": {"rules": []}
}
EOF
}

test_health_command_behaviors() {
    echo "Testing sbx-manager health command..."

    # Scenario 1: healthy environment
    write_healthy_config
    export MOCK_SERVICE_ACTIVE=1
    export MOCK_CONFIG_VALID=1
    export MOCK_LISTEN_PORTS="443/tcp,8444/tcp,8443/udp"
    export MOCK_CERT_VALID=1

    run_health "$CONFIG_FILE"

    assert_equals "0" "$HEALTH_EXIT_CODE" "health should exit 0 when all checks pass"
    assert_contains "$HEALTH_OUTPUT" "[OK] Service: active" "health reports service active"
    assert_contains "$HEALTH_OUTPUT" "[OK] Config: valid" "health reports config valid"
    assert_contains "$HEALTH_OUTPUT" "Port 443/tcp" "health checks configured TCP ports"
    assert_contains "$HEALTH_OUTPUT" "Health result: PASS" "health reports overall PASS"

    # Scenario 2: failing environment
    write_healthy_config
    export MOCK_SERVICE_ACTIVE=0
    export MOCK_CONFIG_VALID=0
    export MOCK_LISTEN_PORTS=""
    export MOCK_CERT_VALID=1

    run_health "$CONFIG_FILE"

    assert_equals "1" "$HEALTH_EXIT_CODE" "health should exit 1 when failures exist"
    assert_contains "$HEALTH_OUTPUT" "[FAIL] Service: inactive" "health reports inactive service failure"
    assert_contains "$HEALTH_OUTPUT" "[FAIL] Config: invalid" "health reports config validation failure"
    assert_contains "$HEALTH_OUTPUT" "Health result: FAIL" "health reports overall FAIL"

    # Scenario 3: warning-only environment (deprecated field + cert expiry warning)
    write_warn_config
    export MOCK_SERVICE_ACTIVE=1
    export MOCK_CONFIG_VALID=1
    export MOCK_LISTEN_PORTS="443/tcp,8444/tcp"
    export MOCK_CERT_VALID=0

    run_health "$CONFIG_FILE"

    assert_equals "0" "$HEALTH_EXIT_CODE" "health should exit 0 for warning-only report"
    assert_contains "$HEALTH_OUTPUT" "[WARN] Certificate:" "health warns for certificate expiry window"
    assert_contains "$HEALTH_OUTPUT" "[WARN] Deprecated fields detected" "health warns for deprecated config fields"
    assert_contains "$HEALTH_OUTPUT" "Health result: PASS (with warnings)" "health reports warning-only PASS state"

    # Scenario 4: usage includes health command
    local help_output
    help_output=$(bash "$PROJECT_ROOT/bin/sbx-manager.sh" help 2>&1)
    assert_contains "$help_output" "health" "help output includes health command"
}

main() {
    # Disable strict mode to allow assertion tracking
    set +e

    run_test_suite "sbx-manager health command behaviors" setup_health_mock test_health_command_behaviors teardown_health_mock
    print_test_summary
}

main "$@"
