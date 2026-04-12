#!/usr/bin/env bash
# lib/users.sh - Multi-user UUID management
# Part of sbx-lite modular architecture
#
# Provides CRUD operations for managing multiple users in state.json,
# and syncing the users array into sing-box config.json inbounds.

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_USERS_LOADED:-}" ]] && return 0
readonly _SBX_USERS_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/generators.sh"

#==============================================================================
# Internal Helpers
#==============================================================================

# Return the path to the active state file (supports test override via TEST_STATE_FILE)
_resolve_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-/etc/sing-box/state.json}}"
}

# Return the path to the active config file (supports test override via TEST_CONFIG_FILE)
_resolve_config_file() {
  echo "${TEST_CONFIG_FILE:-${SB_CONF:-/etc/sing-box/config.json}}"
}

# Load users array from state.json.
# If the users array is absent (legacy install), auto-migrates from the
# top-level .protocols.reality.uuid field.
# Outputs a JSON array to stdout; echoes '[]' when no state file exists.
_load_users() {
  local state_file=''
  state_file=$(_resolve_state_file)

  if [[ ! -f "${state_file}" ]]; then
    echo '[]'
    return 0
  fi

  # Prefer structured users array
  local users=''
  users=$(jq -r '.protocols.reality.users // empty' "${state_file}" 2>/dev/null || true)

  if [[ -n "${users}" && "${users}" != "null" ]]; then
    echo "${users}"
    return 0
  fi

  # Legacy migration: wrap single uuid in a users array
  local legacy_uuid=''
  legacy_uuid=$(jq -r '.protocols.reality.uuid // empty' "${state_file}" 2>/dev/null || true)

  if [[ -n "${legacy_uuid}" ]]; then
    local installed_at=''
    installed_at=$(jq -r '.installed_at // empty' "${state_file}" 2>/dev/null || true)
    jq -n \
      --arg uuid "${legacy_uuid}" \
      --arg created_at "${installed_at}" \
      '[{name: "default", uuid: $uuid, created_at: (if $created_at == "" then null else $created_at end)}]'
    return 0
  fi

  echo '[]'
}

# Write users_json back to state.json atomically.
# Also updates .protocols.reality.uuid to the first user's UUID for backward
# compatibility with load_client_info() in lib/export.sh.
#
# Args: users_json (JSON array string)
_save_users() {
  local users_json="$1"
  local state_file=''
  state_file=$(_resolve_state_file)

  if [[ ! -f "${state_file}" ]]; then
    err "State file not found: ${state_file}"
    return 1
  fi

  local first_uuid=''
  first_uuid=$(echo "${users_json}" | jq -r '.[0].uuid // empty' 2>/dev/null || true)

  local tmp_file=''
  tmp_file=$(mktemp "${state_file}.XXXXXX")

  if jq \
    --argjson users "${users_json}" \
    --arg first_uuid "${first_uuid}" \
    '.protocols.reality.users = $users |
     if $first_uuid != "" then .protocols.reality.uuid = $first_uuid else . end' \
    "${state_file}" >"${tmp_file}" 2>/dev/null; then
    chmod 600 "${tmp_file}"
    # Skip ownership enforcement in test mode (TEST_STATE_FILE set)
    if [[ -z "${TEST_STATE_FILE:-}" ]]; then
      chown root:root "${tmp_file}" 2>/dev/null || true
    fi
    mv "${tmp_file}" "${state_file}"
  else
    rm -f "${tmp_file}"
    err "Failed to update state file"
    return 1
  fi
}

#==============================================================================
# Public CRUD Functions
#==============================================================================

# Add a new user with a freshly generated UUID.
#
# Usage: user_add [--name NAME]
# If --name is omitted, auto-names the user as user1, user2, etc.
user_add() {
  local name=''

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        [[ -n "${2:-}" ]] || {
          err "Flag --name requires a value"
          return 1
        }
        name="$2"
        shift 2
        ;;
      *)
        err "Unknown option: $1"
        return 1
        ;;
    esac
  done

  local users=''
  users=$(_load_users)

  # Auto-generate name if not provided
  if [[ -z "${name}" ]]; then
    local count=0
    count=$(echo "${users}" | jq 'length')
    name="user$((count + 1))"
  fi

  # Validate name characters
  if ! [[ "${name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    err "Invalid user name '${name}': use alphanumeric characters, underscores, or dashes only"
    return 1
  fi

  # Check name uniqueness
  local existing=''
  existing=$(echo "${users}" | jq -r --arg name "${name}" '.[] | select(.name == $name) | .name' 2>/dev/null || true)
  if [[ -n "${existing}" ]]; then
    err "User with name '${name}' already exists"
    return 1
  fi

  local uuid=''
  uuid=$(generate_uuid) || {
    err "Failed to generate UUID"
    return 1
  }

  local created_at=''
  created_at=$(date -Iseconds 2>/dev/null || date)

  local new_user=''
  new_user=$(jq -n \
    --arg name "${name}" \
    --arg uuid "${uuid}" \
    --arg created_at "${created_at}" \
    '{name: $name, uuid: $uuid, created_at: $created_at}')

  local updated_users=''
  updated_users=$(echo "${users}" | jq --argjson user "${new_user}" '. + [$user]')

  _save_users "${updated_users}" || return 1

  echo "Added user: ${name} (${uuid})"
}

# List all users in a formatted table.
#
# Usage: user_list
user_list() {
  local users=''
  users=$(_load_users)

  local count=0
  count=$(echo "${users}" | jq 'length')

  if [[ "${count}" -eq 0 ]]; then
    echo "No users configured."
    return 0
  fi

  printf "%-20s %-36s %s\n" "NAME" "UUID" "CREATED"
  printf "%-20s %-36s %s\n" "--------------------" "------------------------------------" "-------"

  while IFS=$'\t' read -r name uuid created_at; do
    printf "%-20s %-36s %s\n" "${name}" "${uuid}" "${created_at}"
  done < <(echo "${users}" | jq -r '.[] | [(.name // "?"), .uuid, (.created_at // "?")] | @tsv')
}

# Remove a user by UUID or name.
# Refuses to remove the last remaining user.
#
# Usage: user_remove <UUID|NAME>
user_remove() {
  local id="${1:-}"
  [[ -n "${id}" ]] || {
    err "Usage: user_remove <UUID|NAME>"
    return 1
  }

  local users=''
  users=$(_load_users)

  local count=0
  count=$(echo "${users}" | jq 'length')

  if [[ "${count}" -le 1 ]]; then
    err "Cannot remove the last user"
    return 1
  fi

  # Find user and remove in one pass
  local found_info=''
  found_info=$(echo "${users}" | jq -r --arg id "${id}" \
    '(.[] | select(.uuid == $id or .name == $id) | [(.name // "?"), .uuid]) | @tsv' 2>/dev/null | head -1 || true)

  if [[ -z "${found_info}" ]]; then
    err "User not found: ${id}"
    return 1
  fi

  local found_name='' found_uuid=''
  IFS=$'\t' read -r found_name found_uuid <<<"${found_info}"

  local updated_users=''
  updated_users=$(echo "${users}" | jq --arg id "${id}" \
    '[.[] | select(.uuid != $id and .name != $id)]')

  _save_users "${updated_users}" || return 1

  echo "Removed user: ${found_name} (${found_uuid})"
}

# Regenerate the UUID for an existing user.
# The user's name and creation timestamp are preserved.
#
# Usage: user_reset <UUID|NAME>
user_reset() {
  local id="${1:-}"
  [[ -n "${id}" ]] || {
    err "Usage: user_reset <UUID|NAME>"
    return 1
  }

  local users=''
  users=$(_load_users)

  # Find user by UUID or name
  local found_info=''
  found_info=$(echo "${users}" | jq -r --arg id "${id}" \
    '(.[] | select(.uuid == $id or .name == $id) | [(.name // "?"), .uuid]) | @tsv' 2>/dev/null | head -1 || true)

  if [[ -z "${found_info}" ]]; then
    err "User not found: ${id}"
    return 1
  fi

  local found_name='' old_uuid=''
  IFS=$'\t' read -r found_name old_uuid <<<"${found_info}"

  local new_uuid=''
  new_uuid=$(generate_uuid) || {
    err "Failed to generate UUID"
    return 1
  }

  local updated_users=''
  updated_users=$(echo "${users}" | jq \
    --arg id "${id}" \
    --arg new_uuid "${new_uuid}" \
    '[.[] | if (.uuid == $id or .name == $id) then .uuid = $new_uuid else . end]')

  _save_users "${updated_users}" || return 1

  echo "Reset user ${found_name}: new UUID = ${new_uuid}"
}

#==============================================================================
# Config Sync
#==============================================================================

# Sync the users array from state.json into config.json inbounds in-place.
# Updates the users array for in-reality and in-ws inbounds without requiring
# a full reinstall.
#
# Usage: sync_users_to_config [config_file]
sync_users_to_config() {
  local config_file="${1:-}"
  [[ -z "${config_file}" ]] && config_file=$(_resolve_config_file)

  local state_file=''
  state_file=$(_resolve_state_file)

  if [[ ! -f "${config_file}" ]]; then
    err "Config file not found: ${config_file}"
    return 1
  fi

  if [[ ! -f "${state_file}" ]]; then
    err "State file not found: ${state_file}"
    return 1
  fi

  local users=''
  users=$(_load_users)

  local flow="${REALITY_FLOW_VISION:-xtls-rprx-vision}"

  # Build both reality (uuid+flow) and ws (uuid-only) user arrays in one jq call
  local sb_users=''
  sb_users=$(echo "${users}" | jq --arg flow "${flow}" \
    '{reality: [.[] | {uuid: .uuid, flow: $flow}], ws: [.[] | {uuid: .uuid}]}')

  local tmp_file=''
  tmp_file=$(mktemp "${config_file}.XXXXXX")

  if echo "${sb_users}" | jq --slurpfile cfg "${config_file}" \
    '$cfg[0] |
     (.inbounds[] | select(.tag == "in-reality") | .users) = input.reality |
     (.inbounds[] | select(.tag == "in-ws") | .users) = input.ws' \
    >"${tmp_file}" 2>/dev/null; then
    chmod 600 "${tmp_file}"
    mv "${tmp_file}" "${config_file}"
    return 0
  else
    rm -f "${tmp_file}"
    err "Failed to sync users to config.json"
    return 1
  fi
}
