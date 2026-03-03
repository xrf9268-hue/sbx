#!/usr/bin/env bash
# tests/ci/advanced_features_checks.sh - Advanced feature checks previously in workflow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"

usage() {
  cat <<USAGE
Usage: advanced_features_checks.sh [--summary-file <path>]
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
  rm -f /tmp/test-schema-config.json
}
trap cleanup EXIT

summary "# Advanced Features Tests"
summary ""
summary "## Version Compatibility"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/version.sh"

VERSION="$(get_singbox_version)"
summary "**Detected Version:** $VERSION"

if compare_versions "1.8.0" "1.13.0" | grep -q "1.8.0"; then
  summary "✅ Version comparison works"
else
  summary "❌ Version comparison failed"
  exit 1
fi

if version_meets_minimum "$VERSION" "1.8.0"; then
  summary "✅ Version meets minimum requirement (1.8.0+)"
else
  summary "❌ Version too old (< 1.8.0)"
  exit 1
fi

summary ""
summary "## Schema Validation"

source "$SCRIPT_DIR/lib/schema_validator.sh"
source "$SCRIPT_DIR/lib/generators.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/config.sh"

UUID="$(generate_uuid)"
KEYPAIR="$(generate_reality_keypair)"
read -r PRIV PUB <<< "$KEYPAIR"
SID="$(openssl rand -hex 4)"

CONFIG="$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")"

jq -n \
  --argjson inbound "$CONFIG" \
  '{
    log: {level: "warn"},
    dns: {servers: [{type: "local", tag: "dns-local"}], strategy: "ipv4_only"},
    inbounds: [$inbound],
    outbounds: [{type: "direct", tag: "direct"}],
    route: {rules: [], auto_detect_interface: true}
  }' > /tmp/test-schema-config.json

if validate_reality_structure /tmp/test-schema-config.json >/dev/null 2>&1; then
  summary "✅ Schema validation passed"
else
  summary "❌ Schema validation failed"
  exit 1
fi

summary ""
summary "## Integration Tests"
if bash -n "$SCRIPT_DIR/tests/integration/test_reality_connection.sh" 2>/dev/null; then
  summary "✅ Integration test script syntax valid"
else
  summary "❌ Integration test script has syntax errors"
  exit 1
fi
