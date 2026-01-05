#!/usr/bin/env bash
# lib/version.sh - Version alias resolution for sing-box
#
# This module provides version resolution functionality for sing-box installations.
# Supports version aliases (stable/latest) and specific version strings.
#
# Functions:
#   - resolve_singbox_version: Resolve version alias to actual version tag

# Strict mode for error handling and safety
set -euo pipefail

[[ -n "${_SBX_VERSION_LOADED:-}" ]] && return 0
readonly _SBX_VERSION_LOADED=1

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load dependencies
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

# Fetch GitHub API response, using auth when possible.
_github_api_fetch_json() {
  local api_url="$1"
  local token="${GITHUB_TOKEN:-}"
  local tmpfile="" api_response="" err_output=""

  if [[ -z "${token}" ]]; then
    safe_http_get "${api_url}"
    return $?
  fi

  tmpfile=$(create_temp_file "sbx-gh-api") || return 1

  if have curl; then
    if ! err_output=$(curl -fsSL --max-time 30 \
      -H "Authorization: token ${token}" \
      -o "${tmpfile}" \
      "${api_url}" 2>&1); then
      err "Failed to fetch release information from GitHub API"
      err "Details: ${err_output}"
      rm -f "${tmpfile}" 2> /dev/null || true
      return 1
    fi
  elif have wget; then
    if ! err_output=$(wget -q --timeout=30 \
      --header="Authorization: token ${token}" \
      -O "${tmpfile}" \
      "${api_url}" 2>&1); then
      err "Failed to fetch release information from GitHub API"
      err "Details: ${err_output}"
      rm -f "${tmpfile}" 2> /dev/null || true
      return 1
    fi
  else
    debug "GITHUB_TOKEN set but neither curl nor wget available for authenticated GitHub API request; falling back to unauthenticated request"
    rm -f "${tmpfile}" 2> /dev/null || true
    safe_http_get "${api_url}"
    return $?
  fi

  api_response=$(cat "${tmpfile}") || {
    err "Failed to read GitHub API response from temp file: ${tmpfile}"
    rm -f "${tmpfile}" 2> /dev/null || true
    return 1
  }
  rm -f "${tmpfile}" 2> /dev/null || true

  if [[ -z "${api_response}" ]]; then
    err "GitHub API response was empty: ${api_url}"
    return 1
  fi

  printf '%s' "${api_response}"
  return 0
}

#==============================================================================
# Version Resolution Functions
#==============================================================================

# Resolve version alias to actual version tag
#
# Uses SINGBOX_VERSION environment variable to determine which version to use.
# Supports: stable, latest, vX.Y.Z, X.Y.Z, vX.Y.Z-beta.N
#
# Args:
#   None (uses environment variable SINGBOX_VERSION)
#
# Returns:
#   Outputs resolved version tag to stdout (e.g., "v1.10.7")
#   Exit code 0 on success, 1 on failure
#
# Environment:
#   SINGBOX_VERSION: Version specifier (default: "stable")
#     - "stable" or "" : Latest stable release (no pre-releases)
#     - "latest"       : Absolute latest release (including pre-releases)
#     - "vX.Y.Z"       : Specific version tag (preserved as-is)
#     - "X.Y.Z"        : Specific version (auto-prefixed with 'v')
#     - "vX.Y.Z-beta.N": Pre-release version (preserved as-is)
#
#   GITHUB_TOKEN (optional): GitHub API token for higher rate limits
#   CUSTOM_GITHUB_API (optional): Custom GitHub API endpoint (default: https://api.github.com)
#                                  Example: https://github.enterprise.local/api/v3
#
# Example:
#   SINGBOX_VERSION=stable resolve_singbox_version
#   # Output: v1.10.7
#
#   SINGBOX_VERSION=latest resolve_singbox_version
#   # Output: v1.11.0-beta.1
#
#   SINGBOX_VERSION=1.10.7 resolve_singbox_version
#   # Output: v1.10.7
#
resolve_singbox_version() {
  local version_input="${SINGBOX_VERSION:-stable}"
  local resolved_version=""

  # Normalize to lowercase for comparison
  local version_lower="${version_input,,}"

  msg "Resolving version: ${version_input}"

  case "${version_lower}" in
    stable | "")
      # Fetch latest stable release (non-prerelease)
      msg "  Fetching latest stable release from GitHub..."

      local github_api_base="${CUSTOM_GITHUB_API:-https://api.github.com}"
      local api_url="${github_api_base}/repos/SagerNet/sing-box/releases/latest"
      local api_response=""

      debug "Using GitHub API: ${github_api_base}"

      api_response=$(_github_api_fetch_json "${api_url}") || return 1

      # Extract tag_name from JSON response
      if have jq; then
        resolved_version=$(echo "${api_response}" | jq -r '.tag_name // empty' 2> /dev/null)
      else
        resolved_version=$(echo "${api_response}" \
          | grep '"tag_name":' \
          | head -1 \
          | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
      fi

      if [[ -z "${resolved_version}" ]]; then
        err "Failed to parse version from API response"
        return 1
      fi
      ;;

    latest)
      # Fetch absolute latest release (including pre-releases)
      msg "  Fetching latest release (including pre-releases) from GitHub..."

      local github_api_base="${CUSTOM_GITHUB_API:-https://api.github.com}"
      local api_url="${github_api_base}/repos/SagerNet/sing-box/releases"
      local api_response=""

      debug "Using GitHub API: ${github_api_base}"

      api_response=$(_github_api_fetch_json "${api_url}") || return 1

      # Extract first tag_name from releases array
      if have jq; then
        resolved_version=$(echo "${api_response}" | jq -r '.[0].tag_name // empty' 2> /dev/null)
      else
        resolved_version=$(echo "${api_response}" \
          | grep '"tag_name":' \
          | head -1 \
          | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?')
      fi

      if [[ -z "${resolved_version}" ]]; then
        err "Failed to parse version from API response"
        return 1
      fi
      ;;

    v[0-9]*)
      # Already a version tag with 'v' prefix
      # Validate format: vX.Y.Z or vX.Y.Z-pre-release
      if [[ "${version_input}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        resolved_version="${version_input}"
        msg "  Using specified version: ${resolved_version}"
      else
        err "Invalid version format: ${version_input}"
        err "Expected: vX.Y.Z or vX.Y.Z-pre-release"
        return 1
      fi
      ;;

    [0-9]*)
      # Version without 'v' prefix - add it
      # Validate format: X.Y.Z or X.Y.Z-pre-release
      if [[ "${version_input}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        resolved_version="v${version_input}"
        msg "  Auto-prefixed version: ${resolved_version}"
      else
        err "Invalid version format: ${version_input}"
        err "Expected: X.Y.Z or X.Y.Z-pre-release"
        return 1
      fi
      ;;

    *)
      # Invalid format
      err "Invalid version specifier: ${version_input}"
      err "Supported formats:"
      err "  - stable           : Latest stable release"
      err "  - latest           : Latest release (including pre-releases)"
      err "  - vX.Y.Z           : Specific version with 'v' prefix"
      err "  - X.Y.Z            : Specific version without 'v' prefix"
      err "  - vX.Y.Z-beta.N    : Pre-release version"
      return 1
      ;;
  esac

  # Final validation
  if [[ -z "${resolved_version}" ]]; then
    err "Failed to resolve version: ${version_input}"
    return 1
  fi

  # Validate resolved version format
  if [[ ! "${resolved_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    err "Resolved version has invalid format: ${resolved_version}"
    return 1
  fi

  # Determine version type for logging
  local version_type
  case "${version_lower}" in
    stable | "") version_type="stable" ;;
    latest) version_type="latest" ;;
    v* | [0-9]*) version_type="specific" ;;
    *) version_type="unknown" ;;
  esac

  success "Resolved sing-box version: ${resolved_version} (type: ${version_type})"
  echo "${resolved_version}"
  return 0
}

#==============================================================================
# Version Compatibility Functions
#==============================================================================

# Get current installed sing-box version
#
# Returns:
#   Outputs version string (e.g., "1.12.0") to stdout
#   Exit code 0 on success, 1 on failure
#
# Example:
#   version=$(get_singbox_version)
#
get_singbox_version() {
  local sb_bin="${SB_BIN:-/usr/local/bin/sing-box}"

  if [[ ! -f "${sb_bin}" ]]; then
    debug "sing-box binary not found: ${sb_bin}"
    return 1
  fi

  if [[ ! -x "${sb_bin}" ]]; then
    debug "sing-box binary not executable: ${sb_bin}"
    return 1
  fi

  local version_output
  version_output=$("${sb_bin}" version 2>&1) || {
    debug "Failed to get sing-box version"
    return 1
  }

  # Extract version number (e.g., "1.12.0" or "1.11.0-beta.1")
  local version
  version=$(echo "${version_output}" | grep -oP 'sing-box version \K[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?') || {
    debug "Failed to parse version from: ${version_output}"
    return 1
  }

  echo "${version}"
  return 0
}

# Compare two semantic version strings
#
# Args:
#   $1 - First version (e.g., "1.10.0")
#   $2 - Second version (e.g., "1.12.0")
#
# Returns:
#   Outputs the lower version to stdout
#   Exit code 0 on success
#
# Example:
#   lowest=$(compare_versions "1.10.0" "1.12.0")
#   # lowest="1.10.0"
#
compare_versions() {
  local version1="${1:-}"
  local version2="${2:-}"

  if [[ -z "${version1}" || -z "${version2}" ]]; then
    err "compare_versions: both version parameters required"
    return 1
  fi

  # Use sort -V for version comparison
  printf '%s\n%s\n' "${version1}" "${version2}" | sort -V | head -n1
}

# Check if current version meets minimum requirement
#
# Args:
#   $1 - Current version (e.g., "1.12.0")
#   $2 - Minimum required version (e.g., "1.8.0")
#
# Returns:
#   0 if current >= minimum
#   1 if current < minimum
#
# Example:
#   if version_meets_minimum "$current" "1.8.0"; then
#     echo "Version OK"
#   fi
#
version_meets_minimum() {
  local current="${1:-}"
  local minimum="${2:-}"

  if [[ -z "${current}" || -z "${minimum}" ]]; then
    err "version_meets_minimum: both version parameters required"
    return 1
  fi

  # Strip 'v' prefix if present
  current="${current#v}"
  minimum="${minimum#v}"

  # Get lowest version
  local lowest
  lowest=$(compare_versions "${current}" "${minimum}")

  # If lowest is minimum, current >= minimum
  if [[ "${lowest}" == "${minimum}" ]]; then
    return 0
  else
    return 1
  fi
}

# Validate sing-box version for Reality protocol compatibility
#
# Checks:
#   - Minimum version 1.8.0 (Reality support)
#   - Recommended version 1.12.0 (modern config format)
#
# Returns:
#   0 if validation passes (meets minimum)
#   1 if version too old or detection failed
#
# Environment:
#   SB_BIN: Path to sing-box binary (default: /usr/local/bin/sing-box)
#
# Example:
#   validate_singbox_version || die "sing-box version too old"
#
validate_singbox_version() {
  local min_version="1.8.0"          # Reality requires 1.8.0+
  local recommended_version="1.12.0" # Modern config format

  msg "Checking sing-box version compatibility..."

  local current_version
  current_version=$(get_singbox_version) || {
    warn "Could not detect sing-box version"
    warn "Reality protocol requires sing-box ${min_version} or later"
    return 0 # Don't fail on detection failure
  }

  debug "Detected sing-box version: ${current_version}"

  # Check minimum version
  if ! version_meets_minimum "${current_version}" "${min_version}"; then
    err ""
    err "sing-box version ${current_version} is too old for Reality protocol"
    err ""
    err "Minimum required: ${min_version}"
    err "Current version:   ${current_version}"
    err ""
    err "Please upgrade sing-box:"
    err "  https://github.com/SagerNet/sing-box/releases"
    err ""
    return 1
  fi

  # Check recommended version
  if ! version_meets_minimum "${current_version}" "${recommended_version}"; then
    warn ""
    warn "sing-box version ${current_version} detected"
    warn "Recommended: ${recommended_version} or later for modern config format"
    warn ""
    warn "Current version: ${current_version}"
    warn "Your version will work, but newer versions have improved features"
    warn ""
  else
    success "sing-box version ${current_version} (meets all requirements)"
  fi

  return 0
}

# Display version compatibility information
#
# Shows current version, requirements, and recommendations
#
# Returns:
#   0 always (informational only)
#
# Example:
#   show_version_info
#
show_version_info() {
  local current_version
  current_version=$(get_singbox_version 2> /dev/null) || current_version="unknown"

  echo ""
  echo "sing-box Version Information"
  echo "============================"
  echo ""
  echo "Current version:     ${current_version}"
  echo "Minimum required:    1.8.0  (Reality protocol support)"
  echo "Recommended:         1.12.0 (Modern configuration format)"
  echo "Latest info:         https://github.com/SagerNet/sing-box/releases"
  echo ""

  if [[ "${current_version}" != "unknown" ]]; then
    if version_meets_minimum "${current_version}" "1.12.0"; then
      echo "Status: ✓ Fully compatible"
    elif version_meets_minimum "${current_version}" "1.8.0"; then
      echo "Status: ⚠ Compatible (upgrade recommended)"
    else
      echo "Status: ✗ Upgrade required"
    fi
  fi

  echo ""
}

# Export functions for use in other modules
export -f resolve_singbox_version
export -f get_singbox_version
export -f compare_versions
export -f version_meets_minimum
export -f validate_singbox_version
export -f show_version_info
