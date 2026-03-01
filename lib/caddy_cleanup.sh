#!/usr/bin/env bash
# lib/caddy_cleanup.sh - Caddy cleanup/uninstall utilities
# Migration tool: removes legacy Caddy installations from pre-1.13.0 setups
# sing-box 1.13.0+ uses native ACME, Caddy is no longer needed

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CADDY_CLEANUP_LOADED:-}" ]] && return 0
readonly _SBX_CADDY_CLEANUP_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Caddy Cleanup Functions
#==============================================================================

# Determine Caddy data directory based on service user
# Caddy stores certificates and state here
_caddy_data_dir() {
  local user_home=""
  user_home=$(getent passwd "root" | cut -d: -f6)
  if [[ -z "$user_home" ]]; then
    user_home="/root"
  fi
  echo "${user_home}/.local/share/caddy"
}

# Remove legacy Caddy installation completely
# Called during uninstall if Caddy binary is detected
caddy_uninstall() {
  msg "Removing Caddy..."

  # Stop and disable services
  systemctl stop caddy 2>/dev/null || true
  systemctl disable caddy 2>/dev/null || true
  systemctl stop caddy-cert-sync.timer 2>/dev/null || true
  systemctl disable caddy-cert-sync.timer 2>/dev/null || true

  # Remove binaries and configs
  rm -f /usr/local/bin/caddy
  rm -f /etc/systemd/system/caddy.service
  rm -f /etc/systemd/system/caddy-cert-sync.service
  rm -f /etc/systemd/system/caddy-cert-sync.timer
  rm -f /usr/local/bin/caddy-cert-sync
  rm -rf /usr/local/etc/caddy

  # Preserve certificate data with warning
  local data_dir=""
  data_dir=$(_caddy_data_dir)
  warn "Certificate data preserved in: ${data_dir}"
  warn "Remove manually if needed: rm -rf ${data_dir}"

  systemctl daemon-reload

  success "Caddy removed successfully"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f caddy_uninstall
