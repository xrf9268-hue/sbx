#!/usr/bin/env bash
# Unit tests for lib/stats.sh — traffic statistics via Clash API.
# Mocks the HTTP layer by overriding `curl` with a shell function that
# returns canned responses, so the tests never touch the network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
export TERM="xterm"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${G}✓${N} $1"
}
fail() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "${R}✗${N} $1"
}
assert_eq() {
  local name="$1" want="$2" got="$3"
  if [[ "${want}" == "${got}" ]]; then
    pass "${name}"
  else
    fail "${name} (want=${want} got=${got})"
  fi
}
assert_jq() {
  local name="$1" json="$2" filter="$3" want="$4"
  local got=""
  got=$(echo "${json}" | jq -r "${filter}" 2>/dev/null)
  assert_eq "${name}" "${want}" "${got}"
}

# shellcheck source=../../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=../../lib/stats.sh
source "${PROJECT_ROOT}/lib/stats.sh"

#==============================================================================
# Fixtures: canned Clash API payloads keyed by path
#==============================================================================

_SECRET_FIXTURE="deadbeef0123456789abcdef0123456789abcdef0123456789abcdef0123dead"
_TMP_STATE=""
STATS_CONNECTIONS_FIXTURE="default"

_setup_state() {
  local enabled="$1"
  _TMP_STATE=$(mktemp)
  jq -n \
    --argjson enabled "${enabled}" \
    --arg secret "${_SECRET_FIXTURE}" \
    '{stats: {enabled: $enabled, bind: "127.0.0.1", port: 9090, secret: $secret}}' \
    >"${_TMP_STATE}"
  export TEST_STATE_FILE="${_TMP_STATE}"
}

_teardown_state() {
  rm -f "${_TMP_STATE}"
  unset TEST_STATE_FILE
  _TMP_STATE=""
}

# Mock curl: detects the endpoint from the positional URL argument
# and emits canned JSON. Also records the last Authorization header.
_LAST_AUTH=""
curl() {
  local url=""
  local arg
  _LAST_AUTH=""
  for arg in "$@"; do
    if [[ "${arg}" == http://* || "${arg}" == https://* ]]; then
      url="${arg}"
    fi
  done
  # Capture Authorization header for inspection
  local saw_auth=0
  for arg in "$@"; do
    if [[ "${saw_auth}" -eq 1 ]]; then
      _LAST_AUTH="${arg}"
      saw_auth=0
    fi
    if [[ "${arg}" == "-H" ]]; then
      saw_auth=1
    fi
  done

  case "${url}" in
    */traffic)
      echo '{"up":12345,"down":67890}'
      ;;
    */memory)
      echo '{"inuse":10485760,"oslimit":0}'
      ;;
    */connections)
      case "${STATS_CONNECTIONS_FIXTURE:-default}" in
        no_metadata_user_reality)
          cat <<'EOF'
{
  "downloadTotal": 4096,
  "uploadTotal":    1024,
  "connections": [
    {"upload": 100, "download": 200, "start": "2024-01-01T00:00:00Z", "rule": "",
     "metadata": {"host": "fallback.example", "destinationPort": "443", "type": "vless/in-reality"}}
  ]
}
EOF
          ;;
        *)
          cat <<'EOF'
{
  "downloadTotal": 1048576,
  "uploadTotal":    524288,
  "connections": [
    {"upload": 100, "download": 200, "start": "2024-01-01T00:00:00Z", "rule": "",
     "metadata": {"host": "a.example", "destinationPort": "443", "user": "alice", "inboundTag": "in-reality"}},
    {"upload":  50, "download":  75, "start": "2024-01-01T00:00:00Z", "rule": "",
     "metadata": {"host": "b.example", "destinationPort": "443", "user": "alice", "inboundTag": "in-reality"}},
    {"upload":  10, "download":  20, "start": "2024-01-01T00:00:00Z", "rule": "",
     "metadata": {"host": "c.example", "destinationPort": "443", "user": "bob",   "inboundTag": "in-reality"}}
  ]
}
EOF
          ;;
      esac
      ;;
    *)
      return 22
      ;;
  esac
  return 0
}

# Mock systemctl so _stats_service_uptime_seconds returns deterministic 0
systemctl() {
  if [[ "$1" == "show" ]]; then
    echo ""
    return 0
  fi
  return 0
}

export -f curl systemctl

#==============================================================================
# Tests
#==============================================================================

test_disabled_path() {
  echo ""
  echo "Testing stats_overview when .stats.enabled = false"
  echo "--------------------------------------------------"
  _setup_state false

  local out=""
  out=$(stats_overview_json)
  assert_jq "disabled -> enabled:false" "${out}" '.enabled' "false"

  out=$(stats_connections_json)
  assert_jq "disabled connections -> enabled:false" "${out}" '.enabled' "false"

  out=$(stats_users_json)
  assert_jq "disabled users -> enabled:false" "${out}" '.enabled' "false"

  _teardown_state
}

test_overview_json_structure() {
  echo ""
  echo "Testing stats_overview_json structure"
  echo "-------------------------------------"
  _setup_state true

  local out=""
  out=$(stats_overview_json)

  if echo "${out}" | jq empty 2>/dev/null; then
    pass "overview JSON is valid"
  else
    fail "overview JSON is invalid"
  fi

  assert_jq "enabled true" "${out}" '.enabled' "true"
  assert_jq "up_bps propagates" "${out}" '.traffic.up_bps' "12345"
  assert_jq "down_bps propagates" "${out}" '.traffic.down_bps' "67890"
  assert_jq "upload_total propagates" "${out}" '.traffic.upload_total' "524288"
  assert_jq "download_total" "${out}" '.traffic.download_total' "1048576"
  assert_jq "connection count" "${out}" '.connections.count' "3"
  assert_jq "memory.inuse" "${out}" '.memory.inuse' "10485760"

  _teardown_state
}

test_per_user_grouping() {
  echo ""
  echo "Testing per-user aggregation via /connections"
  echo "---------------------------------------------"
  _setup_state true

  local out=""
  out=$(stats_users_json)

  assert_jq "users payload valid" "${out}" '.enabled' "true"
  assert_jq "two distinct users" "${out}" '.users | length' "2"
  assert_jq "alice grouped count" "${out}" '[.users[] | select(.user=="alice")][0].count' "2"
  assert_jq "alice upload sum" "${out}" '[.users[] | select(.user=="alice")][0].upload' "150"
  assert_jq "alice download sum" "${out}" '[.users[] | select(.user=="alice")][0].download' "275"
  assert_jq "bob grouped count" "${out}" '[.users[] | select(.user=="bob")][0].count' "1"
  assert_jq "sorted by total traffic" "${out}" '.users[0].user' "alice"

  _teardown_state
}

test_single_user_fallback_from_state() {
  echo ""
  echo "Testing single-user fallback when metadata.user is absent"
  echo "--------------------------------------------------------"
  _setup_state true
  STATS_CONNECTIONS_FIXTURE="no_metadata_user_reality"

  local tmp_state=""
  tmp_state=$(mktemp)
  jq '.protocols.reality.users = [{name: "default", uuid: "uuid-default"}]' \
    "${_TMP_STATE}" >"${tmp_state}"
  mv -f "${tmp_state}" "${_TMP_STATE}"

  local out=""
  out=$(stats_users_json)
  assert_jq "fallback users payload valid" "${out}" '.enabled' "true"
  assert_jq "fallback user count" "${out}" '.users | length' "1"
  assert_jq "fallback user resolved from state" "${out}" '.users[0].user' "default"
  assert_jq "fallback upload sum" "${out}" '.users[0].upload' "100"
  assert_jq "fallback download sum" "${out}" '.users[0].download' "200"

  out=$(stats_connections_json)
  assert_jq "connections json exposes resolved_user" "${out}" \
    '.connections[0].resolved_user' "default"

  STATS_CONNECTIONS_FIXTURE="default"
  _teardown_state
}

test_multi_user_missing_metadata_stays_unknown() {
  echo ""
  echo "Testing multi-user installs do not fall back to default"
  echo "------------------------------------------------------"
  _setup_state true
  STATS_CONNECTIONS_FIXTURE="no_metadata_user_reality"

  local tmp_state=""
  tmp_state=$(mktemp)
  jq '.protocols.reality = {
        uuid: "uuid-default",
        users: [
          {name: "default", uuid: "uuid-default"},
          {name: "alice", uuid: "uuid-alice"}
        ]
      }' "${_TMP_STATE}" >"${tmp_state}"
  mv -f "${tmp_state}" "${_TMP_STATE}"

  local out=""
  out=$(stats_users_json)
  assert_jq "multi-user payload valid" "${out}" '.enabled' "true"
  assert_jq "multi-user fallback keeps unknown bucket" "${out}" '.users[0].user' "unknown"
  assert_jq "multi-user upload stays on unknown bucket" "${out}" '.users[0].upload' "100"
  assert_jq "multi-user download stays on unknown bucket" "${out}" '.users[0].download' "200"

  out=$(stats_connections_json)
  assert_jq "multi-user connections keep resolved_user unknown" "${out}" \
    '.connections[0].resolved_user' "unknown"

  STATS_CONNECTIONS_FIXTURE="default"
  _teardown_state
}

test_bearer_token_sent() {
  echo ""
  echo "Testing Bearer token is attached to requests"
  echo "--------------------------------------------"
  _setup_state true

  stats_curl /traffic >/dev/null 2>&1 || true
  if [[ "${_LAST_AUTH}" == "Authorization: Bearer ${_SECRET_FIXTURE}" ]]; then
    pass "stats_curl sends Bearer header with secret from state.json"
  else
    fail "unexpected Authorization header: '${_LAST_AUTH}'"
  fi

  _teardown_state
}

test_secret_never_printed() {
  echo ""
  echo "Testing secret is never emitted in stdout/stderr"
  echo "------------------------------------------------"
  _setup_state true

  local combined=""
  combined=$({
    stats_overview_pretty
    stats_overview_json
    stats_users_pretty
    stats_connections_pretty
  } 2>&1)

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if echo "${combined}" | grep -qF "${_SECRET_FIXTURE}"; then
    echo -e "${R}✗${N} secret leaked into user-facing output"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  else
    echo -e "${G}✓${N} secret absent from all stats command output"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  fi

  _teardown_state
}

test_curl_failure_handled() {
  echo ""
  echo "Testing graceful handling when curl fails (service down)"
  echo "--------------------------------------------------------"
  _setup_state true

  # Override curl to simulate connection refused
  curl() { return 7; }
  export -f curl

  local out=""
  out=$(stats_overview_json)
  if echo "${out}" | jq empty 2>/dev/null; then
    pass "overview JSON still valid when API unreachable"
  else
    fail "overview JSON invalid when API unreachable"
  fi

  assert_jq "connections count = 0 when unreachable" "${out}" '.connections.count' "0"
  assert_jq "traffic up_bps = 0 when unreachable" "${out}" '.traffic.up_bps' "0"

  _teardown_state

  # Restore the original mock for subsequent tests (none here)
  curl() {
    local arg url=""
    for arg in "$@"; do [[ "${arg}" == http://* ]] && url="${arg}"; done
    case "${url}" in
      */traffic) echo '{"up":0,"down":0}' ;;
      */memory) echo '{"inuse":0,"oslimit":0}' ;;
      */connections) echo '{"downloadTotal":0,"uploadTotal":0,"connections":[]}' ;;
      *) return 22 ;;
    esac
  }
  export -f curl
}

test_state_block_idempotent() {
  echo ""
  echo "Testing stats_ensure_state_block is idempotent"
  echo "----------------------------------------------"
  _setup_state true

  local before="" after=""
  before=$(jq -S '.stats' "${_TMP_STATE}")
  stats_ensure_state_block >/dev/null 2>&1 || true
  after=$(jq -S '.stats' "${_TMP_STATE}")
  assert_eq "ensure_state_block preserves existing block" "${before}" "${after}"

  _teardown_state
}

#==============================================================================
# Main
#==============================================================================

main() {
  echo "========================================="
  echo "lib/stats.sh Unit Tests"
  echo "========================================="

  local required=(stats_overview_json stats_connections_json stats_users_json
    stats_curl stats_ensure_state_block)
  local missing=0
  for fn in "${required[@]}"; do
    if ! declare -f "${fn}" >/dev/null 2>&1; then
      echo -e "${R}✗${N} ${fn} is not defined"
      missing=$((missing + 1))
    fi
  done
  [[ "${missing}" -gt 0 ]] && {
    echo "Required functions missing."
    exit 1
  }

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for these tests"
    exit 1
  fi

  test_disabled_path
  test_overview_json_structure
  test_per_user_grouping
  test_single_user_fallback_from_state
  test_multi_user_missing_metadata_stays_unknown
  test_bearer_token_sent
  test_secret_never_printed
  test_curl_failure_handled
  test_state_block_idempotent

  echo ""
  echo "========================================="
  echo "Test Summary"
  echo "========================================="
  echo "Total:  ${TOTAL_TESTS}"
  echo -e "${G}Passed: ${PASSED_TESTS}${N}"
  echo -e "${R}Failed: ${FAILED_TESTS}${N}"
  echo ""
  [[ "${FAILED_TESTS}" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
