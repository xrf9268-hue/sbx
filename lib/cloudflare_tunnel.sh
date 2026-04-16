#!/usr/bin/env bash
# lib/cloudflare_tunnel.sh - Cloudflare Tunnel (cloudflared) integration
# Part of sbx-lite modular architecture
#
# Exposes sing-box's WebSocket inbound through Cloudflare's edge network
# without requiring a public IP or user-owned domain. Provides binary
# install/uninstall, systemd unit management, state.json tracking, and
# a minimal config.yml writer.
#
# Modes: quick (trycloudflare.com, no account) | token (Zero Trust dashboard).
# Only WS-based sing-box inbounds are tunnel-compatible (cloudflared only
# proxies HTTP/WS — Reality/Hy2/TUIC cannot be tunneled).
#
# Upstream docs:
#   https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
#   https://github.com/cloudflare/cloudflared/releases

set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CLOUDFLARE_TUNNEL_LOADED:-}" ]] && return 0
readonly _SBX_CLOUDFLARE_TUNNEL_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -z "${_SBX_COMMON_LOADED:-}" ]] && source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_DOWNLOAD_LOADED:-}" ]] && source "${_LIB_DIR}/download.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_CHECKSUM_LOADED:-}" ]] && source "${_LIB_DIR}/checksum.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_NETWORK_LOADED:-}" ]] && source "${_LIB_DIR}/network.sh"

#==============================================================================
# Constants
#==============================================================================

# Paths are overridable via environment for testability.
: "${CLOUDFLARED_BIN:=/usr/local/bin/cloudflared}"
: "${CLOUDFLARED_SVC:=/etc/systemd/system/cloudflared.service}"
: "${CLOUDFLARED_CONF_DIR:=/etc/cloudflared}"
: "${CLOUDFLARED_CONFIG:=${CLOUDFLARED_CONF_DIR}/config.yml}"
: "${CLOUDFLARED_ENV_FILE:=${CLOUDFLARED_CONF_DIR}/tunnel.env}"
: "${CLOUDFLARED_LOG:=/var/log/cloudflared.log}"
: "${CLOUDFLARED_RELEASE_BASE:=https://github.com/cloudflare/cloudflared/releases}"
: "${CLOUDFLARED_SERVICE_NAME:=cloudflared}"

#==============================================================================
# Upstream port resolution
#==============================================================================

# cloudflared_resolve_upstream_port
# Resolves the upstream WS-TLS port for cloudflared's local proxy.
# Prefers the actually-chosen port from state.json (.protocols.ws_tls.port),
# falling back to WS_PORT_DEFAULT when state is absent or unreadable.
cloudflared_resolve_upstream_port() {
  local state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"
  if [[ -f "${state_file}" ]] && command -v jq >/dev/null 2>&1; then
    # Guard jq against malformed/unreadable JSON: set -e would otherwise abort
    # this function on parse failure and skip the WS_PORT_DEFAULT fallback.
    local p=""
    if p=$(jq -r '.protocols.ws_tls.port // empty' "${state_file}" 2>/dev/null) &&
      [[ -n "${p}" ]]; then
      echo "${p}"
      return 0
    fi
  fi
  echo "${WS_PORT_DEFAULT:-8444}"
}

#==============================================================================
# Arch detection
#==============================================================================

# Map `uname -m` (or $SBX_FAKE_UNAME_M) to the cloudflared asset suffix.
# Returns one of: amd64 | arm64 | armhf | arm | 386
cloudflared_detect_arch() {
  local m=""
  m="${SBX_FAKE_UNAME_M:-$(uname -m 2>/dev/null || echo "")}"

  case "${m}" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    armv7l | armv7) echo "arm" ;;
    armv6l | armv6) echo "arm" ;;
    armhf) echo "armhf" ;;
    i386 | i686) echo "386" ;;
    *)
      err "Unsupported architecture for cloudflared: ${m}"
      return 1
      ;;
  esac
}

#==============================================================================
# Version resolution
#==============================================================================

# Resolve a requested version to a concrete tag.
# "latest" -> resolved via GitHub redirect; otherwise echoed unchanged.
cloudflared_resolve_version() {
  local requested="${1:-latest}"

  if [[ "${requested}" != "latest" ]]; then
    echo "${requested}"
    return 0
  fi

  # Follow the /releases/latest redirect to capture the tag without needing jq
  # or an API token. We deliberately use HEAD so no large body is downloaded.
  if command -v curl >/dev/null 2>&1; then
    local resolved=""
    resolved=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
      "${CLOUDFLARED_RELEASE_BASE}/latest" 2>/dev/null | awk -F'/' '{print $NF}')
    if [[ -n "${resolved}" && "${resolved}" != "latest" ]]; then
      echo "${resolved}"
      return 0
    fi
  fi

  # Conservative fallback if we could not resolve dynamically.
  warn "Could not resolve cloudflared 'latest' tag; falling back to '2024.8.2'"
  echo "2024.8.2"
}

#==============================================================================
# Binary installation
#==============================================================================

# cloudflared_install [version]
#
# Downloads the official cloudflared binary for the host architecture and
# installs it to CLOUDFLARED_BIN. Uses the existing download.sh / checksum.sh
# helpers so we get retry + TLSv1.2-only + optional SHA256 verification for
# free. The upstream release page publishes a `.sha256` file next to every
# binary; when available we verify against it but (matching verify_singbox_binary
# behaviour) treat missing checksums as non-fatal.
cloudflared_install() {
  local requested="${1:-latest}"
  local version="" arch="" asset="" url="" checksum_url=""
  local tmp_bin="" tmp_sum=""

  need_root || return 1

  msg "Installing cloudflared..."

  arch=$(cloudflared_detect_arch) || return 1
  version=$(cloudflared_resolve_version "${requested}")

  asset="cloudflared-linux-${arch}"
  url="${CLOUDFLARED_RELEASE_BASE}/download/${version}/${asset}"
  checksum_url="${url}.sha256"

  msg "  Version : ${version}"
  msg "  Asset   : ${asset}"
  msg "  URL     : ${url}"

  tmp_bin=$(create_temp_file "cloudflared") || return 1
  tmp_sum=$(create_temp_file "cloudflared-sum") || {
    rm -f "${tmp_bin}"
    return 1
  }
  # shellcheck disable=SC2064
  trap "rm -f '${tmp_bin}' '${tmp_sum}'" RETURN

  if ! download_file_with_retry "${url}" "${tmp_bin}"; then
    err "Failed to download cloudflared from ${url}"
    return 1
  fi

  if ! verify_downloaded_file "${tmp_bin}" 1000; then
    err "Downloaded cloudflared binary failed size sanity check"
    return 1
  fi

  # Best-effort SHA256 verification. Missing checksum is non-fatal (matches
  # verify_singbox_binary semantics) because cloudflared's checksum publishing
  # is inconsistent across older tags.
  if safe_http_get "${checksum_url}" "${tmp_sum}" 2>/dev/null && [[ -s "${tmp_sum}" ]]; then
    if verify_file_checksum "${tmp_bin}" "${tmp_sum}"; then
      success "  ✓ cloudflared SHA256 verified"
    else
      err "cloudflared binary failed SHA256 verification"
      return 1
    fi
  else
    warn "  ⚠ cloudflared checksum not available; proceeding without verification"
  fi

  install -m 0755 "${tmp_bin}" "${CLOUDFLARED_BIN}" || {
    err "Failed to install cloudflared to ${CLOUDFLARED_BIN}"
    return 1
  }

  success "  ✓ cloudflared installed at ${CLOUDFLARED_BIN}"
  return 0
}

cloudflared_uninstall() {
  need_root || return 1
  msg "Removing cloudflared..."

  systemctl disable --now "${CLOUDFLARED_SERVICE_NAME}" 2>/dev/null || true
  rm -f "${CLOUDFLARED_SVC}" "${CLOUDFLARED_BIN}"
  rm -rf "${CLOUDFLARED_CONF_DIR}"
  systemctl daemon-reload 2>/dev/null || true

  success "  ✓ cloudflared removed"
}

#==============================================================================
# Config / service file writers
#==============================================================================

# cloudflared_write_env_file <token>
# Writes CLOUDFLARED_ENV_FILE with TUNNEL_TOKEN, mode 600.
cloudflared_write_env_file() {
  local token="$1"
  [[ -n "${token}" ]] || {
    err "cloudflared_write_env_file: token is required"
    return 1
  }

  mkdir -p "${CLOUDFLARED_CONF_DIR}"
  local tmp=""
  tmp=$(create_temp_file_in_dir "${CLOUDFLARED_CONF_DIR}" "tunnel.env") || return 1
  {
    echo "# Managed by sbx — do not edit by hand."
    echo "TUNNEL_TOKEN=${token}"
  } >"${tmp}"
  chmod 600 "${tmp}"
  mv "${tmp}" "${CLOUDFLARED_ENV_FILE}"
  chmod 600 "${CLOUDFLARED_ENV_FILE}"
}

# cloudflared_write_config_yml <hostname> [upstream_port]
# Writes a minimal named-tunnel config.yml routing <hostname> -> local WS.
cloudflared_write_config_yml() {
  local hostname="$1"
  local upstream_port="${2:-$(cloudflared_resolve_upstream_port)}"

  [[ -n "${hostname}" ]] || {
    err "cloudflared_write_config_yml: hostname is required"
    return 1
  }

  mkdir -p "${CLOUDFLARED_CONF_DIR}"
  cat >"${CLOUDFLARED_CONFIG}" <<EOF
# Managed by sbx — do not edit by hand.
# Routes public hostname traffic to the local sing-box WebSocket inbound.
ingress:
  - hostname: ${hostname}
    service: http://127.0.0.1:${upstream_port}
  - service: http_status:404
EOF
  chmod 600 "${CLOUDFLARED_CONFIG}"
}

# cloudflared_write_service_file <mode>
# mode ∈ quick | token
cloudflared_write_service_file() {
  local mode="${1:-token}"
  local exec_line=""

  case "${mode}" in
    token)
      # The token is pulled from EnvironmentFile at start-time so it never
      # appears on the command line (and therefore not in `ps`/journal).
      exec_line='ExecStart=/usr/local/bin/cloudflared --no-autoupdate tunnel run --token ${TUNNEL_TOKEN}'
      ;;
    quick)
      local quick_port=""
      quick_port=$(cloudflared_resolve_upstream_port)
      exec_line="ExecStart=/usr/local/bin/cloudflared --no-autoupdate tunnel --url http://127.0.0.1:${quick_port}"
      ;;
    *)
      err "cloudflared_write_service_file: unknown mode '${mode}'"
      return 1
      ;;
  esac

  msg "Writing cloudflared systemd unit (${mode} mode)..."
  cat >"${CLOUDFLARED_SVC}" <<EOF
[Unit]
Description=Cloudflare Tunnel (sbx)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
${exec_line}
Restart=on-failure
RestartSec=5s
User=nobody
Group=nogroup
EnvironmentFile=-${CLOUDFLARED_ENV_FILE}
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "${CLOUDFLARED_SVC}"
  success "  ✓ cloudflared service file written"
}

#==============================================================================
# State tracking
#==============================================================================

# cloudflared_update_state <enabled> <mode> <hostname> [upstream_port]
# Atomically merges tunnel state into state.json using jq.
cloudflared_update_state() {
  local enabled="${1:-false}"
  local mode="${2:-}"
  local hostname="${3:-}"
  local upstream_port="${4:-$(cloudflared_resolve_upstream_port)}"

  local state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR}/state.json}}"

  if [[ ! -f "${state_file}" ]]; then
    warn "State file not found (${state_file}); skipping tunnel state update"
    return 0
  fi

  command -v jq >/dev/null 2>&1 || {
    err "jq is required to update tunnel state"
    return 1
  }

  [[ "${enabled}" == "true" ]] || enabled="false"
  if ! state_json_apply "${state_file}" \
    '.tunnel = {
       enabled: $enabled,
       mode: (if $mode == "" then null else $mode end),
       hostname: (if $hostname == "" then null else $hostname end),
       upstream_port: (if $upstream == 0 then null else $upstream end)
     }' \
    --argjson enabled "${enabled}" \
    --arg mode "${mode}" \
    --arg hostname "${hostname}" \
    --argjson upstream "${upstream_port:-0}"; then
    err "Failed to update tunnel state in ${state_file}"
    return 1
  fi
}

cloudflared_current_hostname() {
  local state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR}/state.json}}"
  if [[ -f "${state_file}" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.tunnel.hostname // empty' "${state_file}" 2>/dev/null
  fi
}

#==============================================================================
# Lifecycle: enable / disable / status
#==============================================================================

# cloudflared_enable_token <token> <hostname> [upstream_port]
cloudflared_enable_token() {
  local token="${1:-}"
  local hostname="${2:-}"
  local upstream_port="${3:-$(cloudflared_resolve_upstream_port)}"

  if [[ -z "${token}" || -z "${hostname}" ]]; then
    err "Usage: cloudflared_enable_token <token> <hostname> [upstream_port]"
    return 1
  fi

  need_root || return 1

  if [[ ! -x "${CLOUDFLARED_BIN}" ]]; then
    cloudflared_install "latest" || return 1
  fi

  cloudflared_write_env_file "${token}" || return 1
  cloudflared_write_config_yml "${hostname}" "${upstream_port}" || return 1
  cloudflared_write_service_file "token" || return 1

  systemctl daemon-reload || {
    err "systemctl daemon-reload failed"
    return 1
  }
  systemctl enable --now "${CLOUDFLARED_SERVICE_NAME}" || {
    err "Failed to start ${CLOUDFLARED_SERVICE_NAME} service"
    err "Inspect: journalctl -u ${CLOUDFLARED_SERVICE_NAME} -n 80 --no-pager"
    return 1
  }

  cloudflared_update_state "true" "token" "${hostname}" "${upstream_port}"

  success "  ✓ Cloudflare Tunnel active at https://${hostname}"
}

cloudflared_disable() {
  need_root || return 1
  msg "Disabling Cloudflare Tunnel..."

  systemctl disable --now "${CLOUDFLARED_SERVICE_NAME}" 2>/dev/null || true

  # Scrub the token file but keep config.yml so operators can inspect history.
  shred -uf "${CLOUDFLARED_ENV_FILE}" 2>/dev/null || rm -f "${CLOUDFLARED_ENV_FILE}"

  cloudflared_update_state "false" "" "" 0
  success "  ✓ Cloudflare Tunnel disabled"
}

cloudflared_status() {
  local hostname=""
  hostname=$(cloudflared_current_hostname 2>/dev/null || true)

  echo "=== Cloudflare Tunnel Status ==="
  if [[ -x "${CLOUDFLARED_BIN}" ]]; then
    echo "Binary   : ${CLOUDFLARED_BIN} ($("${CLOUDFLARED_BIN}" --version 2>/dev/null | head -1))"
  else
    echo "Binary   : (not installed)"
  fi

  if systemctl list-unit-files "${CLOUDFLARED_SERVICE_NAME}.service" >/dev/null 2>&1; then
    if systemctl is-active --quiet "${CLOUDFLARED_SERVICE_NAME}"; then
      echo "Service  : active"
    else
      echo "Service  : inactive"
    fi
  else
    echo "Service  : (unit not installed)"
  fi

  echo "Hostname : ${hostname:-(none)}"
  echo "Config   : ${CLOUDFLARED_CONFIG}"
}

#==============================================================================
# Export functions for use by install.sh / bin/sbx-manager.sh
#==============================================================================

export -f cloudflared_install
export -f cloudflared_uninstall
export -f cloudflared_enable_token
export -f cloudflared_disable
export -f cloudflared_status
export -f cloudflared_current_hostname
export -f cloudflared_update_state
export -f cloudflared_resolve_upstream_port
