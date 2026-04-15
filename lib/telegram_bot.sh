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
# Public API (stubs — to be implemented in subsequent steps)
#==============================================================================

# telegram_bot_setup
# Interactive bootstrap: prompts for bot token, verifies via getMe,
# persists to state.json + EnvironmentFile.
telegram_bot_setup() {
  err "telegram_bot_setup: not implemented yet"
  return 1
}

# telegram_bot_enable
# Writes systemd unit, daemon-reload, enable --now.
telegram_bot_enable() {
  err "telegram_bot_enable: not implemented yet"
  return 1
}

# telegram_bot_disable
# Stop + disable + remove systemd unit; update state.json.
telegram_bot_disable() {
  err "telegram_bot_disable: not implemented yet"
  return 1
}

# telegram_bot_status
# Show systemd status, whitelist size, bot username.
telegram_bot_status() {
  err "telegram_bot_status: not implemented yet"
  return 1
}

# telegram_bot_logs
# Tail journalctl for the service unit.
telegram_bot_logs() {
  err "telegram_bot_logs: not implemented yet"
  return 1
}

# telegram_bot_admin_add <chat_id>
telegram_bot_admin_add() {
  err "telegram_bot_admin_add: not implemented yet"
  return 1
}

# telegram_bot_admin_remove <chat_id>
telegram_bot_admin_remove() {
  err "telegram_bot_admin_remove: not implemented yet"
  return 1
}

# telegram_bot_admin_list
telegram_bot_admin_list() {
  err "telegram_bot_admin_list: not implemented yet"
  return 1
}

# telegram_bot_run
# Main loop invoked by the systemd unit (ExecStart target).
telegram_bot_run() {
  err "telegram_bot_run: not implemented yet"
  return 1
}

#==============================================================================
# Internal helpers (stubs — to be implemented in subsequent steps)
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
  return 1
}

# _tg_state_file
# Resolves the active state.json path, honoring TEST_STATE_FILE for tests.
_tg_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"
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

# _tg_get_updates <offset>
# Calls getUpdates with long-poll timeout; exponential backoff on failure.
_tg_get_updates() {
  return 1
}

# _tg_send_message <chat_id> <text>
# Sends a message; handles 429 retry_after.
_tg_send_message() {
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
# Pure case-based dispatch to _tg_handle_* functions.
_tg_dispatch_command() {
  return 1
}

# _tg_handle_status <chat_id>
_tg_handle_status() {
  return 1
}

# _tg_handle_users <chat_id>
_tg_handle_users() {
  return 1
}

# _tg_handle_adduser <chat_id> <name>
_tg_handle_adduser() {
  return 1
}

# _tg_handle_removeuser <chat_id> <name_or_uuid>
_tg_handle_removeuser() {
  return 1
}

# _tg_handle_restart <chat_id>
_tg_handle_restart() {
  return 1
}

# _tg_handle_help <chat_id>
_tg_handle_help() {
  return 1
}

# _tg_update_state <key>=<value>...
# Atomically merges bot state into state.json (mktemp→jq→chmod→mv).
_tg_update_state() {
  return 1
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
