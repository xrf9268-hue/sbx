#!/usr/bin/env bash
# lib/common.sh - Core utilities and global variables
# Part of sbx-lite modular architecture v2.2.0
#
# This is the core module that provides constants, global variables,
# and essential utility functions.
# It also loads the colors, logging, and generators modules.

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_COMMON_LOADED:-}" ]] && return 0
readonly _SBX_COMMON_LOADED=1

# Source colors first (needed by logging)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/colors.sh"

#==============================================================================
# Global Constants
#==============================================================================

declare -r SB_BIN="/usr/local/bin/sing-box"
declare -r SB_CONF_DIR="/etc/sing-box"
declare -r SB_CONF="$SB_CONF_DIR/config.json"
declare -r SB_SVC="/etc/systemd/system/sing-box.service"
declare -r CLIENT_INFO="$SB_CONF_DIR/client-info.txt"

# Default ports
declare -r REALITY_PORT_DEFAULT=443
declare -r WS_PORT_DEFAULT=8444
declare -r HY2_PORT_DEFAULT=8443

# Fallback ports
declare -r REALITY_PORT_FALLBACK=24443
declare -r WS_PORT_FALLBACK=24444
declare -r HY2_PORT_FALLBACK=24445

# Default values
declare -r SNI_DEFAULT="${SNI_DEFAULT:-www.microsoft.com}"
declare -r CERT_DIR_BASE="${CERT_DIR_BASE:-/etc/ssl/sbx}"
declare -r LOG_LEVEL="${LOG_LEVEL:-warn}"

# Operation timeouts and retry limits
declare -r NETWORK_TIMEOUT_SEC=5
declare -r SERVICE_STARTUP_MAX_WAIT_SEC=10
declare -r SERVICE_PORT_VALIDATION_MAX_RETRIES=5
declare -r PORT_ALLOCATION_MAX_RETRIES=3
declare -r PORT_ALLOCATION_RETRY_DELAY_SEC=2
declare -r CLEANUP_OLD_FILES_MIN=60
declare -r BACKUP_RETENTION_DAYS=30
declare -r CADDY_CERT_WAIT_TIMEOUT_SEC=60

# Download configuration (some constants defined in install_multi.sh early boot)
# DOWNLOAD_CONNECT_TIMEOUT_SEC, DOWNLOAD_MAX_TIMEOUT_SEC, MIN_MODULE_FILE_SIZE_BYTES
# are defined in install_multi.sh before module loading
[[ -z "${HTTP_TIMEOUT_SEC:-}" ]] && declare -r HTTP_TIMEOUT_SEC=30
[[ -z "${DEFAULT_PARALLEL_JOBS:-}" ]] && declare -r DEFAULT_PARALLEL_JOBS=5

# File permissions (octal) - defined in install_multi.sh for early use
# SECURE_DIR_PERMISSIONS and SECURE_FILE_PERMISSIONS are already readonly

# Input validation limits
[[ -z "${MAX_INPUT_LENGTH:-}" ]] && declare -r MAX_INPUT_LENGTH=256
[[ -z "${MAX_DOMAIN_LENGTH:-}" ]] && declare -r MAX_DOMAIN_LENGTH=253

# Service operation wait times
[[ -z "${SERVICE_WAIT_SHORT_SEC:-}" ]] && declare -r SERVICE_WAIT_SHORT_SEC=1
[[ -z "${SERVICE_WAIT_MEDIUM_SEC:-}" ]] && declare -r SERVICE_WAIT_MEDIUM_SEC=2

#==============================================================================
# Reality Protocol Constants
#==============================================================================

# Reality configuration defaults
declare -r REALITY_DEFAULT_SNI="www.microsoft.com"
declare -r REALITY_DEFAULT_HANDSHAKE_PORT=443
declare -r REALITY_MAX_TIME_DIFF="1m"
declare -r REALITY_FLOW_VISION="xtls-rprx-vision"

# Reality validation constraints
declare -r REALITY_SHORT_ID_MIN_LENGTH=1
declare -r REALITY_SHORT_ID_MAX_LENGTH=8

# ALPN protocols for Reality
declare -r REALITY_ALPN_H2="h2"
declare -r REALITY_ALPN_HTTP11="http/1.1"

# Reality fingerprint options
declare -r REALITY_FINGERPRINT_CHROME="chrome"
declare -r REALITY_FINGERPRINT_FIREFOX="firefox"
declare -r REALITY_FINGERPRINT_SAFARI="safari"
declare -r REALITY_FINGERPRINT_DEFAULT="$REALITY_FINGERPRINT_CHROME"

#==============================================================================
# Global Variables (from environment)
#==============================================================================

DOMAIN="${DOMAIN:-}"
CERT_MODE="${CERT_MODE:-}"
CF_Token="${CF_Token:-}"
CF_Zone_ID="${CF_Zone_ID:-}"
CF_Account_ID="${CF_Account_ID:-}"
CERT_FORCE="${CERT_FORCE:-0}"

CERT_FULLCHAIN="${CERT_FULLCHAIN:-}"
CERT_KEY="${CERT_KEY:-}"

REALITY_PORT="${REALITY_PORT:-$REALITY_PORT_DEFAULT}"
WS_PORT="${WS_PORT:-$WS_PORT_DEFAULT}"
HY2_PORT="${HY2_PORT:-$HY2_PORT_DEFAULT}"

SINGBOX_VERSION="${SINGBOX_VERSION:-}"

# Dynamic variables (generated during installation)
UUID="${UUID:-}"
PRIV="${PRIV:-}"
PUB="${PUB:-}"
SID="${SID:-}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SHORT_ID="${SHORT_ID:-}"
HY2_PASS="${HY2_PASS:-}"
SNI="${SNI:-}"
REALITY_PORT_CHOSEN="${REALITY_PORT_CHOSEN:-}"
WS_PORT_CHOSEN="${WS_PORT_CHOSEN:-}"
HY2_PORT_CHOSEN="${HY2_PORT_CHOSEN:-}"

# Process-specific temporary directory for secure cleanup
# Created with secure permissions and cleaned up automatically
SBX_TMP_DIR="${SBX_TMP_DIR:-}"

#==============================================================================
# Utility Functions
#==============================================================================

# Check if running as root
need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root (sudo)."
}

# Check if command exists
have() {
  command -v "$1" >/dev/null 2>&1
}

# Safe temporary directory cleanup
safe_rm_temp() {
  local temp_path="$1"
  [[ -n "$temp_path" && "$temp_path" != "/" && "$temp_path" =~ ^/tmp/ ]] || return 1
  [[ -d "$temp_path" ]] && rm -rf "$temp_path" 2>/dev/null || true
}

# Get file size in bytes (cross-platform)
# Supports both Linux (stat -c%s) and BSD/macOS (stat -f%z)
# Args:
#   $1 - file path
# Returns:
#   File size in bytes, or "0" if file doesn't exist or error occurs
# Example:
#   size=$(get_file_size "/path/to/file")
get_file_size() {
  local file="$1"

  # Validate file exists
  [[ -f "$file" ]] || {
    echo "0"
    return 1
  }

  # Cross-platform file size retrieval
  # Linux: stat -c%s
  # BSD/macOS: stat -f%z
  stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
}

#==============================================================================
# Cleanup Handler
#==============================================================================

cleanup() {
  local exit_code=$?

  # Skip error reporting in test mode (tests manage their own error reporting)
  if [[ $exit_code -ne 0 && -z "${SBX_TEST_MODE:-}" ]]; then
    # err() function will be available from logging.sh
    if declare -f err >/dev/null 2>&1; then
      err "Script execution failed with exit code $exit_code"
    else
      echo "[ERR] Script execution failed with exit code $exit_code" >&2
    fi
  fi

  # Clean up process-specific temporary directory (safe)
  if [[ -n "${SBX_TMP_DIR:-}" && -d "$SBX_TMP_DIR" ]]; then
    # Verify it's a safe path before removal
    if [[ "$SBX_TMP_DIR" =~ ^/tmp/sbx-[a-zA-Z0-9._-]+$ ]]; then
      rm -rf "$SBX_TMP_DIR" 2>/dev/null || true
    fi
  fi

  # Clean up known temporary config files (specific to this process)
  rm -f "${SB_CONF}.tmp" 2>/dev/null || true

  # Remove temporary installer directory created during one-liner bootstrap
  if [[ -n "${INSTALLER_TEMP_DIR:-}" && -d "${INSTALLER_TEMP_DIR}" ]]; then
    # Validate: Must be in a temp directory and contain PID pattern for safety
    if [[ "${INSTALLER_TEMP_DIR}" =~ ^(/tmp|/var/tmp)/sbx-install-[0-9]+$ ]]; then
      if ! rm -rf "${INSTALLER_TEMP_DIR}" 2>/dev/null; then
        if declare -f warn >/dev/null 2>&1; then
          warn "Failed to cleanup temporary installer directory: ${INSTALLER_TEMP_DIR}"
        fi
      fi
    else
      if declare -f warn >/dev/null 2>&1; then
        warn "Skipping cleanup of INSTALLER_TEMP_DIR (path validation failed): ${INSTALLER_TEMP_DIR}"
      fi
    fi
  fi

  # Clean up stale port lock files (over 60 minutes old, with safe timeout)
  # This is safe because it only removes very old locks that are likely orphaned
  if [[ -d "/var/lock" ]]; then
    find /var/lock -maxdepth 1 -name 'sbx-port-*.lock' -type f -mmin +"${CLEANUP_OLD_FILES_MIN:-60}" -delete 2>/dev/null || true
  fi

  # If we're in the middle of an upgrade/install and something fails,
  # try to restore service if it was previously running
  if [[ $exit_code -ne 0 && -f "$SB_SVC" ]]; then
    if systemctl is-enabled sing-box >/dev/null 2>&1; then
      systemctl start sing-box 2>/dev/null || true
    fi
  fi

  exit $exit_code
}

#==============================================================================
# Temporary File Management
#==============================================================================

# Create temporary directory with consistent error handling
#
# Usage: temp_dir=$(create_temp_dir) || return 1
# Args:
#   $1: Optional prefix for temp directory name
# Returns:
#   Path to created temporary directory
# Example:
#   temp_dir=$(create_temp_dir "backup") || return 1
create_temp_dir() {
  local prefix="${1:-sbx}"
  local temp_dir

  if ! temp_dir=$(mktemp -d -t "${prefix}.XXXXXX" 2>&1); then
    err "Failed to create temporary directory"
    err "Possible causes:"
    err "  - Disk full (check: df -h /tmp)"
    err "  - No write permission to /tmp"
    err "  - SELinux/AppArmor restrictions"
    err "Details: $temp_dir"
    return 1
  fi

  # Set secure permissions
  chmod 700 "$temp_dir" || {
    err "Failed to set permissions on temp directory: $temp_dir"
    rm -rf "$temp_dir" 2>/dev/null
    return 1
  }

  echo "$temp_dir"
  return 0
}

# Create temporary file with consistent error handling
#
# Usage: tmpfile=$(create_temp_file) || return 1
# Args:
#   $1: Optional prefix for temp file name
# Returns:
#   Path to created temporary file
# Example:
#   tmpfile=$(create_temp_file "config") || return 1
create_temp_file() {
  local prefix="${1:-sbx}"
  local tmpfile

  if ! tmpfile=$(mktemp -t "${prefix}.XXXXXX" 2>&1); then
    err "Failed to create temporary file"
    err "Possible causes:"
    err "  - Disk full (check: df -h /tmp)"
    err "  - No write permission to /tmp"
    err "  - SELinux/AppArmor restrictions"
    err "Details: $tmpfile"
    return 1
  fi

  # Set secure permissions
  chmod 600 "$tmpfile" || {
    err "Failed to set permissions on temp file: $tmpfile"
    rm -f "$tmpfile" 2>/dev/null
    return 1
  }

  echo "$tmpfile"
  return 0
}

#==============================================================================
# Module Initialization
#==============================================================================

# Source logging module (provides msg, warn, err, info, success, debug, die)
# Colors are already loaded from colors.sh at the top of this file
# shellcheck source=/dev/null
source "${_LIB_DIR}/logging.sh"

# Source generators module (provides generate_uuid, generate_reality_keypair, etc.)
# shellcheck source=/dev/null
source "${_LIB_DIR}/generators.sh"

# Setup cleanup trap (can be overridden by main script)
trap cleanup EXIT INT TERM

# Export core utility functions
export -f need_root have safe_rm_temp get_file_size cleanup create_temp_dir create_temp_file

# Note: Logging and generator functions are exported by their respective modules
