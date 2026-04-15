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
