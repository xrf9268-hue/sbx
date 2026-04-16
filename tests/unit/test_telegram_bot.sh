#!/usr/bin/env bash
# tests/unit/test_telegram_bot.sh - Unit tests for lib/telegram_bot.sh
#
# Covers the pure helpers used by the long-poll daemon:
#   _tg_validate_token / _tg_is_authorized / _tg_parse_command
#   _tg_load_offset / _tg_save_offset
# Plus install.sh registration assertions (module array + contracts map),
# mirroring tests/unit/test_cloudflare_tunnel.sh:298-309.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Per-run sandbox so tests never touch /etc/sing-box or /var/lib.
TEST_TMP_DIR=$(mktemp -d -t sbx-tg-bot-test-XXXXXX)

# Override every state-bearing path before sourcing the lib so its
# `: "${VAR:=default}"` lines pick up the test fixtures.
export SBX_TG_OFFSET_DIR="${TEST_TMP_DIR}/var-lib"
export SBX_TG_OFFSET_FILE="${SBX_TG_OFFSET_DIR}/offset"
export SBX_TG_ENV_FILE="${TEST_TMP_DIR}/telegram.env"
export SBX_TG_SVC="${TEST_TMP_DIR}/sbx-telegram-bot.service"
export SBX_TG_BIN="${TEST_TMP_DIR}/sbx-telegram-bot"
export TEST_STATE_FILE="${TEST_TMP_DIR}/state.json"

source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
  echo "ERROR: Failed to load lib/common.sh"
  exit 1
}
source "${PROJECT_ROOT}/lib/validation.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/users.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/service.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/lib/telegram_bot.sh" 2>/dev/null || {
  echo "ERROR: Failed to source lib/telegram_bot.sh"
  exit 1
}

# Disarm strict mode and any inherited EXIT trap so negative-path
# assertions don't kill the harness.
set +eu
set -o pipefail
trap - EXIT INT TERM
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${result}" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${name}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${name}"
  fi
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      expected: ${expected}"
    echo "      actual:   ${actual}"
  fi
}

assert_zero() {
  local name="$1"
  local rc="$2"
  if [[ "${rc}" -eq 0 ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      rc=${rc}"
  fi
}

assert_nonzero() {
  local name="$1"
  local rc="$2"
  if [[ "${rc}" -ne 0 ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      rc=${rc} (expected nonzero)"
  fi
}

echo "=== Telegram Bot Module Unit Tests ==="

#==============================================================================
# _tg_validate_token: accepts canonical Telegram bot tokens, rejects garbage.
#==============================================================================
echo ""
echo "Testing _tg_validate_token..."

# 9-digit id + 35-char secret (canonical shape from BotFather)
_tg_validate_token "123456789:AAEhBP0av28FrI51bX4nF12345678901234"
assert_zero "valid 9-digit id token" "$?"

_tg_validate_token "12345678:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi"
assert_zero "valid 8-digit id token (lower bound)" "$?"

_tg_validate_token "1234567890:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi"
assert_zero "valid 10-digit id token (upper bound)" "$?"

# Underscore + dash allowed in the secret half per Telegram spec.
_tg_validate_token "123456789:AA-_BP0av28FrI51bX4nF12345678901234"
assert_zero "secret with - and _ accepted" "$?"

_tg_validate_token ""
assert_nonzero "empty token rejected" "$?"

_tg_validate_token "not-a-token"
assert_nonzero "no colon rejected" "$?"

_tg_validate_token "1234567:AAEhBP0av28FrI51bX4nF12345678901234"
assert_nonzero "7-digit id rejected (too short)" "$?"

_tg_validate_token "12345678901:AAEhBP0av28FrI51bX4nF12345678901234"
assert_nonzero "11-digit id rejected (too long)" "$?"

_tg_validate_token "123456789:AAEhBP0av28FrI51bX4nF1234567890123"
assert_nonzero "34-char secret rejected (too short)" "$?"

_tg_validate_token "123456789:AAEhBP0av28FrI51bX4nF123456789012345"
assert_nonzero "36-char secret rejected (too long)" "$?"

_tg_validate_token "123456789:AAEhBP0av28FrI51bX4nF1234567890123!"
assert_nonzero "invalid char in secret rejected" "$?"

#==============================================================================
# _tg_is_authorized: chat_id whitelist lookup against state.json.
#==============================================================================
echo ""
echo "Testing _tg_is_authorized..."

if command -v jq >/dev/null 2>&1; then
  # Case 1: state file missing → reject.
  rm -f "${TEST_STATE_FILE}"
  _tg_is_authorized "12345"
  assert_nonzero "missing state.json rejects everyone" "$?"

  # Case 2: empty whitelist → reject.
  cat >"${TEST_STATE_FILE}" <<'JSON'
{
  "version": "1.0",
  "telegram": {"enabled": false, "admin_chat_ids": []}
}
JSON
  _tg_is_authorized "12345"
  assert_nonzero "empty whitelist rejects everyone" "$?"

  # Case 3: telegram block missing entirely → reject.
  cat >"${TEST_STATE_FILE}" <<'JSON'
{"version": "1.0", "protocols": {}}
JSON
  _tg_is_authorized "12345"
  assert_nonzero "missing .telegram block rejects" "$?"

  # Case 4: chat_id present (numeric) → accept.
  cat >"${TEST_STATE_FILE}" <<'JSON'
{
  "version": "1.0",
  "telegram": {"enabled": true, "admin_chat_ids": [12345, 67890]}
}
JSON
  _tg_is_authorized "12345"
  assert_zero "whitelisted chat_id 12345 accepted" "$?"
  _tg_is_authorized "67890"
  assert_zero "whitelisted chat_id 67890 accepted" "$?"

  # Case 5: chat_id not present → reject.
  _tg_is_authorized "11111"
  assert_nonzero "non-whitelisted chat_id 11111 rejected" "$?"

  # Case 6: empty arg → reject (defensive).
  _tg_is_authorized ""
  assert_nonzero "empty chat_id arg rejected" "$?"

  # Case 7: negative chat_id (Telegram group id convention).
  cat >"${TEST_STATE_FILE}" <<'JSON'
{"telegram": {"admin_chat_ids": [-100123456789]}}
JSON
  _tg_is_authorized "-100123456789"
  assert_zero "negative group chat_id accepted" "$?"
else
  echo "  (skipping is_authorized tests: jq not installed)"
fi

#==============================================================================
# _tg_parse_command: split leading /cmd from args; strip @botname suffix.
#==============================================================================
echo ""
echo "Testing _tg_parse_command..."

assert_eq "/status -> 'status'" "status" "$(_tg_parse_command '/status')"
assert_eq "/help -> 'help'" "help" "$(_tg_parse_command '/help')"
assert_eq "/adduser alice -> 'adduser alice'" "adduser alice" "$(_tg_parse_command '/adduser alice')"
assert_eq "leading whitespace in args trimmed" \
  "adduser alice" "$(_tg_parse_command '/adduser   alice')"
assert_eq "/cmd@botname stripped" \
  "status" "$(_tg_parse_command '/status@my_sbx_bot')"
assert_eq "/cmd@botname with args" \
  "adduser alice" "$(_tg_parse_command '/adduser@my_sbx_bot alice')"
assert_eq "multi-word args preserved" \
  "removeuser alice bob" "$(_tg_parse_command '/removeuser alice bob')"

# Negative paths.
out=$(_tg_parse_command 'hello world' 2>/dev/null)
rc=$?
if [[ ${rc} -ne 0 && -z "${out}" ]]; then
  test_result "non-command text rejected" "pass"
else
  test_result "non-command text rejected" "fail"
fi

out=$(_tg_parse_command '' 2>/dev/null)
rc=$?
if [[ ${rc} -ne 0 && -z "${out}" ]]; then
  test_result "empty input rejected" "pass"
else
  test_result "empty input rejected" "fail"
fi

out=$(_tg_parse_command '/' 2>/dev/null)
rc=$?
if [[ ${rc} -ne 0 ]]; then
  test_result "lone slash rejected" "pass"
else
  test_result "lone slash rejected" "fail"
fi

#==============================================================================
# _tg_load_offset / _tg_save_offset: round-trip + missing-file default.
#==============================================================================
echo ""
echo "Testing _tg_load_offset / _tg_save_offset..."

# Missing file → "0".
rm -rf "${SBX_TG_OFFSET_DIR}"
assert_eq "missing offset file defaults to 0" "0" "$(_tg_load_offset)"

# Round-trip a positive integer.
_tg_save_offset 4242
assert_zero "save_offset returns 0" "$?"
assert_eq "round-trip 4242" "4242" "$(_tg_load_offset)"

# Overwrite with a different value.
_tg_save_offset 9999999
assert_eq "overwrite 9999999" "9999999" "$(_tg_load_offset)"

# Save 0 explicitly.
_tg_save_offset 0
assert_eq "round-trip 0" "0" "$(_tg_load_offset)"

# Negative offset (Telegram allows offset=-1 for 'latest only').
_tg_save_offset -1
assert_eq "round-trip -1" "-1" "$(_tg_load_offset)"

# Garbage content → load returns "0" (defensive).
echo "not-a-number" >"${SBX_TG_OFFSET_FILE}"
assert_eq "garbage offset content defaults to 0" "0" "$(_tg_load_offset)"

# Non-numeric save rejected.
_tg_save_offset "abc"
assert_nonzero "save_offset rejects non-numeric" "$?"

# Confirm offset file was created with 0600 (mktemp default may vary; we set
# it explicitly in _tg_save_offset).
_tg_save_offset 100
perm=$(stat -c '%a' "${SBX_TG_OFFSET_FILE}" 2>/dev/null ||
  stat -f '%Lp' "${SBX_TG_OFFSET_FILE}" 2>/dev/null)
assert_eq "offset file is mode 600" "600" "${perm}"

#==============================================================================
# _tg_get_updates: backoff loop, success path, attempt cap, missing token.
# Curl + sleep are stubbed via SBX_TG_CURL_CMD / SBX_TG_SLEEP_CMD so the
# test never touches the network or wall clock.
#==============================================================================
echo ""
echo "Testing _tg_get_updates..."

# Counters live in files so subshells don't lose them.
GU_CALLS_FILE="${TEST_TMP_DIR}/gu_calls"
GU_SLEEPS_FILE="${TEST_TMP_DIR}/gu_sleeps"

# Stub curl: writes a fixture body and succeeds. Detects the -o argument
# anywhere in argv (the lib uses curl -o <file>).
mock_curl_get_success() {
  local out_file=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      out_file="$2"
      shift 2
      continue
    fi
    shift
  done
  echo '{"ok":true,"result":[]}' >"${out_file}"
  echo "ok" >>"${GU_CALLS_FILE}"
  return 0
}

# Stub curl: always fails (simulates network error / 5xx).
mock_curl_get_fail() {
  echo "fail" >>"${GU_CALLS_FILE}"
  return 22
}

# Stub sleep: records arg, returns immediately.
mock_sleep() {
  echo "$1" >>"${GU_SLEEPS_FILE}"
  return 0
}

export SBX_TG_SLEEP_CMD=mock_sleep

# Case 1: missing BOT_TOKEN → reject without calling curl.
unset BOT_TOKEN
: >"${GU_CALLS_FILE}"
SBX_TG_CURL_CMD=mock_curl_get_success _tg_get_updates 0 "${TEST_TMP_DIR}/gu.out"
rc=$?
calls=$(wc -l <"${GU_CALLS_FILE}" | tr -d ' ')
if [[ ${rc} -ne 0 && "${calls}" == "0" ]]; then
  test_result "missing BOT_TOKEN rejects without curl call" "pass"
else
  test_result "missing BOT_TOKEN rejects without curl call" "fail"
  echo "      rc=${rc} calls=${calls}"
fi

# Case 2: missing output_file arg → reject.
BOT_TOKEN="123456789:AAEhBP0av28FrI51bX4nF12345678901234"
export BOT_TOKEN
SBX_TG_CURL_CMD=mock_curl_get_success _tg_get_updates 0 ""
assert_nonzero "missing output_file rejects" "$?"

# Case 3: success on first try → rc=0, output file written, no sleeps.
: >"${GU_CALLS_FILE}"
: >"${GU_SLEEPS_FILE}"
rm -f "${TEST_TMP_DIR}/gu.out"
SBX_TG_CURL_CMD=mock_curl_get_success _tg_get_updates 42 "${TEST_TMP_DIR}/gu.out"
assert_zero "first-try success returns 0" "$?"
calls=$(wc -l <"${GU_CALLS_FILE}" | tr -d ' ')
sleeps=$(wc -l <"${GU_SLEEPS_FILE}" | tr -d ' ')
assert_eq "exactly one curl call on success" "1" "${calls}"
assert_eq "no sleep on success" "0" "${sleeps}"
[[ -s "${TEST_TMP_DIR}/gu.out" ]] && test_result "output file populated" "pass" ||
  test_result "output file populated" "fail"

# Case 4: persistent failure with attempt cap → rc=1, exact attempt count,
# backoff sequence is 1, 2, 4 (no sleep after the final failed attempt).
: >"${GU_CALLS_FILE}"
: >"${GU_SLEEPS_FILE}"
SBX_TG_BACKOFF_MAX_ATTEMPTS=4 SBX_TG_CURL_CMD=mock_curl_get_fail \
  _tg_get_updates 0 "${TEST_TMP_DIR}/gu.out"
rc=$?
calls=$(wc -l <"${GU_CALLS_FILE}" | tr -d ' ')
sleeps_seq=$(tr '\n' ',' <"${GU_SLEEPS_FILE}")
assert_nonzero "persistent failure with cap returns nonzero" "${rc}"
assert_eq "exactly N curl attempts" "4" "${calls}"
assert_eq "backoff sequence 1,2,4 between attempts" "1,2,4," "${sleeps_seq}"

# Case 5: backoff caps at 30s. With 7 attempts the 6th sleep would be
# 32; the cap clamps it back to 30.
: >"${GU_CALLS_FILE}"
: >"${GU_SLEEPS_FILE}"
SBX_TG_BACKOFF_MAX_ATTEMPTS=7 SBX_TG_CURL_CMD=mock_curl_get_fail \
  _tg_get_updates 0 "${TEST_TMP_DIR}/gu.out" >/dev/null 2>&1
sleeps_seq=$(tr '\n' ',' <"${GU_SLEEPS_FILE}")
assert_eq "backoff caps at 30 (1,2,4,8,16,30)" "1,2,4,8,16,30," "${sleeps_seq}"

#==============================================================================
# _tg_send_message: success, 429 retry, hard failure, missing token.
#==============================================================================
echo ""
echo "Testing _tg_send_message..."

SM_CALLS_FILE="${TEST_TMP_DIR}/sm_calls"
SM_SLEEPS_FILE="${TEST_TMP_DIR}/sm_sleeps"

# Stub curl for send: writes body to -o file, prints HTTP code via -w.
mock_curl_send_200() {
  local out_file=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      out_file="$2"
      shift 2
      continue
    fi
    shift
  done
  echo '{"ok":true,"result":{"message_id":1}}' >"${out_file}"
  echo "200" >>"${SM_CALLS_FILE}"
  printf '200'
}

mock_curl_send_500() {
  local out_file=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      out_file="$2"
      shift 2
      continue
    fi
    shift
  done
  echo '{"ok":false,"error_code":500}' >"${out_file}"
  echo "500" >>"${SM_CALLS_FILE}"
  printf '500'
}

# 429 once, then 200 — exercises the rate-limit retry path.
mock_curl_send_429_then_200() {
  local out_file=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      out_file="$2"
      shift 2
      continue
    fi
    shift
  done
  local n
  n=$(wc -l <"${SM_CALLS_FILE}" 2>/dev/null | tr -d ' ')
  n=${n:-0}
  n=$((n + 1))
  if [[ ${n} -eq 1 ]]; then
    echo '{"ok":false,"error_code":429,"parameters":{"retry_after":7}}' >"${out_file}"
    echo "429" >>"${SM_CALLS_FILE}"
    printf '429'
  else
    echo '{"ok":true}' >"${out_file}"
    echo "200" >>"${SM_CALLS_FILE}"
    printf '200'
  fi
}

mock_sleep_send() {
  echo "$1" >>"${SM_SLEEPS_FILE}"
  return 0
}

export SBX_TG_SLEEP_CMD=mock_sleep_send

# Case 1: missing token → reject.
unset BOT_TOKEN
: >"${SM_CALLS_FILE}"
SBX_TG_CURL_CMD=mock_curl_send_200 _tg_send_message 12345 "hello"
rc=$?
calls=$(wc -l <"${SM_CALLS_FILE}" | tr -d ' ')
if [[ ${rc} -ne 0 && "${calls}" == "0" ]]; then
  test_result "send: missing BOT_TOKEN rejects without curl call" "pass"
else
  test_result "send: missing BOT_TOKEN rejects without curl call" "fail"
fi

# Case 2: missing chat_id or text → reject.
BOT_TOKEN="123456789:AAEhBP0av28FrI51bX4nF12345678901234"
export BOT_TOKEN
SBX_TG_CURL_CMD=mock_curl_send_200 _tg_send_message "" "hello"
assert_nonzero "send: empty chat_id rejected" "$?"
SBX_TG_CURL_CMD=mock_curl_send_200 _tg_send_message 12345 ""
assert_nonzero "send: empty text rejected" "$?"

# Case 3: 200 first try.
: >"${SM_CALLS_FILE}"
: >"${SM_SLEEPS_FILE}"
SBX_TG_CURL_CMD=mock_curl_send_200 _tg_send_message 12345 "hello world"
assert_zero "send: 200 returns 0" "$?"
calls=$(wc -l <"${SM_CALLS_FILE}" | tr -d ' ')
sleeps=$(wc -l <"${SM_SLEEPS_FILE}" | tr -d ' ')
assert_eq "send: exactly one curl call on 200" "1" "${calls}"
assert_eq "send: no sleep on 200" "0" "${sleeps}"

# Case 4: 500 → fail immediately, no retry.
: >"${SM_CALLS_FILE}"
: >"${SM_SLEEPS_FILE}"
SBX_TG_CURL_CMD=mock_curl_send_500 _tg_send_message 12345 "hello"
assert_nonzero "send: 500 returns nonzero" "$?"
calls=$(wc -l <"${SM_CALLS_FILE}" | tr -d ' ')
assert_eq "send: 500 does not retry" "1" "${calls}"

# Case 5: 429 then 200 → success, exactly one sleep with retry_after=7.
if command -v jq >/dev/null 2>&1; then
  : >"${SM_CALLS_FILE}"
  : >"${SM_SLEEPS_FILE}"
  SBX_TG_CURL_CMD=mock_curl_send_429_then_200 _tg_send_message 12345 "hello"
  assert_zero "send: 429-then-200 returns 0" "$?"
  calls=$(wc -l <"${SM_CALLS_FILE}" | tr -d ' ')
  sleeps_seq=$(tr '\n' ',' <"${SM_SLEEPS_FILE}")
  assert_eq "send: 429-then-200 makes 2 calls" "2" "${calls}"
  assert_eq "send: sleep honors retry_after" "7," "${sleeps_seq}"
else
  echo "  (skipping 429 retry test: jq not installed)"
fi

# Reset SBX_TG_SLEEP_CMD so later tests in this file aren't affected.
unset SBX_TG_SLEEP_CMD SBX_TG_CURL_CMD SBX_TG_BACKOFF_MAX_ATTEMPTS

#==============================================================================
# _tg_dispatch_command + _tg_handle_*: route commands to the right handler,
# enforce authorization (silent reject), capture replies via _tg_send_message
# shadow. Each external dependency (user_add, user_remove, sync, systemctl,
# check_service_status, restart_service) is stubbed so we exercise the
# routing logic without touching real state or services.
#==============================================================================
echo ""
echo "Testing _tg_dispatch_command + handlers..."

SEND_LOG="${TEST_TMP_DIR}/send.log"
USER_ADD_LOG="${TEST_TMP_DIR}/user_add.log"
USER_REMOVE_LOG="${TEST_TMP_DIR}/user_remove.log"
SYSTEMCTL_LOG="${TEST_TMP_DIR}/systemctl.log"

# Shadow _tg_send_message: capture every reply for assertion.
_tg_send_message() {
  printf '[chat=%s] %s\n' "$1" "$2" >>"${SEND_LOG}"
  return 0
}

# Stub external dependencies. Each logs the args so we can assert downstream
# side effects (e.g. that adduser triggered sync + restart).
check_service_status() {
  [[ "${STUB_SERVICE_ACTIVE:-1}" == "1" ]]
}
user_list() {
  echo "alice  uuid-aaa  2025-01-01"
  echo "bob    uuid-bbb  2025-01-02"
}
user_add() {
  echo "user_add $*" >>"${USER_ADD_LOG}"
  if [[ "${STUB_USER_ADD_FAIL:-0}" == "1" ]]; then
    echo "User with name 'dup' already exists" >&2
    return 1
  fi
  # Mimic the real user_add stdout
  echo "Added user: ${2:-?} (uuid-stub)"
  return 0
}
user_remove() {
  echo "user_remove $*" >>"${USER_REMOVE_LOG}"
  if [[ "${STUB_USER_REMOVE_FAIL:-0}" == "1" ]]; then
    echo "User not found: $1" >&2
    return 1
  fi
  echo "Removed user: $1 (uuid-stub)"
  return 0
}
sync_users_to_config() { return 0; }
restart_service() {
  echo "restart_service called" >>"${SYSTEMCTL_LOG}"
  if [[ "${STUB_RESTART_FAIL:-0}" == "1" ]]; then
    echo "systemctl restart failed" >&2
    return 1
  fi
  return 0
}
# Shadow systemctl so adduser/removeuser don't actually touch services.
systemctl() {
  echo "systemctl $*" >>"${SYSTEMCTL_LOG}"
  return 0
}

# Whitelist chat_id 99999 in state.json.
cat >"${TEST_STATE_FILE}" <<'JSON'
{"version":"1.0","telegram":{"enabled":true,"admin_chat_ids":[99999]}}
JSON

reset_logs() {
  : >"${SEND_LOG}"
  : >"${USER_ADD_LOG}"
  : >"${USER_REMOVE_LOG}"
  : >"${SYSTEMCTL_LOG}"
}

# --- Authorization boundary --------------------------------------------------

# Non-whitelisted chat → silent: NO sendMessage call at all.
reset_logs
_tg_dispatch_command 11111 status
sends=$(wc -l <"${SEND_LOG}" | tr -d ' ')
assert_eq "non-whitelisted chat → silent (0 replies)" "0" "${sends}"

# Whitelisted chat → at least one reply.
reset_logs
_tg_dispatch_command 99999 status
sends=$(wc -l <"${SEND_LOG}" | tr -d ' ')
if [[ "${sends}" -ge 1 ]]; then
  test_result "whitelisted chat → handler invoked" "pass"
else
  test_result "whitelisted chat → handler invoked" "fail"
fi

# Empty chat_id or empty cmd → reject.
_tg_dispatch_command "" status
assert_nonzero "dispatch empty chat_id rejected" "$?"
_tg_dispatch_command 99999 ""
assert_nonzero "dispatch empty cmd rejected" "$?"

# --- /status routing ---------------------------------------------------------

reset_logs
STUB_SERVICE_ACTIVE=1 _tg_dispatch_command 99999 status
reply=$(cat "${SEND_LOG}")
assert_contains_str() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    test_result "${name}" "pass"
  else
    test_result "${name}" "fail"
    echo "      missing: ${needle}"
    echo "      in:      ${haystack}"
  fi
}
assert_contains_str "/status active reply" "active" "${reply}"

reset_logs
STUB_SERVICE_ACTIVE=0 _tg_dispatch_command 99999 status
reply=$(cat "${SEND_LOG}")
assert_contains_str "/status inactive reply" "inactive" "${reply}"

# --- /users routing ----------------------------------------------------------

reset_logs
_tg_dispatch_command 99999 users
reply=$(cat "${SEND_LOG}")
assert_contains_str "/users includes alice" "alice" "${reply}"
assert_contains_str "/users includes bob" "bob" "${reply}"

# --- /adduser routing -------------------------------------------------------

# Happy path: triggers user_add + sync + restart_service.
reset_logs
_tg_dispatch_command 99999 adduser charlie
reply=$(cat "${SEND_LOG}")
ua=$(cat "${USER_ADD_LOG}")
sysctl=$(cat "${SYSTEMCTL_LOG}")
assert_contains_str "/adduser invokes user_add with --name <arg>" \
  "user_add --name charlie" "${ua}"
assert_contains_str "/adduser triggers restart_service" \
  "restart_service called" "${sysctl}"
assert_contains_str "/adduser success reply contains ✅" "✅" "${reply}"

# Missing arg.
reset_logs
_tg_dispatch_command 99999 adduser
reply=$(cat "${SEND_LOG}")
assert_contains_str "/adduser without arg shows usage" "Usage" "${reply}"
ua=$(wc -l <"${USER_ADD_LOG}" | tr -d ' ')
assert_eq "/adduser without arg does not call user_add" "0" "${ua}"

# Invalid name (contains semicolon — shell metachar).
reset_logs
_tg_dispatch_command 99999 adduser "bad;name"
reply=$(cat "${SEND_LOG}")
assert_contains_str "/adduser invalid name rejected" "Invalid" "${reply}"
ua=$(wc -l <"${USER_ADD_LOG}" | tr -d ' ')
assert_eq "/adduser invalid name skips user_add" "0" "${ua}"

# user_add fails → error reply, no restart.
reset_logs
STUB_USER_ADD_FAIL=1 _tg_dispatch_command 99999 adduser dup
reply=$(cat "${SEND_LOG}")
sysctl=$(cat "${SYSTEMCTL_LOG}")
assert_contains_str "/adduser failure reply contains ❌" "❌" "${reply}"
assert_eq "/adduser failure skips restart" "" "${sysctl}"
unset STUB_USER_ADD_FAIL

# --- /removeuser routing -----------------------------------------------------

reset_logs
_tg_dispatch_command 99999 removeuser alice
reply=$(cat "${SEND_LOG}")
ur=$(cat "${USER_REMOVE_LOG}")
sysctl=$(cat "${SYSTEMCTL_LOG}")
assert_contains_str "/removeuser invokes user_remove" \
  "user_remove alice" "${ur}"
assert_contains_str "/removeuser triggers restart_service" \
  "restart_service called" "${sysctl}"
assert_contains_str "/removeuser success reply contains ✅" "✅" "${reply}"

reset_logs
_tg_dispatch_command 99999 removeuser
reply=$(cat "${SEND_LOG}")
assert_contains_str "/removeuser without arg shows usage" "Usage" "${reply}"

reset_logs
STUB_USER_REMOVE_FAIL=1 _tg_dispatch_command 99999 removeuser ghost
reply=$(cat "${SEND_LOG}")
assert_contains_str "/removeuser failure reply contains ❌" "❌" "${reply}"
unset STUB_USER_REMOVE_FAIL

# --- /restart routing --------------------------------------------------------

reset_logs
_tg_dispatch_command 99999 restart
reply=$(cat "${SEND_LOG}")
assert_contains_str "/restart success reply" "restarted" "${reply}"

reset_logs
STUB_RESTART_FAIL=1 _tg_dispatch_command 99999 restart
reply=$(cat "${SEND_LOG}")
assert_contains_str "/restart failure reply" "Restart failed" "${reply}"
unset STUB_RESTART_FAIL

# --- /help and unknown command ----------------------------------------------

reset_logs
_tg_dispatch_command 99999 help
reply=$(cat "${SEND_LOG}")
assert_contains_str "/help lists /status" "/status" "${reply}"
assert_contains_str "/help lists /adduser" "/adduser" "${reply}"

# Unknown command falls back to help (per plan).
reset_logs
_tg_dispatch_command 99999 wat
reply=$(cat "${SEND_LOG}")
assert_contains_str "unknown command falls back to help" "/help" "${reply}"

# /start (Telegram convention) also shows help.
reset_logs
_tg_dispatch_command 99999 start
reply=$(cat "${SEND_LOG}")
assert_contains_str "/start aliases to help" "/status" "${reply}"

#==============================================================================
# _tg_update_state: atomic merge into .telegram block. Verifies value
# typing (bool/int/string/array), allowlist enforcement, format validation,
# preservation of unrelated state, and chmod 600 after rename.
#==============================================================================
echo ""
echo "Testing _tg_update_state..."

if command -v jq >/dev/null 2>&1; then
  # Seed a state file with unrelated fields we expect to survive.
  cat >"${TEST_STATE_FILE}" <<'JSON'
{
  "version": "1.0",
  "server": {"ip": "203.0.113.1"},
  "protocols": {"reality": {"enabled": true}}
}
JSON
  chmod 600 "${TEST_STATE_FILE}"

  # Case 1: enabled=true (boolean literal).
  _tg_update_state enabled=true >/dev/null 2>&1
  assert_zero "set enabled=true returns 0" "$?"
  assert_eq ".telegram.enabled is JSON true" \
    "true" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"

  # Case 2: unrelated state survives.
  assert_eq "unrelated .protocols.reality.enabled preserved" \
    "true" "$(jq -r '.protocols.reality.enabled' "${TEST_STATE_FILE}")"
  assert_eq "unrelated .server.ip preserved" \
    "203.0.113.1" "$(jq -r '.server.ip' "${TEST_STATE_FILE}")"

  # Case 3: username=mybot (string).
  _tg_update_state username=mybot >/dev/null 2>&1
  assert_eq ".telegram.username is JSON string" \
    "mybot" "$(jq -r '.telegram.username' "${TEST_STATE_FILE}")"
  # And the previous .telegram.enabled is still there (merge, not replace).
  assert_eq "previous .telegram.enabled retained after username update" \
    "true" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"

  # Case 4: multi-pair single call (atomic).
  _tg_update_state enabled=false username=otherbot >/dev/null 2>&1
  assert_eq "multi-pair: enabled=false applied" \
    "false" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"
  assert_eq "multi-pair: username=otherbot applied" \
    "otherbot" "$(jq -r '.telegram.username' "${TEST_STATE_FILE}")"

  # Case 5: admin_chat_ids as JSON array (--argjson path).
  _tg_update_state admin_chat_ids='[12345,67890,-100123]' >/dev/null 2>&1
  assert_eq "admin_chat_ids written as JSON array" \
    "3" "$(jq -r '.telegram.admin_chat_ids | length' "${TEST_STATE_FILE}")"
  assert_eq "admin_chat_ids[0] is integer 12345" \
    "12345" "$(jq -r '.telegram.admin_chat_ids[0]' "${TEST_STATE_FILE}")"
  assert_eq "admin_chat_ids[2] is negative group id" \
    "-100123" "$(jq -r '.telegram.admin_chat_ids[2]' "${TEST_STATE_FILE}")"

  # Case 6: file mode is 600 after update.
  perm=$(stat -c '%a' "${TEST_STATE_FILE}" 2>/dev/null ||
    stat -f '%Lp' "${TEST_STATE_FILE}" 2>/dev/null)
  assert_eq "state.json mode preserved at 600" "600" "${perm}"

  # Case 7: state.json remains valid JSON.
  jq empty "${TEST_STATE_FILE}" >/dev/null 2>&1
  assert_zero "state.json remains parseable JSON" "$?"

  # Case 8: missing state file → return 0 (warn-and-skip, matches cloudflared).
  rm -f "${TEST_STATE_FILE}"
  _tg_update_state enabled=true 2>/dev/null
  assert_zero "missing state file → return 0 (skip)" "$?"

  # Restore for negative-path tests below.
  echo '{"version":"1.0"}' >"${TEST_STATE_FILE}"

  # Case 9: no args rejected.
  _tg_update_state 2>/dev/null
  assert_nonzero "no args rejected" "$?"

  # Case 10: malformed kv (no '=') rejected.
  _tg_update_state "notakv" 2>/dev/null
  assert_nonzero "kv without '=' rejected" "$?"

  # Case 11: invalid key (digits-only / shell metas) rejected.
  _tg_update_state "123=foo" 2>/dev/null
  assert_nonzero "key starting with digit rejected" "$?"
  _tg_update_state "evil;rm=foo" 2>/dev/null
  assert_nonzero "key with shell meta rejected" "$?"

  # Case 12: key not in allowlist rejected (defense-in-depth).
  _tg_update_state "bot_token=secret123" 2>/dev/null
  assert_nonzero "key outside allowlist rejected" "$?"
  # And the rejected write must NOT have leaked into state.
  bot_field=$(jq -r '.telegram.bot_token // "MISSING"' "${TEST_STATE_FILE}")
  assert_eq "rejected key never written" "MISSING" "${bot_field}"

  # Case 13: weird-but-valid string value (spaces) round-trips.
  _tg_update_state "username=My Bot Name" >/dev/null 2>&1
  assert_eq "string value with spaces round-trips" \
    "My Bot Name" "$(jq -r '.telegram.username' "${TEST_STATE_FILE}")"

  # Case 14: integer value typed as JSON int (not string).
  _tg_update_state "admin_chat_ids=[42]" >/dev/null 2>&1
  type_check=$(jq -r '.telegram.admin_chat_ids[0] | type' "${TEST_STATE_FILE}")
  assert_eq "integer in array stays JSON number" "number" "${type_check}"

  # Case 15: trip enable→disable cycle round-trip integrity.
  _tg_update_state enabled=true username=cycle1 >/dev/null 2>&1
  _tg_update_state enabled=false >/dev/null 2>&1
  enabled=$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")
  username=$(jq -r '.telegram.username' "${TEST_STATE_FILE}")
  assert_eq "cycle: enabled is false" "false" "${enabled}"
  assert_eq "cycle: username preserved across toggle" "cycle1" "${username}"
else
  echo "  (skipping _tg_update_state tests: jq not installed)"
fi

#==============================================================================
# telegram_bot_* lifecycle helpers: setup / enable / disable / status / logs /
# admin list mutation.
#==============================================================================
echo ""
echo "Testing telegram_bot lifecycle..."

TG_VERIFY_LOG="${TEST_TMP_DIR}/verify.log"
JOURNALCTL_LOG="${TEST_TMP_DIR}/journalctl.log"

reset_lifecycle_logs() {
  : >"${SYSTEMCTL_LOG}"
  : >"${JOURNALCTL_LOG}"
  : >"${TG_VERIFY_LOG}"
}

_tg_verify_token_live() {
  local token="${1:-}"
  printf '%s\n' "${token}" >>"${TG_VERIFY_LOG}"
  if [[ "${token}" == "123456789:AAEhBP0av28FrI51bX4nF12345678901234" ]]; then
    printf 'my_sbx_bot\n'
    return 0
  fi
  return 1
}

systemctl() {
  echo "systemctl $*" >>"${SYSTEMCTL_LOG}"
  case "${1:-}" in
    is-active)
      [[ "${STUB_TG_SYSTEMD_ACTIVE:-0}" == "1" ]]
      ;;
    status)
      echo "sbx-telegram-bot.service - sbx Telegram Bot"
      if [[ "${STUB_TG_SYSTEMD_ACTIVE:-0}" == "1" ]]; then
        echo "Active: active (running)"
        return 0
      fi
      echo "Active: inactive (dead)"
      return 3
      ;;
    daemon-reload | enable | disable | start | stop | restart)
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

journalctl() {
  echo "journalctl $*" >>"${JOURNALCTL_LOG}"
  echo "telegram bot journal output"
}

need_root() {
  return 0
}

if command -v jq >/dev/null 2>&1; then
  reset_lifecycle_logs
  cat >"${TEST_STATE_FILE}" <<'JSON'
{"version":"1.0","protocols":{"reality":{"enabled":true}}}
JSON
  rm -f "${SBX_TG_ENV_FILE}" "${SBX_TG_SVC}" "${SBX_TG_BIN}"
  mkdir -p "$(dirname "${SBX_TG_BIN}")"
  : >"${SBX_TG_BIN}"
  chmod 755 "${SBX_TG_BIN}"

  printf '%s\n%s\n' \
    "123456789:AAEhBP0av28FrI51bX4nF12345678901234" \
    "99999" | telegram_bot_setup >/dev/null 2>&1
  assert_zero "telegram_bot_setup succeeds with valid token + admin" "$?"
  assert_eq "setup writes BOT_TOKEN env file" \
    "BOT_TOKEN=123456789:AAEhBP0av28FrI51bX4nF12345678901234" \
    "$(grep '^BOT_TOKEN=' "${SBX_TG_ENV_FILE}")"
  assert_eq "setup stores username" \
    "my_sbx_bot" "$(jq -r '.telegram.username' "${TEST_STATE_FILE}")"
  assert_eq "setup stores enabled=false before service enable" \
    "false" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"
  assert_eq "setup seeds first admin_chat_id" \
    "99999" "$(jq -r '.telegram.admin_chat_ids[0]' "${TEST_STATE_FILE}")"
  assert_eq "setup verifies the provided token" \
    "123456789:AAEhBP0av28FrI51bX4nF12345678901234" "$(tail -n 1 "${TG_VERIFY_LOG}")"
  perm=$(stat -c '%a' "${SBX_TG_ENV_FILE}" 2>/dev/null ||
    stat -f '%Lp' "${SBX_TG_ENV_FILE}" 2>/dev/null)
  assert_eq "telegram.env is mode 600 after setup" "600" "${perm}"

  reset_lifecycle_logs
  telegram_bot_admin_add 12345 >/dev/null 2>&1
  assert_zero "admin_add accepts new numeric chat id" "$?"
  assert_eq "admin_add appends second admin id" \
    "2" "$(jq -r '.telegram.admin_chat_ids | length' "${TEST_STATE_FILE}")"

  telegram_bot_admin_add 12345 >/dev/null 2>&1
  assert_eq "admin_add de-duplicates existing chat id" \
    "2" "$(jq -r '.telegram.admin_chat_ids | length' "${TEST_STATE_FILE}")"

  telegram_bot_admin_remove 99999 >/dev/null 2>&1
  assert_zero "admin_remove succeeds for existing id" "$?"
  assert_eq "admin_remove drops the target id" \
    "12345" "$(jq -r '.telegram.admin_chat_ids[0]' "${TEST_STATE_FILE}")"

  admin_list_output="$(telegram_bot_admin_list 2>/dev/null)"
  assert_contains_str "admin_list prints the remaining id" "12345" "${admin_list_output}"

  reset_lifecycle_logs
  telegram_bot_enable >/dev/null 2>&1
  assert_zero "telegram_bot_enable succeeds once setup is complete" "$?"
  assert_eq "enable marks telegram.enabled=true" \
    "true" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"
  assert_contains_str "enable writes service file" "[Service]" "$(cat "${SBX_TG_SVC}")"
  assert_contains_str "enable unit references launcher" \
    "ExecStart=${SBX_TG_BIN}" "$(cat "${SBX_TG_SVC}")"
  assert_contains_str "enable unit references env file" \
    "EnvironmentFile=-${SBX_TG_ENV_FILE}" "$(cat "${SBX_TG_SVC}")"
  assert_contains_str "enable reloads systemd" \
    "systemctl daemon-reload" "$(cat "${SYSTEMCTL_LOG}")"
  assert_contains_str "enable starts service immediately" \
    "systemctl enable --now ${SBX_TG_SERVICE_NAME}" "$(cat "${SYSTEMCTL_LOG}")"

  reset_lifecycle_logs
  STUB_TG_SYSTEMD_ACTIVE=1
  status_output="$(telegram_bot_status 2>&1)"
  assert_contains_str "status includes username" "my_sbx_bot" "${status_output}"
  assert_contains_str "status includes admin count" "Admins" "${status_output}"
  assert_contains_str "status includes active systemd text" "active (running)" "${status_output}"
  unset STUB_TG_SYSTEMD_ACTIVE

  reset_lifecycle_logs
  logs_output="$(telegram_bot_logs 2>&1)"
  assert_contains_str "logs delegates to journalctl output" \
    "telegram bot journal output" "${logs_output}"
  assert_contains_str "logs targets the telegram bot unit" \
    "journalctl -u ${SBX_TG_SERVICE_NAME}" "$(cat "${JOURNALCTL_LOG}")"

  reset_lifecycle_logs
  telegram_bot_disable >/dev/null 2>&1
  assert_zero "telegram_bot_disable succeeds" "$?"
  assert_eq "disable marks telegram.enabled=false" \
    "false" "$(jq -r '.telegram.enabled' "${TEST_STATE_FILE}")"
  if [[ ! -f "${SBX_TG_SVC}" ]]; then
    test_result "disable removes the service unit file" "pass"
  else
    test_result "disable removes the service unit file" "fail"
  fi
  assert_contains_str "disable stops+disables service" \
    "systemctl disable --now ${SBX_TG_SERVICE_NAME}" "$(cat "${SYSTEMCTL_LOG}")"
else
  echo "  (skipping lifecycle tests: jq not installed)"
fi

#==============================================================================
# telegram_bot_run bootstrap offset handling.
# First startup must discard backlog, persist the new offset, and avoid
# executing the latest historical command.
#==============================================================================
echo ""
echo "Testing telegram_bot_run bootstrap offset..."

RUN_DISPATCH_LOG="${TEST_TMP_DIR}/run-dispatch.log"
RUN_GET_UPDATES_LOG="${TEST_TMP_DIR}/run-get-updates.log"

_tg_get_updates() {
  local offset="${1:-}"
  local output_file="${2:-}"
  printf '%s\n' "${offset}" >>"${RUN_GET_UPDATES_LOG}"
  cat >"${output_file}" <<'JSON'
{"ok":true,"result":[{"update_id":41,"message":{"chat":{"id":99999},"text":"/restart"}}]}
JSON
  return 0
}

_tg_dispatch_command() {
  printf '%s\n' "$*" >>"${RUN_DISPATCH_LOG}"
  return 0
}

if command -v jq >/dev/null 2>&1; then
  : >"${RUN_DISPATCH_LOG}"
  : >"${RUN_GET_UPDATES_LOG}"
  rm -f "${SBX_TG_OFFSET_FILE}"
  BOT_TOKEN="123456789:AAEhBP0av28FrI51bX4nF12345678901234" \
    SBX_TG_RUN_ONCE=1 telegram_bot_run >/dev/null 2>&1
  assert_zero "telegram_bot_run succeeds in bootstrap discard mode" "$?"
  assert_eq "first poll uses offset=-1 when offset file is absent" \
    "-1" "$(head -n 1 "${RUN_GET_UPDATES_LOG}")"
  sends=$(wc -l <"${RUN_DISPATCH_LOG}" | tr -d ' ')
  assert_eq "bootstrap discard does not dispatch historical commands" "0" "${sends}"
  assert_eq "bootstrap discard persists update_id+1 to offset file" \
    "42" "$(_tg_load_offset)"
else
  echo "  (skipping run bootstrap tests: jq not installed)"
fi

#==============================================================================
# Module is registered in install.sh modules array + contracts map
# (mirrors tests/unit/test_cloudflare_tunnel.sh:298-309).
#==============================================================================
echo ""
echo "Testing install.sh registration..."

if grep -qE 'local modules=\(.*\btelegram_bot\b.*\)' "${PROJECT_ROOT}/install.sh"; then
  test_result "telegram_bot registered in install.sh modules array" "pass"
else
  test_result "telegram_bot registered in install.sh modules array" "fail"
fi

if grep -q '\["telegram_bot"\]=' "${PROJECT_ROOT}/install.sh"; then
  test_result "telegram_bot API contract registered" "pass"
else
  test_result "telegram_bot API contract registered" "fail"
fi

#==============================================================================
# Public API surface: every exported function exists.
#==============================================================================
echo ""
echo "Testing exported API surface..."

for fn in telegram_bot_setup telegram_bot_enable telegram_bot_disable \
  telegram_bot_status telegram_bot_logs telegram_bot_admin_add \
  telegram_bot_admin_remove telegram_bot_admin_list telegram_bot_run; do
  if declare -F "${fn}" >/dev/null 2>&1; then
    test_result "${fn} is defined" "pass"
  else
    test_result "${fn} is defined" "fail"
  fi
done

#==============================================================================
# Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -eq 0 ]]; then
  exit 0
else
  exit 1
fi
