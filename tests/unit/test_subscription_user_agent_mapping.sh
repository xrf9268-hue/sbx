#!/usr/bin/env bash
# tests/unit/test_subscription_user_agent_mapping.sh
# Pure-bash table test of the User-Agent -> format mapping helper in
# lib/subscription.sh::_subscription_pick_format. No Python required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

# Isolate potential readonly constants in common.sh by running the source
# in the current shell (safe: common.sh is idempotent).
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/subscription.sh"

test_ua_mapping() {
  # Clash family -> clash
  assert_equals "clash" "$(_subscription_pick_format 'ClashMetaForAndroid/2.10.9')" "ClashMeta -> clash"
  assert_equals "clash" "$(_subscription_pick_format 'Mihomo/1.18')" "Mihomo -> clash"
  assert_equals "clash" "$(_subscription_pick_format 'Stash/2.6.0')" "Stash -> clash"
  assert_equals "clash" "$(_subscription_pick_format 'clash.meta')" "clash.meta -> clash"

  # Shadowrocket / Quantumult / Surge / Loon -> uri
  assert_equals "uri" "$(_subscription_pick_format 'Shadowrocket/2.2.32 CFNetwork/1410')" "Shadowrocket -> uri"
  assert_equals "uri" "$(_subscription_pick_format 'Quantumult%20X/1.0.30')" "Quantumult X -> uri"
  assert_equals "uri" "$(_subscription_pick_format 'Surge iOS/2700')" "Surge -> uri"
  assert_equals "uri" "$(_subscription_pick_format 'Loon/714')" "Loon -> uri"

  # Default / V2Ray family -> base64
  assert_equals "base64" "$(_subscription_pick_format 'v2rayN/6.42')" "v2rayN -> base64"
  assert_equals "base64" "$(_subscription_pick_format 'V2rayNG/1.8.17')" "V2rayNG -> base64"
  assert_equals "base64" "$(_subscription_pick_format 'NekoBox/1.2.7')" "NekoBox -> base64"
  assert_equals "base64" "$(_subscription_pick_format 'Mozilla/5.0')" "Generic browser -> base64"
  assert_equals "base64" "$(_subscription_pick_format '')" "Empty UA -> base64"
}

main() {
  set +e
  echo "Running: subscription user-agent mapping"
  test_ua_mapping
  print_test_summary
}

main "$@"
