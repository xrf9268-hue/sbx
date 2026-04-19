#!/usr/bin/env bash
# tests/unit/test_sbx_manager_uri.sh - Validate sbx-manager URI generation paths

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TEST_TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Disable immediate exit to allow manual assertions
set +e

pass() {
  local name="$1"
  ((TESTS_RUN++))
  ((TESTS_PASSED++))
  echo "  ✓ $name"
}

fail() {
  local name="$1"
  local msg="${2:-}"
  ((TESTS_RUN++))
  ((TESTS_FAILED++))
  echo "  ✗ $name"
  [[ -n "$msg" ]] && echo "    $msg"
}

create_client_info() {
  local path="$1"
  cat > "$path" << 'EOF'
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="pubkey123"
SHORT_ID="abcd1234"
REALITY_PORT="443"
SNI="www.microsoft.com"
WS_PORT="8444"
HY2_PORT="8443"
HY2_PASS="pass123"
TUIC_PORT="8445"
TUIC_PASS="tuicpass123"
TROJAN_PORT="8446"
TROJAN_PASS="trojanpass123"
CERT_FULLCHAIN="/tmp/fullchain.pem"
CERT_KEY="/tmp/key.pem"
EOF
  # Security check requires 600 permissions
  chmod 600 "$path"
}

create_stub_lib() {
  local lib_dir="$1"
  mkdir -p "$lib_dir"
  cat > "${lib_dir}/common.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

  cat > "${lib_dir}/export.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
export_uri() {
  case "${1:-all}" in
    tuic)
      [[ -n "${TUIC_PORT:-}" && -n "${TUIC_PASS:-}" ]] || return 46
      echo "stub-tuic"
      ;;
    trojan)
      [[ -n "${TROJAN_PORT:-}" && -n "${TROJAN_PASS:-}" ]] || return 47
      echo "stub-trojan"
      ;;
    *)
      echo "stub-${1:-all}"
      ;;
  esac
}
load_client_info() {
  source "${TEST_CLIENT_INFO:?}"
  if [[ -n "${REALITY_PORT:-}" ]]; then
    REALITY_ENABLED="true"
    REALITY_PORT="${REALITY_PORT:-443}"
    SNI="${SNI:-www.microsoft.com}"
  else
    REALITY_ENABLED="false"
  fi
  if [[ -n "${WS_PORT:-}" ]]; then
    WS_ENABLED="true"
    WS_PORT="${WS_PORT:-8444}"
  else
    WS_ENABLED="false"
  fi
  if [[ -n "${HY2_PORT:-}" || -n "${HY2_PASS:-}" ]]; then
    HY2_ENABLED="true"
    HY2_PORT="${HY2_PORT:-8443}"
  else
    HY2_ENABLED="false"
  fi
  if [[ -n "${TUIC_PORT:-}" || -n "${TUIC_PASS:-}" ]]; then
    TUIC_ENABLED="true"
  else
    TUIC_ENABLED="false"
  fi
  if [[ -n "${TROJAN_PORT:-}" || -n "${TROJAN_PASS:-}" ]]; then
    TROJAN_ENABLED="true"
    TROJAN_PORT="${TROJAN_PORT:-8446}"
  else
    TROJAN_ENABLED="false"
  fi
}
EOF
}

create_non_tuic_client_info() {
  local path="$1"
  cat > "$path" << 'EOF'
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="pubkey123"
SHORT_ID="abcd1234"
REALITY_PORT="443"
SNI="www.microsoft.com"
WS_PORT="8444"
HY2_PORT="8443"
HY2_PASS="pass123"
CERT_FULLCHAIN="/tmp/fullchain.pem"
CERT_KEY="/tmp/key.pem"
EOF
  chmod 600 "$path"
}

create_acme_client_info() {
  local path="$1"
  cat > "$path" << 'EOF'
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="pubkey123"
SHORT_ID="abcd1234"
REALITY_PORT="443"
SNI="www.microsoft.com"
WS_PORT="8444"
HY2_PORT="8443"
HY2_PASS="pass123"
TUIC_PORT="8445"
TUIC_PASS="tuicpass123"
WS_ENABLED="true"
HY2_ENABLED="true"
TUIC_ENABLED="true"
EOF
  chmod 600 "$path"
}

create_state_info() {
  local path="$1"
  cat > "$path" << 'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-01T00:00:00Z",
  "mode": "multi_protocol",
  "server": {"domain": "example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "public_key": "pubkey123",
      "short_id": "abcd1234",
      "sni": "www.microsoft.com"
    },
    "ws_tls": {"enabled": true, "port": 8444, "certificate": null, "key": null},
    "hysteria2": {
      "enabled": true,
      "port": 8443,
      "password": "pass123",
      "port_range": null
    },
    "tuic": {"enabled": false, "port": null, "password": null},
    "trojan": {"enabled": false, "port": null, "password": null}
  },
  "subscription": {
    "enabled": true,
    "port": 8838,
    "bind": "127.0.0.1",
    "token": "deadbeefdeadbeefdeadbeefdeadbeef",
    "path": "/sub",
    "created_at": "2026-04-01T00:00:00Z"
  }
}
EOF
}

test_stubbed_export_uri_used_in_info_and_qr() {
  echo ""
  echo "Test: sbx-manager uses export_uri hook"

  local client_info="$TEST_TMP_DIR/client-info.txt"
  create_client_info "$client_info"

  local stub_lib="$TEST_TMP_DIR/lib"
  create_stub_lib "$stub_lib"

  mkdir -p "$TEST_TMP_DIR/bin"
  cat > "$TEST_TMP_DIR/bin/qrencode" << 'EOF'
#!/usr/bin/env bash
echo "$@" >>"$QR_LOG"
EOF
  chmod +x "$TEST_TMP_DIR/bin/qrencode"
  export QR_LOG="$TEST_TMP_DIR/qrencode.log"

  local info_output
  info_output=$(LIB_DIR="$stub_lib" TEST_CLIENT_INFO="$client_info" PATH="$TEST_TMP_DIR/bin:$PATH" bash "$PROJECT_ROOT/bin/sbx-manager.sh" info)

  if echo "$info_output" | grep -q "URI       = stub-reality"; then
    pass "info command uses export_uri path"
  else
    fail "info command should delegate to export_uri" "$info_output"
  fi

  if echo "$info_output" | grep -q "stub-tuic"; then
    pass "info command prints TUIC URI when configured"
  else
    fail "info command should print TUIC URI" "$info_output"
  fi

  if echo "$info_output" | grep -q "stub-trojan"; then
    pass "info command prints Trojan URI when configured"
  else
    fail "info command should print Trojan URI" "$info_output"
  fi

  LIB_DIR="$stub_lib" TEST_CLIENT_INFO="$client_info" PATH="$TEST_TMP_DIR/bin:$PATH" bash "$PROJECT_ROOT/bin/sbx-manager.sh" qr > /dev/null 2>&1 || true

  if [[ -f "$QR_LOG" ]] && grep -q "stub-reality" "$QR_LOG"; then
    pass "qr command uses export_uri path"
  else
    fail "qr command should delegate to export_uri" "qrencode log missing stub URI"
  fi
}

test_help_lists_tuic_and_trojan_export_protocols() {
  echo ""
  echo "Test: sbx-manager help lists TUIC and Trojan export support"

  local help_output
  help_output=$(bash "$PROJECT_ROOT/bin/sbx-manager.sh" help)

  if echo "$help_output" | grep -q "reality|ws|hy2|tuic|trojan|all"; then
    pass "help output lists TUIC and Trojan for export uri"
  else
    fail "help output should list TUIC and Trojan for export uri" "$help_output"
  fi
}

test_info_skips_tuic_when_not_configured() {
  echo ""
  echo "Test: sbx-manager info skips TUIC when not configured"

  local client_info="$TEST_TMP_DIR/client-info-no-tuic.txt"
  create_non_tuic_client_info "$client_info"

  local stub_lib="$TEST_TMP_DIR/lib-no-tuic"
  create_stub_lib "$stub_lib"

  local info_output
  info_output=$(LIB_DIR="$stub_lib" TEST_CLIENT_INFO="$client_info" bash "$PROJECT_ROOT/bin/sbx-manager.sh" info)

  if echo "$info_output" | grep -q "INBOUND   : TUIC V5"; then
    fail "info command should not print TUIC section when disabled" "$info_output"
  else
    pass "info command skips TUIC section when disabled"
  fi
}

test_info_prints_acme_managed_protocols() {
  echo ""
  echo "Test: sbx-manager info prints ACME-managed protocol URIs"

  local client_info="$TEST_TMP_DIR/client-info-acme.txt"
  create_acme_client_info "$client_info"

  local stub_lib="$TEST_TMP_DIR/lib-acme"
  create_stub_lib "$stub_lib"

  local info_output
  info_output=$(LIB_DIR="$stub_lib" TEST_CLIENT_INFO="$client_info" bash "$PROJECT_ROOT/bin/sbx-manager.sh" info)

  if echo "$info_output" | grep -q "stub-ws"; then
    pass "info command prints WS URI for ACME-managed setup"
  else
    fail "info command should print WS URI for ACME-managed setup" "$info_output"
  fi

  if echo "$info_output" | grep -q "stub-hy2"; then
    pass "info command prints Hysteria2 URI for ACME-managed setup"
  else
    fail "info command should print Hysteria2 URI for ACME-managed setup" "$info_output"
  fi

  if echo "$info_output" | grep -q "stub-tuic"; then
    pass "info command prints TUIC URI for ACME-managed setup"
  else
    fail "info command should print TUIC URI for ACME-managed setup" "$info_output"
  fi
}

test_cli_uri_matches_export_module() {
  echo ""
  echo "Test: sbx-manager URIs match lib/export.sh"

  local client_info="$TEST_TMP_DIR/client-info-real.txt"
  create_client_info "$client_info"

  local info_output
  info_output=$(LIB_DIR="$PROJECT_ROOT/lib" TEST_CLIENT_INFO="$client_info" bash "$PROJECT_ROOT/bin/sbx-manager.sh" info)

  local cli_real cli_ws cli_hy2
  cli_real=$(echo "$info_output" | grep -oE 'URI       = .*Reality-[^ ]*' | sed 's/^[[:space:]]*URI[[:space:]]*=[[:space:]]*//' || true)
  cli_ws=$(echo "$info_output" | grep -oE 'URI      = vless://.*WS-TLS-[^ ]*' | sed 's/^[[:space:]]*URI[[:space:]]*=[[:space:]]*//' || true)
  cli_hy2=$(echo "$info_output" | grep -oE 'URI      = hysteria2://.*Hysteria2-[^ ]*' | sed 's/^[[:space:]]*URI[[:space:]]*=[[:space:]]*//' || true)

  local export_real export_ws export_hy2
  export_real=$(TEST_CLIENT_INFO="$client_info" bash -c "source \"$PROJECT_ROOT/lib/export.sh\"; export_uri reality")
  export_ws=$(TEST_CLIENT_INFO="$client_info" bash -c "source \"$PROJECT_ROOT/lib/export.sh\"; export_uri ws")
  export_hy2=$(TEST_CLIENT_INFO="$client_info" bash -c "source \"$PROJECT_ROOT/lib/export.sh\"; export_uri hy2")

  if [[ "$cli_real" == "$export_real" ]]; then
    pass "Reality URI matches export module"
  else
    fail "Reality URI mismatch" "cli='$cli_real' export='$export_real'"
  fi

  if [[ "$cli_ws" == "$export_ws" ]]; then
    pass "WS URI matches export module"
  else
    fail "WS URI mismatch" "cli='$cli_ws' export='$export_ws'"
  fi

  if [[ "$cli_hy2" == "$export_hy2" ]]; then
    pass "Hysteria2 URI matches export module"
  else
    fail "Hysteria2 URI mismatch" "cli='$cli_hy2' export='$export_hy2'"
  fi
}

test_hy2_uri_mport_param() {
  echo ""
  echo "Test: Hysteria2 URI includes mport when port hopping is configured"
  echo "-------------------------------------------------------------------"

  local client_info="$TEST_TMP_DIR/client-info-mport.txt"
  create_client_info "$client_info"

  # URI without port hopping should not contain mport
  local uri_no_hop=""
  uri_no_hop=$(HY2_PORT_RANGE="" TEST_CLIENT_INFO="$client_info" \
    bash -c "source \"$PROJECT_ROOT/lib/export.sh\"; export_uri hy2" 2> /dev/null) || true

  if [[ "$uri_no_hop" != *"mport"* ]]; then
    pass "HY2 URI without port hopping has no mport"
  else
    fail "HY2 URI without port hopping should not have mport" "uri='$uri_no_hop'"
  fi

  # URI with port hopping should contain mport
  local uri_with_hop=""
  uri_with_hop=$(HY2_PORT_RANGE="20000-40000" TEST_CLIENT_INFO="${client_info}" \
    bash -c "source \"$PROJECT_ROOT/lib/export.sh\"; export_uri hy2" 2> /dev/null) || true

  if [[ "$uri_with_hop" == *"mport=20000-40000"* ]]; then
    pass "HY2 URI with port hopping includes mport=20000-40000"
  else
    fail "HY2 URI with port hopping should include mport param" "uri='$uri_with_hop'"
  fi
}

test_info_accepts_group_readable_state_without_export_module() {
  echo ""
  echo "Test: sbx-manager info accepts 640 state.json without export module"

  local state_file="$TEST_TMP_DIR/state-info.json"
  create_state_info "$state_file"
  chmod 640 "$state_file"

  local stub_lib="$TEST_TMP_DIR/lib-fallback"
  mkdir -p "$stub_lib"
  cat > "${stub_lib}/common.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail
source "${PROJECT_ROOT}/lib/common.sh"
EOF
  chmod +x "${stub_lib}/common.sh"

  local output=""
  output=$(LIB_DIR="$stub_lib" TEST_STATE_FILE="$state_file" bash "$PROJECT_ROOT/bin/sbx-manager.sh" info 2>&1)
  local rc=$?

  if [[ "$rc" -eq 0 ]]; then
    pass "info command accepts 640 state.json in fallback path"
  else
    fail "info command should accept 640 state.json in fallback path" "$output"
  fi

  if echo "$output" | grep -q "example.com"; then
    pass "info command renders state-derived domain with 640 state.json"
  else
    fail "info command should render state-derived domain" "$output"
  fi
}

echo ""
echo "=========================================="
echo "Running test suite: sbx-manager URI paths"
echo "=========================================="

test_stubbed_export_uri_used_in_info_and_qr
test_help_lists_tuic_and_trojan_export_protocols
test_info_skips_tuic_when_not_configured
test_info_prints_acme_managed_protocols
test_cli_uri_matches_export_module
test_hy2_uri_mport_param
test_info_accepts_group_readable_state_without_export_module

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
