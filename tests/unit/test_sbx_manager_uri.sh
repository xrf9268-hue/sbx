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
  cat >"$path" <<'EOF'
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
}

create_stub_lib() {
  local lib_dir="$1"
  mkdir -p "$lib_dir"
  cat >"${lib_dir}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

  cat >"${lib_dir}/export.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export_uri() {
  echo "stub-${1:-all}"
}
load_client_info() {
  source "${TEST_CLIENT_INFO:?}"
  REALITY_PORT="${REALITY_PORT:-443}"
  SNI="${SNI:-www.microsoft.com}"
  WS_PORT="${WS_PORT:-8444}"
  HY2_PORT="${HY2_PORT:-8443}"
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
  cat >"$TEST_TMP_DIR/bin/qrencode" <<'EOF'
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

  LIB_DIR="$stub_lib" TEST_CLIENT_INFO="$client_info" PATH="$TEST_TMP_DIR/bin:$PATH" bash "$PROJECT_ROOT/bin/sbx-manager.sh" qr >/dev/null 2>&1 || true

  if [[ -f "$QR_LOG" ]] && grep -q "stub-reality" "$QR_LOG"; then
    pass "qr command uses export_uri path"
  else
    fail "qr command should delegate to export_uri" "qrencode log missing stub URI"
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

echo ""
echo "=========================================="
echo "Running test suite: sbx-manager URI paths"
echo "=========================================="

test_stubbed_export_uri_used_in_info_and_qr
test_cli_uri_matches_export_module

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
