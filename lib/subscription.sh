#!/usr/bin/env bash
# lib/subscription.sh - Adaptive subscription endpoint management
# Part of sbx-lite modular architecture
#
# Provides a lightweight HTTP endpoint that auto-detects the requesting
# client from the User-Agent header and returns the matching format:
#   - Base64-encoded URI list (V2Ray family, default)
#   - Clash Meta YAML (Clash/Mihomo/Stash)
#   - Plain URI list (Shadowrocket/Quantumult/Surge/Loon)
#
# The HTTP listener is a minimal python3 script under lib/subscription/,
# run by a systemd unit as an unprivileged system user. Rendered payloads
# are cached under SUBSCRIPTION_CACHE_DIR so the server never touches
# state.json directly.
#
# Functions defined here are also used by the CLI (`sbx subscription ...`)
# and by render-time regeneration hooks in bin/sbx-manager.sh.

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_SUBSCRIPTION_LOADED:-}" ]] && return 0
readonly _SBX_SUBSCRIPTION_LOADED=1

# Source dependencies (common is idempotent, export may already be loaded)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
if [[ -z "${_SBX_EXPORT_LOADED:-}" ]]; then
  # shellcheck source=/dev/null
  source "${_LIB_DIR}/export.sh"
fi

#==============================================================================
# Paths and constants
#==============================================================================

_subscription_cache_dir() {
  echo "${SUB_CACHE_DIR_OVERRIDE:-${SUBSCRIPTION_CACHE_DIR}}"
}

_subscription_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR}/state.json}}"
}

_subscription_unit_path() {
  echo "/etc/systemd/system/${SUBSCRIPTION_SERVICE_NAME}.service"
}

# Launcher/helper install paths (installed by install_manager_script())
_SUBSCRIPTION_SERVER_BIN="/usr/local/bin/sbx-sub-server"
_SUBSCRIPTION_SERVER_PY="/usr/local/lib/sbx/subscription/server.py"

#==============================================================================
# User-Agent -> format mapping
#==============================================================================

# Pick subscription format based on a User-Agent string.
# Returns one of: clash | uri | base64
# Pure-bash so it is unit-testable without spawning Python.
_subscription_pick_format() {
  local ua="${1:-}"
  local lc=''
  # Lowercase, handle locale-safely
  lc="$(printf '%s' "${ua}" | tr '[:upper:]' '[:lower:]')"

  case "${lc}" in
    *clash* | *meta* | *stash* | *mihomo*)
      echo "clash"
      return 0
      ;;
    *shadowrocket* | *quantumult* | *surge* | *loon*)
      echo "uri"
      return 0
      ;;
    *)
      echo "base64"
      return 0
      ;;
  esac
}

#==============================================================================
# Token generation
#==============================================================================

# Generate a URL-safe hex token (32 chars / 128 bits by default).
_subscription_generate_token() {
  local bytes=$((SUBSCRIPTION_TOKEN_LENGTH / 2))
  local token=''

  if have openssl; then
    token=$(openssl rand -hex "${bytes}" 2>/dev/null || true)
  fi
  if [[ -z "${token}" && -r /dev/urandom ]]; then
    token=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c "${SUBSCRIPTION_TOKEN_LENGTH}" || true)
  fi
  if [[ -z "${token}" ]] && have python3; then
    token=$(python3 -c "import secrets; print(secrets.token_hex(${bytes}))")
  fi

  [[ -n "${token}" ]] || {
    if declare -f err >/dev/null 2>&1; then
      err "Failed to generate subscription token (no openssl/urandom/python3)"
    else
      echo "[ERR] Failed to generate subscription token" >&2
    fi
    return 1
  }

  printf '%s' "${token}"
}

_subscription_validate_token() {
  local token="$1"
  [[ "${token}" =~ ^[a-f0-9]{16,128}$ ]]
}

#==============================================================================
# Render
#==============================================================================

# subscription_render <format>
#
# Print the subscription body for the given format on stdout. Reuses
# export_uri / export_clash_yaml so we never duplicate format generation.
#
# Format:
#   base64 - newline-joined URI list, base64 (-w 0) encoded
#   clash  - Clash Meta YAML (same as `sbx export clash`)
#   uri    - newline-joined URI list, plain text
subscription_render() {
  local format="${1:-base64}"
  local uris=''

  load_client_info >/dev/null

  case "${format}" in
    clash)
      export_clash_yaml
      return 0
      ;;
    uri | base64)
      uris=$(export_uri reality)
      if [[ "${WS_ENABLED:-false}" == "true" && -n "${WS_PORT:-}" ]]; then
        uris+=$'\n'$(export_uri ws)
      fi
      if [[ "${HY2_ENABLED:-false}" == "true" && -n "${HY2_PORT:-}" ]]; then
        uris+=$'\n'$(export_uri hy2)
      fi
      if [[ "${TUIC_ENABLED:-false}" == "true" ]]; then
        uris+=$'\n'$(export_uri tuic)
      fi
      if [[ "${TROJAN_ENABLED:-false}" == "true" ]]; then
        uris+=$'\n'$(export_uri trojan)
      fi

      if [[ "${format}" == "base64" ]]; then
        printf '%s' "${uris}" | base64 -w 0 2>/dev/null || printf '%s' "${uris}" | base64 | tr -d '\n'
        echo
      else
        printf '%s\n' "${uris}"
      fi
      return 0
      ;;
    *)
      if declare -f _export_die >/dev/null 2>&1; then
        _export_die "SBX-SUB-001" "Unknown subscription format: ${format}" \
          "Use one of: base64, clash, uri."
      else
        echo "[ERR] Unknown subscription format: ${format}" >&2
        return 1
      fi
      ;;
  esac
}

#==============================================================================
# Cache
#==============================================================================

# Refresh the three cached payloads under SUBSCRIPTION_CACHE_DIR.
# No-op when subscription is disabled (avoids stray files after `off`).
subscription_refresh_cache() {
  local cache_dir=''
  local state_file=''
  local enabled='false'
  local owner_user="${SUB_SYSTEM_USER_OVERRIDE:-${SUBSCRIPTION_SYSTEM_USER}}"
  local tmp=''

  cache_dir=$(_subscription_cache_dir)
  state_file=$(_subscription_state_file)

  if [[ -f "${state_file}" ]] && have jq; then
    enabled=$(jq -r '.subscription.enabled // false' "${state_file}" 2>/dev/null || echo false)
  fi
  if [[ "${enabled}" != "true" ]]; then
    return 0
  fi

  mkdir -p "${cache_dir}"
  chmod 750 "${cache_dir}" 2>/dev/null || true

  local formats=(base64 clash uri)
  local ext
  local fmt
  for fmt in "${formats[@]}"; do
    case "${fmt}" in
      base64) ext="base64" ;;
      clash) ext="clash.yaml" ;;
      uri) ext="uri.txt" ;;
    esac
    tmp=$(mktemp "${cache_dir}/.${ext}.XXXXXX") || return 1
    if ! subscription_render "${fmt}" >"${tmp}" 2>/dev/null; then
      rm -f "${tmp}"
      continue
    fi
    chmod 640 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${cache_dir}/${ext}"
  done

  # Best-effort chown so the unprivileged HTTP process can read the cache.
  # Skipped silently in test mode (non-root).
  if [[ -z "${SUB_CACHE_DIR_OVERRIDE:-}" ]] && [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    if id -u "${owner_user}" >/dev/null 2>&1; then
      chown -R "root:${owner_user}" "${cache_dir}" 2>/dev/null || true
    fi
  fi
}

#==============================================================================
# State mutation helpers
#==============================================================================

# Read a subscription field from state.json ("" if missing).
_subscription_state_get() {
  local field="$1"
  local state_file=''
  state_file=$(_subscription_state_file)
  [[ -f "${state_file}" ]] || {
    echo ""
    return 0
  }
  have jq || {
    echo ""
    return 0
  }
  jq -r ".subscription.${field} // empty" "${state_file}" 2>/dev/null || echo ""
}

# Atomically update a single subscription field in state.json.
# Usage: _subscription_state_set_string <field> <value>
#        _subscription_state_set_json   <field> <json-literal>
_subscription_state_set_string() {
  local field="$1"
  local value="$2"
  local state_file=''
  local tmp=''
  state_file=$(_subscription_state_file)
  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }
  have jq || {
    err "jq required to update state.json"
    return 1
  }
  tmp=$(mktemp) || return 1
  if ! jq --arg v "${value}" ".subscription.${field} = \$v" "${state_file}" >"${tmp}"; then
    rm -f "${tmp}"
    err "Failed to update state.json field subscription.${field}"
    return 1
  fi
  mv -f "${tmp}" "${state_file}"
  chmod 600 "${state_file}" 2>/dev/null || true
}

_subscription_state_set_json() {
  local field="$1"
  local json_literal="$2"
  local state_file=''
  local tmp=''
  state_file=$(_subscription_state_file)
  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }
  have jq || {
    err "jq required to update state.json"
    return 1
  }
  tmp=$(mktemp) || return 1
  if ! jq --argjson v "${json_literal}" ".subscription.${field} = \$v" "${state_file}" >"${tmp}"; then
    rm -f "${tmp}"
    err "Failed to update state.json field subscription.${field}"
    return 1
  fi
  mv -f "${tmp}" "${state_file}"
  chmod 600 "${state_file}" 2>/dev/null || true
}

# Merge a default subscription block into state.json if it's missing.
# Called from save_state_info() so that fresh installs have the block with
# enabled=false. Re-invocable and idempotent.
subscription_ensure_state_block() {
  local state_file=''
  local tmp=''
  state_file=$(_subscription_state_file)
  [[ -f "${state_file}" ]] || return 0
  have jq || return 0

  if jq -e '.subscription | type == "object"' "${state_file}" >/dev/null 2>&1; then
    return 0
  fi

  tmp=$(mktemp) || return 1
  if ! jq \
    --argjson port "${SUBSCRIPTION_PORT_DEFAULT}" \
    --arg bind "${SUBSCRIPTION_BIND_DEFAULT}" \
    --arg path "${SUBSCRIPTION_PATH_DEFAULT}" \
    '.subscription = {
        enabled: false,
        port: $port,
        bind: $bind,
        token: "",
        path: $path,
        created_at: null
      }' "${state_file}" >"${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  mv -f "${tmp}" "${state_file}"
  chmod 600 "${state_file}" 2>/dev/null || true
}

#==============================================================================
# Systemd unit
#==============================================================================

subscription_install_unit() {
  local unit_path=''
  local bind=''
  local port=''
  local user="${SUB_SYSTEM_USER_OVERRIDE:-${SUBSCRIPTION_SYSTEM_USER}}"
  unit_path=$(_subscription_unit_path)

  bind=$(_subscription_state_get bind)
  port=$(_subscription_state_get port)
  [[ -n "${bind}" ]] || bind="${SUBSCRIPTION_BIND_DEFAULT}"
  [[ -n "${port}" ]] || port="${SUBSCRIPTION_PORT_DEFAULT}"

  if [[ -n "${SUB_UNIT_DRY_RUN:-}" ]]; then
    return 0
  fi

  cat >"${unit_path}" <<EOF
[Unit]
Description=sbx adaptive subscription endpoint
After=network.target
Wants=network.target

[Service]
Type=simple
User=${user}
Group=${user}
ExecStart=${_SUBSCRIPTION_SERVER_BIN}
Environment=SBX_SUB_CACHE_DIR=$(_subscription_cache_dir)
Environment=SBX_SUB_STATE_FILE=$(_subscription_state_file)
Restart=on-failure
RestartSec=3s
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$(_subscription_cache_dir)

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "${unit_path}"
  systemctl daemon-reload >/dev/null 2>&1 || true
}

subscription_remove_unit() {
  local unit_path=''
  unit_path=$(_subscription_unit_path)

  if [[ -n "${SUB_UNIT_DRY_RUN:-}" ]]; then
    return 0
  fi

  systemctl stop "${SUBSCRIPTION_SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SUBSCRIPTION_SERVICE_NAME}" 2>/dev/null || true
  rm -f "${unit_path}"
  systemctl daemon-reload >/dev/null 2>&1 || true
}

#==============================================================================
# CLI-facing commands
#==============================================================================

# sbx subscription on [--rotate]
#
# Generate a token (if absent or --rotate), persist enabled=true, render cache,
# install+start the unit.
subscription_enable() {
  local rotate=0
  local arg=''
  for arg in "$@"; do
    case "${arg}" in
      --rotate) rotate=1 ;;
    esac
  done

  subscription_ensure_state_block || return 1

  local token=''
  token=$(_subscription_state_get token)
  if [[ -z "${token}" || "${rotate}" -eq 1 ]]; then
    token=$(_subscription_generate_token) || return 1
    _subscription_state_set_string token "${token}" || return 1
  fi

  # Apply bind/port overrides from environment if provided
  if [[ -n "${SUB_BIND:-}" ]]; then
    _subscription_state_set_string bind "${SUB_BIND}" || return 1
  fi
  if [[ -n "${SUB_PORT:-}" ]]; then
    _subscription_state_set_json port "${SUB_PORT}" || return 1
  fi

  local now=''
  now=$(date -Iseconds 2>/dev/null || date)
  _subscription_state_set_string created_at "${now}" || true
  _subscription_state_set_json enabled true || return 1

  subscription_refresh_cache || true
  subscription_install_unit || return 1

  if [[ -z "${SUB_UNIT_DRY_RUN:-}" ]]; then
    systemctl enable "${SUBSCRIPTION_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl restart "${SUBSCRIPTION_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  if declare -f success >/dev/null 2>&1; then
    success "Subscription endpoint enabled"
  else
    echo "Subscription endpoint enabled"
  fi
  subscription_url
}

# sbx subscription off
subscription_disable() {
  _subscription_state_set_json enabled false || return 1

  if [[ -z "${SUB_UNIT_DRY_RUN:-}" ]]; then
    systemctl stop "${SUBSCRIPTION_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl disable "${SUBSCRIPTION_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  # Purge cached payloads so stopping really means stopping
  local cache_dir=''
  cache_dir=$(_subscription_cache_dir)
  if [[ -d "${cache_dir}" ]]; then
    rm -f "${cache_dir}/base64" "${cache_dir}/clash.yaml" "${cache_dir}/uri.txt" 2>/dev/null || true
  fi

  if declare -f success >/dev/null 2>&1; then
    success "Subscription endpoint disabled"
  else
    echo "Subscription endpoint disabled"
  fi
}

# sbx subscription rotate
subscription_rotate() {
  local token=''
  token=$(_subscription_generate_token) || return 1
  _subscription_state_set_string token "${token}" || return 1
  subscription_refresh_cache || true

  # Restart to pick up any related changes (token validation is file-backed)
  if [[ -z "${SUB_UNIT_DRY_RUN:-}" ]]; then
    if [[ "$(_subscription_state_get enabled)" == "true" ]]; then
      systemctl restart "${SUBSCRIPTION_SERVICE_NAME}" >/dev/null 2>&1 || true
    fi
  fi

  if declare -f success >/dev/null 2>&1; then
    success "Subscription token rotated"
  else
    echo "Subscription token rotated"
  fi
  subscription_url
}

# sbx subscription status
subscription_status() {
  local enabled=''
  local bind=''
  local port=''
  local token=''
  local active='unknown'
  enabled=$(_subscription_state_get enabled)
  bind=$(_subscription_state_get bind)
  port=$(_subscription_state_get port)
  token=$(_subscription_state_get token)

  if [[ -z "${SUB_UNIT_DRY_RUN:-}" ]] && have systemctl; then
    active=$(systemctl is-active "${SUBSCRIPTION_SERVICE_NAME}" 2>/dev/null || echo "inactive")
  fi

  local masked='(none)'
  if [[ -n "${token}" ]]; then
    masked="${token:0:6}…${token: -4}"
  fi

  echo "Subscription:"
  echo "  Enabled: ${enabled:-false}"
  echo "  Active : ${active}"
  echo "  Bind   : ${bind:-${SUBSCRIPTION_BIND_DEFAULT}}"
  echo "  Port   : ${port:-${SUBSCRIPTION_PORT_DEFAULT}}"
  echo "  Token  : ${masked}"
}

# sbx subscription url
subscription_url() {
  local bind=''
  local port=''
  local token=''
  local path=''
  local host=''

  bind=$(_subscription_state_get bind)
  port=$(_subscription_state_get port)
  token=$(_subscription_state_get token)
  path=$(_subscription_state_get path)

  [[ -n "${bind}" ]] || bind="${SUBSCRIPTION_BIND_DEFAULT}"
  [[ -n "${port}" ]] || port="${SUBSCRIPTION_PORT_DEFAULT}"
  [[ -n "${path}" ]] || path="${SUBSCRIPTION_PATH_DEFAULT}"

  if [[ "${bind}" == "0.0.0.0" || "${bind}" == "::" ]]; then
    if have jq; then
      host=$(jq -r '.server.domain // .server.ip // empty' "$(_subscription_state_file)" 2>/dev/null || echo "")
    fi
    [[ -n "${host}" ]] || host="<server-ip-or-domain>"
  else
    host="${bind}"
  fi

  if [[ -z "${token}" ]]; then
    echo "http://${host}:${port}${path}"
  else
    echo "http://${host}:${port}${path}/${token}"
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f subscription_render subscription_refresh_cache
export -f subscription_enable subscription_disable subscription_rotate
export -f subscription_status subscription_url
export -f subscription_install_unit subscription_remove_unit
export -f subscription_ensure_state_block
export -f _subscription_pick_format
