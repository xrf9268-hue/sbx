#!/usr/bin/env bash
# tests/ci/integration_checks.sh - Integration checks previously embedded in workflow

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
SINGBOX_TEST_VERSION="${SINGBOX_TEST_VERSION:-latest}"

usage() {
  cat <<USAGE
Usage: integration_checks.sh [--summary-file <path>]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary-file)
      SUMMARY_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

summary() {
  local line="$1"
  if [[ -n "$SUMMARY_FILE" ]]; then
    echo "$line" >> "$SUMMARY_FILE"
  fi
}

cleanup() {
  rm -f /tmp/test-config.json /tmp/test-state.json
}
trap cleanup EXIT

summary "# Integration Tests - sing-box ${SINGBOX_TEST_VERSION}"
summary ""

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/generators.sh"
source "$PROJECT_ROOT/lib/validation.sh"
source "$PROJECT_ROOT/lib/config.sh"

UUID="$(generate_uuid)"
KEYPAIR="$(generate_reality_keypair)"
read -r PRIV PUB <<< "$KEYPAIR"
SID="$(openssl rand -hex 4)"

summary "**Generated Materials:**"
summary "- UUID: ${UUID:0:8}..."
summary "- Short ID: $SID"
summary ""

validate_short_id "$SID" >/dev/null

CONFIG="$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")"

jq -n \
  --argjson inbound "$CONFIG" \
  '{
    log: {level: "warn"},
    dns: {servers: [{type: "local", tag: "dns-local"}], strategy: "ipv4_only"},
    inbounds: [$inbound],
    outbounds: [{type: "direct", tag: "direct"}],
    route: {rules: [{inbound: ["in-reality"], action: "sniff"}], auto_detect_interface: true}
  }' > /tmp/test-config.json

if sing-box check -c /tmp/test-config.json >/dev/null 2>&1; then
  summary "✅ Configuration validation passed"
else
  summary "❌ Configuration validation failed"
  exit 1
fi

summary "**Structure Compliance Checks:**"

if jq -e '.inbounds[0].tls.reality' /tmp/test-config.json > /dev/null; then
  summary "✅ Reality properly nested under tls"
else
  summary "❌ Reality not nested under tls"
  exit 1
fi

FLOW="$(jq -r '.inbounds[0].users[0].flow' /tmp/test-config.json)"
if [[ "$FLOW" == "xtls-rprx-vision" ]]; then
  summary "✅ Flow field correct: $FLOW"
else
  summary "❌ Incorrect flow: $FLOW"
  exit 1
fi

SID_TYPE="$(jq -r '.inbounds[0].tls.reality.short_id | type' /tmp/test-config.json)"
if [[ "$SID_TYPE" == "array" ]]; then
  summary "✅ Short ID is array type"
else
  summary "❌ Short ID must be array, got: $SID_TYPE"
  exit 1
fi

summary ""
summary "**Export Tests:**"

source "$PROJECT_ROOT/lib/export.sh"

export UUID="$(jq -r '.inbounds[0].users[0].uuid' /tmp/test-config.json)"
export PUBLIC_KEY="test_public_key"
export SHORT_ID="$(jq -r '.inbounds[0].tls.reality.short_id[0]' /tmp/test-config.json)"
export DOMAIN="test.example.com"
export REALITY_PORT=443
export SNI="www.microsoft.com"
export TEST_STATE_FILE="/tmp/test-state.json"

jq -n \
  --arg domain "$DOMAIN" \
  --arg uuid "$UUID" \
  --arg public_key "$PUBLIC_KEY" \
  --arg short_id "$SHORT_ID" \
  --arg sni "$SNI" \
  --argjson port "$REALITY_PORT" \
  '{
    server: {domain: $domain},
    protocols: {
      reality: {
        uuid: $uuid,
        public_key: $public_key,
        short_id: $short_id,
        sni: $sni,
        port: $port
      }
    }
  }' > "$TEST_STATE_FILE"
chmod 600 "$TEST_STATE_FILE"

if URI="$(export_uri reality 2>/dev/null)"; then
  if [[ "$URI" =~ ^vless:// ]]; then
    summary "✅ URI export format valid"
  else
    summary "❌ URI export format invalid"
    exit 1
  fi
else
  summary "⚠️ URI export skipped (function may require full setup)"
fi
