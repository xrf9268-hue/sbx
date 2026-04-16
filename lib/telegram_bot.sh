#!/usr/bin/env bash
# lib/telegram_bot.sh - Telegram Bot remote management integration
# Part of sbx-lite modular architecture
#
# Implements a long-polling Telegram Bot daemon for remote sing-box management.
# Supports /status, /users, /adduser, /removeuser, /restart, /help commands
# restricted to an admin chat_id whitelist persisted in state.json.
#
# Runs as an independent systemd unit (sbx-telegram-bot.service) alongside
# sing-box. Uses pure bash + curl + jq — no extra language runtime.
#
# Modes: long-polling only (no webhook); reuses lib/users.sh and lib/service.sh
# for all CRUD and service operations.
#
# Upstream docs:
#   https://core.telegram.org/bots/api
#   https://core.telegram.org/bots#botfather

set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_TELEGRAM_BOT_LOADED:-}" ]] && return 0
readonly _SBX_TELEGRAM_BOT_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -z "${_SBX_COMMON_LOADED:-}" ]] && source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_VALIDATION_LOADED:-}" ]] && source "${_LIB_DIR}/validation.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_USERS_LOADED:-}" ]] && source "${_LIB_DIR}/users.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_SERVICE_LOADED:-}" ]] && source "${_LIB_DIR}/service.sh"

#==============================================================================
# Constants
#==============================================================================

# Paths and tunables are overridable via environment for testability.
: "${SBX_TG_BIN:=/usr/local/bin/sbx-telegram-bot}"
: "${SBX_TG_SVC:=/etc/systemd/system/sbx-telegram-bot.service}"
: "${SBX_TG_ENV_FILE:=/etc/sing-box/telegram.env}"
: "${SBX_TG_OFFSET_DIR:=/var/lib/sbx-telegram-bot}"
: "${SBX_TG_OFFSET_FILE:=${SBX_TG_OFFSET_DIR}/offset}"
: "${SBX_TG_API_BASE:=https://api.telegram.org}"
: "${SBX_TG_POLL_TIMEOUT:=30}"
: "${SBX_TG_SERVICE_NAME:=sbx-telegram-bot}"

#==============================================================================
# Public API
#==============================================================================

# _tg_validate_token <token>
# Returns 0 iff token matches ^[0-9]{8,10}:[A-Za-z0-9_-]{35}$
# Telegram bot tokens have shape: <bot_id>:<35-char_secret>
# where bot_id is 8-10 digits and the secret half is base64url-ish
# (alphanumeric + '-' + '_'), exactly 35 characters long.
_tg_validate_token() {
  local token="${1:-}"
  [[ "${token}" =~ ^[0-9]{8,10}:[A-Za-z0-9_-]{35}$ ]]
}

# _tg_verify_token_live <token>
# Calls Bot API getMe; returns 0 iff response .ok == true.
_tg_verify_token_live() {
  local token="${1:-}"
  _tg_validate_token "${token}" || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local curl_cmd="${SBX_TG_CURL_CMD:-curl}"
  local response_file=""
  response_file=$(create_temp_file "tg-getme") || return 1
  # shellcheck disable=SC2064
  trap "rm -f '${response_file}'" RETURN

  if ! "${curl_cmd}" -fsS \
    --max-time 20 \
    --connect-timeout 10 \
    -o "${response_file}" \
    "${SBX_TG_API_BASE}/bot${token}/getMe" \
    2>/dev/null; then
    return 1
  fi

  local ok="false"
  ok=$(jq -r '.ok // false' "${response_file}" 2>/dev/null) || return 1
  [[ "${ok}" == "true" ]] || return 1

  jq -r '.result.username // empty' "${response_file}" 2>/dev/null || true
}

# _tg_state_file
# Resolves the active state.json path, honoring TEST_STATE_FILE for tests.
_tg_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"
}

# _tg_write_env_file <token>
# Persists BOT_TOKEN for systemd EnvironmentFile consumption.
_tg_write_env_file() {
  local token="${1:-}"
  [[ -n "${token}" ]] || {
    err "_tg_write_env_file: token is required"
    return 1
  }

  local env_dir=""
  env_dir="$(dirname "${SBX_TG_ENV_FILE}")"
  mkdir -p "${env_dir}" || return 1

  local tmp=""
  tmp=$(create_temp_file_in_dir "${env_dir}" "telegram.env") || return 1
  {
    echo "# Managed by sbx — do not edit by hand."
    echo "BOT_TOKEN=${token}"
  } >"${tmp}"
  chmod 600 "${tmp}" 2>/dev/null || true
  mv -f "${tmp}" "${SBX_TG_ENV_FILE}"
  chmod 600 "${SBX_TG_ENV_FILE}" 2>/dev/null || true
}

# _tg_write_service_file
# Writes the systemd unit consumed by telegram_bot_enable.
_tg_write_service_file() {
  local svc_dir=""
  svc_dir="$(dirname "${SBX_TG_SVC}")"
  mkdir -p "${svc_dir}" || return 1

  cat >"${SBX_TG_SVC}" <<EOF
[Unit]
Description=sbx-lite Telegram Bot
After=network-online.target sing-box.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SBX_TG_BIN}
EnvironmentFile=-${SBX_TG_ENV_FILE}
Restart=on-failure
RestartSec=5s
User=root
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/etc/sing-box ${SBX_TG_OFFSET_DIR}

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "${SBX_TG_SVC}" 2>/dev/null || true
}

# _tg_state_admin_ids_json
# Emits the current admin_chat_ids array as compact JSON.
_tg_state_admin_ids_json() {
  local state_file=""
  state_file="$(_tg_state_file)"
  if [[ -f "${state_file}" ]] && command -v jq >/dev/null 2>&1; then
    jq -c '(.telegram.admin_chat_ids // []) | map(tonumber? // .)' \
      "${state_file}" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

# _tg_state_get <field> [default]
# Reads a Telegram field from state.json, returning default on absence.
_tg_state_get() {
  local field="${1:-}"
  local default_value="${2:-}"
  local state_file=""
  state_file="$(_tg_state_file)"

  if [[ -z "${field}" ]] || [[ ! -f "${state_file}" ]] ||
    ! command -v jq >/dev/null 2>&1; then
    echo "${default_value}"
    return 0
  fi

  local value=""
  value=$(jq -r ".telegram.${field} // empty" "${state_file}" 2>/dev/null) || {
    echo "${default_value}"
    return 0
  }

  if [[ -n "${value}" ]]; then
    echo "${value}"
  else
    echo "${default_value}"
  fi
}

# _tg_is_authorized <chat_id>
# Returns 0 iff <chat_id> appears in .telegram.admin_chat_ids[] of state.json.
# Empty whitelist, missing block, missing file or missing jq all reject.
# This is the security boundary for every Telegram-driven action — be strict.
_tg_is_authorized() {
  local chat_id="${1:-}"
  [[ -n "${chat_id}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local state_file=""
  state_file=$(_tg_state_file)
  [[ -f "${state_file}" ]] || return 1

  local match=""
  match=$(jq -r --arg id "${chat_id}" \
    '(.telegram.admin_chat_ids // []) | map(tostring) | index($id) // empty' \
    "${state_file}" 2>/dev/null) || return 1
  [[ -n "${match}" ]]
}

# _tg_load_offset
# Echoes the last-seen update_id from SBX_TG_OFFSET_FILE.
# Defaults to "0" if the file is missing or contains non-integer garbage,
# which causes the next getUpdates call to fetch from the beginning.
_tg_load_offset() {
  if [[ -f "${SBX_TG_OFFSET_FILE}" ]]; then
    local v=""
    v=$(tr -d '[:space:]' <"${SBX_TG_OFFSET_FILE}" 2>/dev/null) || true
    if [[ "${v}" =~ ^-?[0-9]+$ ]]; then
      echo "${v}"
      return 0
    fi
  fi
  echo "0"
}

# _tg_save_offset <n>
# Atomically persists <n> to SBX_TG_OFFSET_FILE (mktemp + rename).
# Rejects non-integer input. Creates SBX_TG_OFFSET_DIR on first call.
# File is chmod'd to 0600 — offsets aren't sensitive, but the bot is root-only.
_tg_save_offset() {
  local n="${1:-}"
  [[ "${n}" =~ ^-?[0-9]+$ ]] || return 1

  mkdir -p "${SBX_TG_OFFSET_DIR}" 2>/dev/null || return 1

  local tmp=""
  tmp=$(mktemp "${SBX_TG_OFFSET_DIR}/.offset.XXXXXX") || return 1
  printf '%s\n' "${n}" >"${tmp}" || {
    rm -f "${tmp}"
    return 1
  }
  chmod 600 "${tmp}" 2>/dev/null || true
  mv -f "${tmp}" "${SBX_TG_OFFSET_FILE}"
}

# _tg_get_updates <offset> <output_file>
# POSTs to Bot API getUpdates with long-poll timeout; on transient curl
# failure (network blip, DNS hiccup, 5xx) sleeps with exponential backoff
# (1→2→4→8→16→30s, capped at 30s) and retries indefinitely. Tests can
# bound the loop with SBX_TG_BACKOFF_MAX_ATTEMPTS=N (0 = unlimited).
# Curl and sleep are injectable via SBX_TG_CURL_CMD / SBX_TG_SLEEP_CMD
# so unit tests can stub them without touching the real network or clock.
# BOT_TOKEN MUST be set in the environment (loaded by EnvironmentFile).
_tg_get_updates() {
  local offset="${1:-0}"
  local output_file="${2:-}"
  [[ -n "${output_file}" ]] || return 1
  [[ -n "${BOT_TOKEN:-}" ]] || return 1

  local curl_cmd="${SBX_TG_CURL_CMD:-curl}"
  local sleep_cmd="${SBX_TG_SLEEP_CMD:-sleep}"
  local max_attempts="${SBX_TG_BACKOFF_MAX_ATTEMPTS:-0}"
  local backoff=1
  local attempts=0

  while :; do
    attempts=$((attempts + 1))
    if "${curl_cmd}" -fsS \
      --max-time "$((SBX_TG_POLL_TIMEOUT + 10))" \
      --connect-timeout 10 \
      -o "${output_file}" \
      --data-urlencode "offset=${offset}" \
      --data-urlencode "timeout=${SBX_TG_POLL_TIMEOUT}" \
      "${SBX_TG_API_BASE}/bot${BOT_TOKEN}/getUpdates" \
      2>/dev/null; then
      return 0
    fi

    if [[ ${max_attempts} -gt 0 && ${attempts} -ge ${max_attempts} ]]; then
      return 1
    fi

    "${sleep_cmd}" "${backoff}" || true
    backoff=$((backoff * 2))
    [[ ${backoff} -gt 30 ]] && backoff=30
  done
}

# _tg_send_message <chat_id> <text>
# POSTs to Bot API sendMessage. On HTTP 429 (rate limit) parses
# .parameters.retry_after from the response body and sleeps once before
# retrying — at most one retry, so a sustained 429 storm doesn't loop us.
# All other non-2xx responses are reported as failure (caller may log them
# and continue; we don't want to spam-retry on permanent errors like 400).
# Curl and sleep are injectable for testability (see _tg_get_updates).
_tg_send_message() {
  local chat_id="${1:-}"
  local text="${2:-}"
  [[ -n "${chat_id}" && -n "${text}" ]] || return 1
  [[ -n "${BOT_TOKEN:-}" ]] || return 1

  local curl_cmd="${SBX_TG_CURL_CMD:-curl}"
  local sleep_cmd="${SBX_TG_SLEEP_CMD:-sleep}"

  local body_file=""
  body_file=$(mktemp -t sbx-tg-send.XXXXXX) || return 1
  # shellcheck disable=SC2064
  trap "rm -f '${body_file}'" RETURN

  local attempts=0
  local max_attempts=2 # initial + at most one 429 retry
  while [[ ${attempts} -lt ${max_attempts} ]]; do
    attempts=$((attempts + 1))
    local http_code=""
    http_code=$("${curl_cmd}" -sS \
      -o "${body_file}" \
      -w '%{http_code}' \
      --max-time 30 \
      --connect-timeout 10 \
      --data-urlencode "chat_id=${chat_id}" \
      --data-urlencode "text=${text}" \
      "${SBX_TG_API_BASE}/bot${BOT_TOKEN}/sendMessage" \
      2>/dev/null) || http_code="000"

    if [[ "${http_code}" == "200" ]]; then
      return 0
    fi

    if [[ "${http_code}" == "429" ]] && command -v jq >/dev/null 2>&1; then
      local retry_after=""
      retry_after=$(jq -r '.parameters.retry_after // 1' "${body_file}" 2>/dev/null)
      [[ "${retry_after}" =~ ^[0-9]+$ ]] || retry_after=1
      "${sleep_cmd}" "${retry_after}" || true
      continue
    fi

    return 1
  done
  return 1
}

# _tg_parse_command <text>
# Splits a Telegram message body into "<cmd> [args...]" tokens.
# Strips the "/" prefix and an optional "@botname" suffix
# (Telegram appends @botname when commands are sent in groups).
# Returns nonzero (no stdout) for empty input, lone "/", or any text
# that doesn't begin with /<letter|underscore><identifier>.
# stdout format: a single space-separated line; the dispatcher word-splits.
_tg_parse_command() {
  local text="${1:-}"
  [[ -n "${text}" ]] || return 1
  # Anchored regex: leading "/", required identifier, optional @botname,
  # optional whitespace + arg tail.
  [[ "${text}" =~ ^/([a-zA-Z_][a-zA-Z0-9_]*)(@[A-Za-z0-9_]+)?([[:space:]]+(.*))?$ ]] || return 1
  local cmd="${BASH_REMATCH[1]}"
  local rest="${BASH_REMATCH[4]:-}"
  # Trim trailing whitespace from rest so "/cmd   " doesn't leak spaces.
  rest="${rest%"${rest##*[![:space:]]}"}"
  if [[ -n "${rest}" ]]; then
    printf '%s %s\n' "${cmd}" "${rest}"
  else
    printf '%s\n' "${cmd}"
  fi
}

# _tg_dispatch_command <chat_id> <cmd> [args...]
# Pure case-based dispatch to _tg_handle_* functions. NEVER `eval` chat input.
# Authorization is enforced HERE, not per-handler: non-whitelisted senders
# get silent drop (no reply at all) so the bot can't be used to fingerprint
# the admin list. Unknown commands fall through to /help.
_tg_dispatch_command() {
  local chat_id="${1:-}"
  local cmd="${2:-}"
  shift 2 2>/dev/null || true

  [[ -n "${chat_id}" && -n "${cmd}" ]] || return 1

  # Security boundary — fail closed and silent.
  _tg_is_authorized "${chat_id}" || return 0

  case "${cmd}" in
    status) _tg_handle_status "${chat_id}" ;;
    users) _tg_handle_users "${chat_id}" ;;
    adduser) _tg_handle_adduser "${chat_id}" "${1:-}" ;;
    removeuser) _tg_handle_removeuser "${chat_id}" "${1:-}" ;;
    restart) _tg_handle_restart "${chat_id}" ;;
    help | start) _tg_handle_help "${chat_id}" ;;
    *) _tg_handle_help "${chat_id}" ;;
  esac
}

# _tg_handle_status <chat_id>
# Reports sing-box service activity using the existing service.sh helper.
_tg_handle_status() {
  local chat_id="${1:-}"
  local reply=""
  if check_service_status; then
    reply="✅ sing-box: active"
  else
    reply="❌ sing-box: inactive"
  fi
  _tg_send_message "${chat_id}" "${reply}"
}

# _tg_handle_users <chat_id>
# Forwards the user_list table verbatim. Output is small enough to fit in
# Telegram's 4096-char message limit for any realistic deployment.
_tg_handle_users() {
  local chat_id="${1:-}"
  local out=""
  if out=$(user_list 2>&1); then
    _tg_send_message "${chat_id}" "${out}"
  else
    _tg_send_message "${chat_id}" "❌ Failed to list users:
${out}"
  fi
}

# _tg_handle_adduser <chat_id> <name>
# Defense-in-depth: trim whitespace and re-validate the name before delegating
# to user_add (which already enforces ^[a-zA-Z0-9_-]+$). On success, mirror
# the sbx-manager.sh `user add` flow: sync_users_to_config + restart sing-box.
_tg_handle_adduser() {
  local chat_id="${1:-}"
  local name="${2:-}"

  # Trim leading/trailing whitespace.
  name="${name#"${name%%[![:space:]]*}"}"
  name="${name%"${name##*[![:space:]]}"}"

  if [[ -z "${name}" ]]; then
    _tg_send_message "${chat_id}" "Usage: /adduser <name>"
    return 0
  fi

  if ! [[ "${name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    _tg_send_message "${chat_id}" \
      "❌ Invalid name '${name}': use alphanumerics, _, - only"
    return 0
  fi

  local out=""
  if out=$(user_add --name "${name}" 2>&1); then
    sync_users_to_config 2>/dev/null || true
    systemctl restart sing-box 2>/dev/null || true
    _tg_send_message "${chat_id}" "✅ ${out}"
  else
    _tg_send_message "${chat_id}" "❌ ${out}"
  fi
}

# _tg_handle_removeuser <chat_id> <name_or_uuid>
_tg_handle_removeuser() {
  local chat_id="${1:-}"
  local id="${2:-}"

  id="${id#"${id%%[![:space:]]*}"}"
  id="${id%"${id##*[![:space:]]}"}"

  if [[ -z "${id}" ]]; then
    _tg_send_message "${chat_id}" "Usage: /removeuser <name|uuid>"
    return 0
  fi

  local out=""
  if out=$(user_remove "${id}" 2>&1); then
    sync_users_to_config 2>/dev/null || true
    systemctl restart sing-box 2>/dev/null || true
    _tg_send_message "${chat_id}" "✅ ${out}"
  else
    _tg_send_message "${chat_id}" "❌ ${out}"
  fi
}

# _tg_handle_restart <chat_id>
# Delegates to restart_service (already flock-protected by service.sh).
_tg_handle_restart() {
  local chat_id="${1:-}"
  local out=""
  if out=$(restart_service 2>&1); then
    _tg_send_message "${chat_id}" "✅ sing-box restarted"
  else
    _tg_send_message "${chat_id}" "❌ Restart failed:
${out}"
  fi
}

# _tg_handle_help <chat_id>
_tg_handle_help() {
  local chat_id="${1:-}"
  local reply
  reply="sbx-lite Telegram Bot — available commands:

/status — show sing-box service status
/users — list configured users
/adduser <name> — add a new user
/removeuser <name|uuid> — remove a user
/restart — restart sing-box service
/help — show this help"
  _tg_send_message "${chat_id}" "${reply}"
}

# _tg_update_state <key>=<value> [<key>=<value> ...]
# Atomically merges each pair into state.json's .telegram object using a
# single jq invocation (mktemp → jq → chmod → mv), mirroring the
# cloudflared_update_state pattern at lib/cloudflare_tunnel.sh:317-359.
#
# Allowed keys (allowlist — keeps state shape predictable, prevents typos
# from polluting the file): enabled, username, admin_chat_ids.
#
# Value typing is auto-detected:
#   true / false / null / <integer>    → JSON literal (--argjson)
#   leading [ or {                     → JSON literal (--argjson)
#   anything else                      → JSON string  (--arg)
#
# Missing state file is a warn-and-skip (return 0) so the bot doesn't
# explode on a fresh install where state.json was wiped — matches
# cloudflared_update_state semantics.
_tg_update_state() {
  local state_file=""
  state_file=$(_tg_state_file)

  if [[ ! -f "${state_file}" ]]; then
    warn "State file not found (${state_file}); skipping telegram state update"
    return 0
  fi

  command -v jq >/dev/null 2>&1 || {
    err "jq is required to update telegram state"
    return 1
  }

  [[ $# -ge 1 ]] || {
    err "_tg_update_state: no key=value pairs given"
    return 1
  }

  local jq_args=()
  local merge="(.telegram // {})"
  local n=0
  local kv key val arg
  for kv in "$@"; do
    [[ "${kv}" == *"="* ]] || {
      err "_tg_update_state: '${kv}' is not key=value"
      return 1
    }
    key="${kv%%=*}"
    val="${kv#*=}"

    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
      err "_tg_update_state: invalid key '${key}'"
      return 1
    }

    case "${key}" in
      enabled | username | admin_chat_ids) ;;
      *)
        err "_tg_update_state: key '${key}' not in allowlist"
        return 1
        ;;
    esac

    n=$((n + 1))
    arg="a${n}"

    if [[ "${val}" == "true" || "${val}" == "false" || "${val}" == "null" ||
      "${val}" =~ ^-?[0-9]+$ ||
      "${val}" =~ ^\[ ||
      "${val}" =~ ^\{ ]]; then
      jq_args+=(--argjson "${arg}" "${val}")
    else
      jq_args+=(--arg "${arg}" "${val}")
    fi

    merge="${merge} + {${key}: \$${arg}}"
  done

  local filter=". + {telegram: (${merge})}"

  local tmp=""
  tmp=$(mktemp "${state_file}.XXXXXX") || return 1
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}'" RETURN

  if ! jq "${jq_args[@]}" "${filter}" "${state_file}" >"${tmp}" 2>/dev/null; then
    err "_tg_update_state: jq filter failed"
    return 1
  fi

  mv -f "${tmp}" "${state_file}"
  chmod "${SECURE_FILE_PERMISSIONS:-600}" "${state_file}" 2>/dev/null || true
}

# _tg_process_updates_file <file> <offset_var_name>
# Parses getUpdates JSON, dispatches commands, and advances the offset.
_tg_process_updates_file() {
  local updates_file="${1:-}"
  local offset_var_name="${2:-}"
  [[ -n "${updates_file}" && -n "${offset_var_name}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local current_offset="0"
  current_offset="${!offset_var_name}"

  local update_json=""
  while IFS= read -r update_json; do
    [[ -n "${update_json}" ]] || continue

    local update_id=""
    local chat_id=""
    local text=""
    update_id=$(jq -r '.update_id // empty' <<<"${update_json}" 2>/dev/null) || continue
    [[ "${update_id}" =~ ^[0-9]+$ ]] || continue

    current_offset="$((update_id + 1))"
    printf -v "${offset_var_name}" '%s' "${current_offset}"
    TG_LAST_OFFSET="${current_offset}"
    _tg_save_offset "${current_offset}" || true

    chat_id=$(jq -r '.message.chat.id // empty' <<<"${update_json}" 2>/dev/null) || true
    text=$(jq -r '.message.text // empty' <<<"${update_json}" 2>/dev/null) || true
    [[ -n "${chat_id}" && -n "${text}" ]] || continue

    local parsed=""
    parsed=$(_tg_parse_command "${text}" 2>/dev/null || true)
    [[ -n "${parsed}" ]] || continue

    local parts=()
    read -r -a parts <<<"${parsed}"
    _tg_dispatch_command "${chat_id}" "${parts[@]}" || true
  done < <(jq -c '.result[]?' "${updates_file}" 2>/dev/null)
}

# _tg_discard_bootstrap_updates <file> <offset_var_name>
# First startup uses offset=-1 to discard backlog. We still need to advance
# the saved offset to the newest observed update_id, but MUST NOT dispatch any
# historical commands from that bootstrap response.
_tg_discard_bootstrap_updates() {
  local updates_file="${1:-}"
  local offset_var_name="${2:-}"
  [[ -n "${updates_file}" && -n "${offset_var_name}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local next_offset="0"
  next_offset=$(jq -r '
    (.result // []) |
    if length == 0 then 0 else ((.[-1].update_id // -1) + 1) end
  ' "${updates_file}" 2>/dev/null) || return 1
  [[ "${next_offset}" =~ ^[0-9]+$ ]] || next_offset=0

  printf -v "${offset_var_name}" '%s' "${next_offset}"
  TG_LAST_OFFSET="${next_offset}"
  _tg_save_offset "${next_offset}" || return 1
}

#==============================================================================
# Public API
#==============================================================================

# telegram_bot_setup
# Interactive bootstrap: prompts for bot token, verifies via getMe,
# persists to state.json + EnvironmentFile.
telegram_bot_setup() {
  need_root || return 1

  local token=""
  local admin_chat_id=""
  local username=""

  read -r -p "Telegram bot token: " token || return 1
  if ! _tg_validate_token "${token}"; then
    err "Invalid Telegram bot token format"
    return 1
  fi

  username="$(_tg_verify_token_live "${token}")" || {
    err "Telegram getMe verification failed for the provided token"
    return 1
  }

  read -r -p "Initial admin chat ID: " admin_chat_id || return 1
  if ! [[ "${admin_chat_id}" =~ ^-?[0-9]+$ ]]; then
    err "Admin chat ID must be an integer"
    return 1
  fi

  _tg_write_env_file "${token}" || return 1
  _tg_update_state \
    "enabled=false" \
    "username=${username}" \
    "admin_chat_ids=[${admin_chat_id}]" || return 1

  success "  ✓ Telegram bot configured for @${username}"
}

# telegram_bot_enable
# Writes systemd unit, daemon-reload, enable --now.
telegram_bot_enable() {
  need_root || return 1

  [[ -x "${SBX_TG_BIN}" ]] || {
    err "Telegram bot launcher not installed: ${SBX_TG_BIN}"
    return 1
  }
  [[ -f "${SBX_TG_ENV_FILE}" ]] || {
    err "Telegram env file not found: ${SBX_TG_ENV_FILE}"
    return 1
  }

  mkdir -p "${SBX_TG_OFFSET_DIR}" || return 1
  chmod 700 "${SBX_TG_OFFSET_DIR}" 2>/dev/null || true

  _tg_write_service_file || return 1
  systemctl daemon-reload || {
    err "systemctl daemon-reload failed"
    return 1
  }
  systemctl enable --now "${SBX_TG_SERVICE_NAME}" || {
    err "Failed to start ${SBX_TG_SERVICE_NAME} service"
    err "Inspect: journalctl -u ${SBX_TG_SERVICE_NAME} -n 80 --no-pager"
    return 1
  }

  _tg_update_state "enabled=true" || return 1
  success "  ✓ Telegram bot enabled"
}

# telegram_bot_disable
# Stop + disable + remove systemd unit; update state.json.
telegram_bot_disable() {
  need_root || return 1

  systemctl disable --now "${SBX_TG_SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SBX_TG_SVC}"
  systemctl daemon-reload 2>/dev/null || true

  _tg_update_state "enabled=false" || return 1
  success "  ✓ Telegram bot disabled"
}

# telegram_bot_status
# Show systemd status, whitelist size, bot username.
telegram_bot_status() {
  local username=""
  local enabled="false"
  local admin_count="0"

  username="$(_tg_state_get username "(unknown)")"
  enabled="$(_tg_state_get enabled "false")"
  if command -v jq >/dev/null 2>&1 && [[ -f "$(_tg_state_file)" ]]; then
    admin_count=$(jq -r '(.telegram.admin_chat_ids // []) | length' \
      "$(_tg_state_file)" 2>/dev/null || echo "0")
  fi

  echo "=== Telegram Bot Status ==="
  if [[ -x "${SBX_TG_BIN}" ]]; then
    echo "Binary   : ${SBX_TG_BIN}"
  else
    echo "Binary   : (not installed)"
  fi
  echo "Enabled  : ${enabled}"
  echo "Username : ${username}"
  echo "Admins   : ${admin_count}"
  echo "Env file : ${SBX_TG_ENV_FILE}"
  systemctl status "${SBX_TG_SERVICE_NAME}" --no-pager || true
}

# telegram_bot_logs
# Tail journalctl for the service unit.
telegram_bot_logs() {
  journalctl -u "${SBX_TG_SERVICE_NAME}" -f
}

# telegram_bot_admin_add <chat_id>
telegram_bot_admin_add() {
  need_root || return 1

  local chat_id="${1:-}"
  [[ "${chat_id}" =~ ^-?[0-9]+$ ]] || {
    err "Usage: telegram_bot_admin_add <chat_id>"
    return 1
  }

  local state_file=""
  state_file="$(_tg_state_file)"
  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    err "jq is required to modify Telegram admin_chat_ids"
    return 1
  }

  local admins_json=""
  admins_json=$(jq -c --argjson id "${chat_id}" \
    '(.telegram.admin_chat_ids // []) | map(tonumber? // .) |
     if index($id) == null then . + [$id] else . end' \
    "${state_file}" 2>/dev/null) || return 1

  _tg_update_state "admin_chat_ids=${admins_json}" || return 1
  success "  ✓ Added Telegram admin chat ID: ${chat_id}"
}

# telegram_bot_admin_remove <chat_id>
telegram_bot_admin_remove() {
  need_root || return 1

  local chat_id="${1:-}"
  [[ "${chat_id}" =~ ^-?[0-9]+$ ]] || {
    err "Usage: telegram_bot_admin_remove <chat_id>"
    return 1
  }

  local state_file=""
  state_file="$(_tg_state_file)"
  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    err "jq is required to modify Telegram admin_chat_ids"
    return 1
  }

  local admins_json=""
  admins_json=$(jq -c --argjson id "${chat_id}" \
    '(.telegram.admin_chat_ids // []) | map(tonumber? // .) |
     map(select(. != $id))' \
    "${state_file}" 2>/dev/null) || return 1

  _tg_update_state "admin_chat_ids=${admins_json}" || return 1
  success "  ✓ Removed Telegram admin chat ID: ${chat_id}"
}

# telegram_bot_admin_list
telegram_bot_admin_list() {
  local admins_json=""
  admins_json="$(_tg_state_admin_ids_json)"

  echo "Configured Telegram admin chat IDs:"
  if [[ "${admins_json}" == "[]" ]]; then
    echo "(none)"
    return 0
  fi

  jq -r '.[]' <<<"${admins_json}" 2>/dev/null || true
}

# telegram_bot_run
# Main loop invoked by the systemd unit (ExecStart target).
telegram_bot_run() {
  [[ -n "${BOT_TOKEN:-}" ]] || {
    err "BOT_TOKEN is required in the environment"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    err "jq is required for telegram_bot_run"
    return 1
  }

  local offset="0"
  if [[ -f "${SBX_TG_OFFSET_FILE}" ]]; then
    offset="$(_tg_load_offset)"
  else
    offset="-1"
  fi

  while :; do
    local updates_file=""
    updates_file=$(create_temp_file "tg-updates") || return 1

    if ! _tg_get_updates "${offset}" "${updates_file}"; then
      rm -f "${updates_file}"
      return 1
    fi

    if [[ "${offset}" == "-1" ]]; then
      _tg_discard_bootstrap_updates "${updates_file}" offset || {
        rm -f "${updates_file}"
        return 1
      }
    else
      _tg_process_updates_file "${updates_file}" offset || {
        rm -f "${updates_file}"
        return 1
      }
    fi

    rm -f "${updates_file}"

    if [[ "${SBX_TG_RUN_ONCE:-0}" == "1" ]]; then
      break
    fi
  done
}

#==============================================================================
# Export public functions
#==============================================================================

export -f telegram_bot_setup
export -f telegram_bot_enable
export -f telegram_bot_disable
export -f telegram_bot_status
export -f telegram_bot_logs
export -f telegram_bot_admin_add
export -f telegram_bot_admin_remove
export -f telegram_bot_admin_list
export -f telegram_bot_run
