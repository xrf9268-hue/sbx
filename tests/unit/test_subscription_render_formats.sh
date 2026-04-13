#!/usr/bin/env bash
# tests/unit/test_subscription_render_formats.sh
# Exercises subscription_render for base64, uri, and clash formats using
# a fixture state.json (TEST_STATE_FILE override).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
STATE_FILE_PATH=""

setup_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-sub-render.XXXXXX)
  STATE_FILE_PATH="${TEST_TMP}/state.json"

  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-01T00:00:00Z",
  "mode": "multi_protocol",
  "server": {
    "domain": "example.com",
    "ip": null
  },
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "public_key": "pubkey_fixture",
      "short_id": "cafebabe",
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
      "password": "hy2pass_fixture",
      "port_range": null
    },
    "tuic": {
      "enabled": true,
      "port": 8445,
      "password": "tuicpass_fixture"
    },
    "trojan": {
      "enabled": false,
      "port": null,
      "password": null
    }
  },
  "subscription": {
    "enabled": false,
    "port": 8838,
    "bind": "127.0.0.1",
    "token": "",
    "path": "/sub",
    "created_at": null
  }
}
EOF
  chmod 600 "${STATE_FILE_PATH}"
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

_run_render() {
  local fmt="$1"
  TEST_STATE_FILE="${STATE_FILE_PATH}" \
    TEST_CLIENT_INFO="${TEST_TMP}/nope" \
    bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      source '${PROJECT_ROOT}/lib/subscription.sh'
      subscription_render '${fmt}'
    "
}

test_render_uri() {
  local out=''
  out=$(_run_render uri)
  assert_contains "${out}" "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443" "uri contains reality URI"
  assert_contains "${out}" "pbk=pubkey_fixture" "uri contains reality public key"
  assert_contains "${out}" "hysteria2://hy2pass_fixture@example.com:8443" "uri contains hysteria2 URI"
  assert_contains "${out}" "tuic://" "uri contains tuic URI"
  # Trojan is disabled in fixture
  case "${out}" in
    *trojan://*) assert_equals "missing" "present" "uri must not contain trojan when disabled" ;;
    *) assert_equals "0" "0" "uri correctly omits disabled trojan" ;;
  esac
}

test_render_base64() {
  local out='' decoded=''
  out=$(_run_render base64)
  # Base64 output must not contain whitespace or protocol schemes directly
  case "${out}" in
    *vless://*) assert_equals "encoded" "raw" "base64 output must be encoded, not raw" ;;
    *) assert_equals "0" "0" "base64 output is encoded (no raw vless://)" ;;
  esac
  decoded=$(printf '%s' "${out}" | base64 -d 2>/dev/null || true)
  assert_contains "${decoded}" "vless://" "base64 decodes to reality URI"
  assert_contains "${decoded}" "hysteria2://" "base64 decodes to hysteria2 URI"
}

test_render_clash() {
  local out=''
  out=$(_run_render clash)
  assert_contains "${out}" "proxies:" "clash yaml has proxies key"
  assert_contains "${out}" "type: vless" "clash yaml has vless proxy type"
  assert_contains "${out}" "pubkey_fixture" "clash yaml references public key"
  assert_contains "${out}" "proxy-groups:" "clash yaml has proxy-groups key"
  assert_contains "${out}" "sbx-reality-example.com" "clash yaml names reality proxy"
}

main() {
  set +e
  setup_fixture
  echo "Running: subscription_render formats"
  test_render_uri
  test_render_base64
  test_render_clash
  teardown_fixture
  print_test_summary
}

main "$@"
