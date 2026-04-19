#!/usr/bin/env bash
# tests/unit/test_subscription_state_schema.sh
# Verifies:
#   1. subscription_ensure_state_block() adds a default subscription block
#      when state.json does not yet have one.
#   2. load_client_info() populates SUB_* environment variables from
#      .subscription.* when the block is present.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../test_framework.sh"

TEST_TMP=""
STATE_FILE_PATH=""
LOCK_FILE_PATH=""
STATE_LOCK_FILE_PATH=""

# A minimal legacy state.json: no `subscription` key at all.
_write_legacy_state() {
  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-01T00:00:00Z",
  "mode": "multi_protocol",
  "server": {"domain": "example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "public_key": "pubkey_fixture",
      "short_id": "cafebabe",
      "sni": "www.microsoft.com"
    },
    "ws_tls": {"enabled": false, "port": null, "certificate": null, "key": null},
    "hysteria2": {"enabled": false, "port": null, "password": null, "port_range": null},
    "tuic": {"enabled": false, "port": null, "password": null},
    "trojan": {"enabled": false, "port": null, "password": null}
  }
}
EOF
  chmod 600 "${STATE_FILE_PATH}"
}

# State with a subscription block (enabled=true with a token) to test load.
_write_state_with_subscription() {
  cat >"${STATE_FILE_PATH}" <<'EOF'
{
  "version": "1.0",
  "installed_at": "2026-04-01T00:00:00Z",
  "mode": "multi_protocol",
  "server": {"domain": "example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "public_key": "pubkey_fixture",
      "short_id": "cafebabe",
      "sni": "www.microsoft.com"
    },
    "ws_tls": {"enabled": false, "port": null, "certificate": null, "key": null},
    "hysteria2": {"enabled": false, "port": null, "password": null, "port_range": null},
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
  chmod 600 "${STATE_FILE_PATH}"
}

setup_fixture() {
  TEST_TMP=$(mktemp -d /tmp/sbx-sub-schema.XXXXXX)
  STATE_FILE_PATH="${TEST_TMP}/state.json"
  LOCK_FILE_PATH="${TEST_TMP}/sbx.lock"
  STATE_LOCK_FILE_PATH="${TEST_TMP}/sbx-state.lock"
}

teardown_fixture() {
  [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"
}

test_load_client_info_batches_state_reads() {
  _write_state_with_subscription

  local jq_bin_dir="${TEST_TMP}/bin"
  local jq_count_file="${TEST_TMP}/jq-count.log"
  local real_jq=''
  real_jq=$(command -v jq)

  mkdir -p "${jq_bin_dir}"
  cat >"${jq_bin_dir}/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '1\n' >> '${jq_count_file}'
exec '${real_jq}' "\$@"
EOF
  chmod +x "${jq_bin_dir}/jq"

  local out=''
  out=$(
    PATH="${jq_bin_dir}:${PATH}" \
      TEST_STATE_FILE="${STATE_FILE_PATH}" \
      TEST_CLIENT_INFO="${TEST_TMP}/nope" \
      bash -c "
        source '${PROJECT_ROOT}/lib/export.sh'
        load_client_info >/dev/null
        printf 'DOMAIN=%s\nSUB_ENABLED=%s\nWS_ENABLED=%s\nHY2_ENABLED=%s\nTUIC_ENABLED=%s\nTROJAN_ENABLED=%s\n' \
          \"\${DOMAIN:-}\" \"\${SUB_ENABLED:-}\" \"\${WS_ENABLED:-}\" \"\${HY2_ENABLED:-}\" \"\${TUIC_ENABLED:-}\" \"\${TROJAN_ENABLED:-}\"
      "
  )

  local jq_count='0'
  if [[ -f "${jq_count_file}" ]]; then
    jq_count=$(wc -l <"${jq_count_file}")
    jq_count="${jq_count//[[:space:]]/}"
  fi

  assert_equals "2" "${jq_count}" "load_client_info batches state.json reads into one jq extraction"
  assert_contains "${out}" "DOMAIN=example.com" "batched load preserves DOMAIN"
  assert_contains "${out}" "SUB_ENABLED=true" "batched load preserves SUB_ENABLED"
  assert_contains "${out}" "WS_ENABLED=false" "batched load preserves WS_ENABLED"
  assert_contains "${out}" "HY2_ENABLED=false" "batched load preserves HY2_ENABLED"
  assert_contains "${out}" "TUIC_ENABLED=false" "batched load preserves TUIC_ENABLED"
  assert_contains "${out}" "TROJAN_ENABLED=false" "batched load preserves TROJAN_ENABLED"
}

test_ensure_block_adds_defaults_when_missing() {
  _write_legacy_state

  TEST_STATE_FILE="${STATE_FILE_PATH}" \
    SBX_LOCK_FILE="${LOCK_FILE_PATH}" \
    SBX_STATE_LOCK_FILE="${STATE_LOCK_FILE_PATH}" \
    bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      source '${PROJECT_ROOT}/lib/subscription.sh'
      subscription_ensure_state_block
    "

  assert_success "jq -e '.subscription | type == \"object\"' '${STATE_FILE_PATH}' >/dev/null" \
    "subscription block is added to legacy state.json"
  assert_success "test -f '${STATE_LOCK_FILE_PATH}'" \
    "subscription_ensure_state_block uses test state lock file"
  assert_equals "false" "$(jq -r '.subscription.enabled' "${STATE_FILE_PATH}")" \
    "default enabled=false"
  assert_equals "8838" "$(jq -r '.subscription.port' "${STATE_FILE_PATH}")" \
    "default port=8838"
  assert_equals "127.0.0.1" "$(jq -r '.subscription.bind' "${STATE_FILE_PATH}")" \
    "default bind=127.0.0.1"
  assert_equals "/sub" "$(jq -r '.subscription.path' "${STATE_FILE_PATH}")" \
    "default path=/sub"
  assert_equals "" "$(jq -r '.subscription.token' "${STATE_FILE_PATH}")" \
    "default token is empty"
}

test_ensure_block_is_idempotent() {
  _write_state_with_subscription
  local before=''
  before=$(jq -c '.subscription' "${STATE_FILE_PATH}")

  TEST_STATE_FILE="${STATE_FILE_PATH}" \
    SBX_LOCK_FILE="${LOCK_FILE_PATH}" \
    SBX_STATE_LOCK_FILE="${STATE_LOCK_FILE_PATH}" \
    bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      source '${PROJECT_ROOT}/lib/subscription.sh'
      subscription_ensure_state_block
    "

  local after=''
  after=$(jq -c '.subscription' "${STATE_FILE_PATH}")
  assert_equals "${before}" "${after}" "existing subscription block is preserved"
}

test_load_client_info_exposes_sub_vars() {
  _write_state_with_subscription
  local out=''
  out=$(
    TEST_STATE_FILE="${STATE_FILE_PATH}" \
      TEST_CLIENT_INFO="${TEST_TMP}/nope" \
      bash -c "
        source '${PROJECT_ROOT}/lib/export.sh'
        load_client_info >/dev/null
        printf 'SUB_ENABLED=%s\nSUB_PORT=%s\nSUB_BIND=%s\nSUB_TOKEN=%s\nSUB_PATH=%s\n' \
          \"\${SUB_ENABLED:-}\" \"\${SUB_PORT:-}\" \"\${SUB_BIND:-}\" \"\${SUB_TOKEN:-}\" \"\${SUB_PATH:-}\"
      "
  )

  assert_contains "${out}" "SUB_ENABLED=true" "SUB_ENABLED populated from state.json"
  assert_contains "${out}" "SUB_PORT=8838" "SUB_PORT populated from state.json"
  assert_contains "${out}" "SUB_BIND=127.0.0.1" "SUB_BIND populated from state.json"
  assert_contains "${out}" "SUB_TOKEN=deadbeefdeadbeefdeadbeefdeadbeef" "SUB_TOKEN populated"
  assert_contains "${out}" "SUB_PATH=/sub" "SUB_PATH populated"
}

main() {
  set +e
  setup_fixture
  echo "Running: subscription state.json schema"
  test_ensure_block_adds_defaults_when_missing
  test_ensure_block_is_idempotent
  test_load_client_info_exposes_sub_vars
  test_load_client_info_batches_state_reads
  teardown_fixture
  print_test_summary
}

main "$@"
