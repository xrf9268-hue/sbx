#!/usr/bin/env bash
# install.sh v2.0 - Modular sing-box installer
# One-click official sing-box with VLESS-REALITY, VLESS-WS-TLS, and Hysteria2
#
# Usage (install):
#   bash install.sh                                    # Interactive mode
#   AUTO_INSTALL=1 bash install.sh                     # Non-interactive (auto-detect IP)
#   DOMAIN=example.com bash install.sh                 # Full setup with domain
#   DOMAIN=example.com CERT_MODE=cf_dns CF_Token='xxx' ...  # With certificates
#
# Usage (uninstall):
#   FORCE=1 bash install.sh uninstall

set -euo pipefail

# Error context handler for unexpected exits under strict mode.
# Provides actionable line/function/command information for issue reports.
_error_handler() {
  local exit_code=$?

  # Recursion guard: avoid trap loops if handler itself hits an error.
  [[ "${_SBX_IN_ERROR_HANDLER:-0}" == "1" ]] && return "${exit_code}"
  _SBX_IN_ERROR_HANDLER=1
  export _SBX_ERROR_CONTEXT_EMITTED=1

  local line_no="${BASH_LINENO[0]:-unknown}"
  local cmd="${BASH_COMMAND:-unknown}"
  local func="${FUNCNAME[1]:-main}"
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-install.sh}}"

  echo "" >&2
  echo "[ERROR] Command failed (exit ${exit_code})" >&2
  echo "  Location: ${src}:${line_no} in ${func}()" >&2
  echo "  Command:  ${cmd}" >&2
  echo "  Report:   https://github.com/xrf9268-hue/sbx/issues" >&2

  _SBX_IN_ERROR_HANDLER=0
  return "${exit_code}"
}

# Enable ERR trap only when running as a script (not when sourced by tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -o errtrace
  trap '_error_handler' ERR
fi

# Track whether the user explicitly set WS_PORT (before lib/common.sh applies defaults).
# This lets CF_MODE reliably switch the default WS port to 443 while still respecting overrides.
WS_PORT_USER_SPECIFIED=0
if [[ -n "${WS_PORT+x}" ]]; then
  WS_PORT_USER_SPECIFIED=1
fi
readonly WS_PORT_USER_SPECIFIED

#==============================================================================
# Early Constants (used before module loading)
#==============================================================================

# Download configuration
readonly DOWNLOAD_CONNECT_TIMEOUT_SEC=10
readonly DOWNLOAD_MAX_TIMEOUT_SEC=30
readonly HTTP_DOWNLOAD_TIMEOUT_SEC=30 # For safe_http_get() during bootstrap
readonly MIN_MODULE_FILE_SIZE_BYTES=100
readonly MIN_MANAGER_FILE_SIZE_BYTES=5000 # Manager script validation (~15KB expected)

# Network configuration
readonly NETWORK_TIMEOUT_SEC=5   # Used by get_public_ip() during bootstrap
readonly IPV6_TEST_TIMEOUT_SEC=3 # Used by detect_ipv6_support() during bootstrap
readonly IPV6_PING_WAIT_SEC=2    # Used by detect_ipv6_support() during bootstrap

# Reality validation constraints (used by lib/validation.sh during bootstrap)
readonly REALITY_SHORT_ID_MIN_LENGTH=1
readonly REALITY_SHORT_ID_MAX_LENGTH=8

# Port defaults (used by lib/validation.sh during bootstrap)
readonly REALITY_PORT_DEFAULT=443
readonly WS_PORT_DEFAULT=8444
readonly HY2_PORT_DEFAULT=8443
readonly TUIC_PORT_DEFAULT=8445
readonly TROJAN_PORT_DEFAULT=8446

# ACME data directory (used by lib/config.sh for native ACME)
readonly ACME_DATA_DIRECTORY="/var/lib/sing-box/acme"

# Reality configuration defaults (used by lib/config.sh during bootstrap)
readonly REALITY_FLOW_VISION="xtls-rprx-vision"
readonly REALITY_DEFAULT_HANDSHAKE_PORT=443
readonly REALITY_MAX_TIME_DIFF="1m"
readonly REALITY_ALPN_H2="h2"
readonly REALITY_ALPN_HTTP11="http/1.1"

# Cloudflare API Token validation (used by lib/validation.sh during bootstrap)
readonly CF_API_TOKEN_MIN_LENGTH=40
readonly CF_API_TOKEN_MAX_LENGTH=60

# File permissions (octal)
readonly SECURE_DIR_PERMISSIONS=700
readonly SECURE_FILE_PERMISSIONS=600

#==============================================================================
# Early Helper Functions (needed before module loading)
#==============================================================================

# Temporary get_file_size implementation for bootstrapping
# This will be overridden by lib/common.sh after module loading
get_file_size() {
  local file="$1"

  # Validate file exists
  [[ -f "${file}" ]] || {
    echo "0"
    return 1
  }

  # Cross-platform file size retrieval
  # Linux: stat -c%s
  # BSD/macOS: stat -f%z
  stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0"
}

# Temporary create_temp_dir implementation for bootstrapping
# This will be overridden by lib/common.sh after module loading
create_temp_dir() {
  local prefix="${1:-sbx}"
  local temp_dir=''

  if ! temp_dir=$(mktemp -d -t "${prefix}.XXXXXX" 2>/dev/null); then
    echo "ERROR: Failed to create temporary directory" >&2
    return 1
  fi

  chmod "${SECURE_DIR_PERMISSIONS}" "${temp_dir}" 2>/dev/null || {
    echo "ERROR: Failed to set permissions on temporary directory: ${temp_dir}" >&2
    rm -rf "${temp_dir}" 2>/dev/null || true
    return 1
  }

  echo "${temp_dir}"
  return 0
}

# Print usage help (must work before module loading)
_print_help() {
  cat <<'EOF'
sbx-lite sing-box installer

Usage:
  bash install.sh                  Interactive install
  AUTO_INSTALL=1 bash install.sh   Non-interactive install
  bash install.sh --dry-run        Preview actions without making changes
  bash install.sh uninstall        Uninstall
  bash install.sh --help           Show this help

Environment (common):
  DOMAIN=example.com               Configure domain/certs if supported
  SNI_DOMAIN=www.microsoft.com     Override Reality handshake SNI domain
  DEBUG=1                          Enable debug output
EOF
}

# Handle --help/-h early (no root required)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    -h | --help)
      _print_help
      exit 0
      ;;
    *) ;;
  esac
fi

#==============================================================================
# Module Loading with Smart Download
#==============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#==============================================================================
# Module Download Helper Functions
#==============================================================================

# Download and verify a single module (for parallel execution)
# This function is designed to be called by xargs in parallel
_download_single_module() {
  local temp_lib_dir="$1"
  local github_repo="$2"
  local module="$3"

  local module_file="${temp_lib_dir}/${module}.sh"
  local module_url="${github_repo}/lib/${module}.sh"

  # Debug logging (if enabled)
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Downloading ${module} from ${module_url}" >&2

  # Download module
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -o "${module_file}" 2>&1; then
      echo "DOWNLOAD_FAILED:${module}" >&2
      [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: curl failed for ${module}" >&2
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q --timeout="${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -O "${module_file}" 2>&1; then
      echo "DOWNLOAD_FAILED:${module}" >&2
      [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: wget failed for ${module}" >&2
      return 1
    fi
  else
    echo "NO_DOWNLOADER:${module}" >&2
    return 1
  fi

  # Verify downloaded file
  if [[ ! -f "${module_file}" ]]; then
    echo "FILE_NOT_FOUND:${module}" >&2
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: File not found: ${module_file}" >&2
    return 1
  fi

  # Check file size
  local file_size=0
  file_size=$(get_file_size "${module_file}")
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: ${module} file size: ${file_size} bytes" >&2

  if [[ "${file_size}" -lt "${MIN_MODULE_FILE_SIZE_BYTES}" ]]; then
    echo "FILE_TOO_SMALL:${module}:${file_size}" >&2
    return 1
  fi

  # Validate bash syntax
  if ! bash -n "${module_file}" 2>/dev/null; then
    echo "SYNTAX_ERROR:${module}" >&2
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Syntax check failed for ${module}" >&2
    return 1
  fi

  # Success - output for progress tracking
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: ${module} downloaded and verified successfully" >&2
  echo "SUCCESS:${module}:${file_size}"
  return 0
}

# Download modules in parallel using xargs
_download_modules_parallel() {
  local temp_lib_dir="$1"
  local github_repo="$2"
  shift 2
  local modules=("$@")

  local parallel_jobs="${PARALLEL_JOBS:-5}"
  local total="${#modules[@]}"

  echo "  Downloading ${total} modules in parallel (${parallel_jobs} jobs)..."

  # Export function and variables for subshells
  export -f _download_single_module
  export -f get_file_size
  export temp_lib_dir github_repo
  export DOWNLOAD_CONNECT_TIMEOUT_SEC DOWNLOAD_MAX_TIMEOUT_SEC MIN_MODULE_FILE_SIZE_BYTES

  # Track results
  local failed_modules=()
  local success_count=0
  local current=0
  local mod_name='' mod_size='' error_type='' percent=0

  # Use xargs for parallel execution
  while IFS= read -r result; do
    current=$((current + 1))

    # Parse result
    if [[ "${result}" =~ ^SUCCESS:(.+):([0-9]+)$ ]]; then
      mod_name="${BASH_REMATCH[1]}"
      mod_size="${BASH_REMATCH[2]}"
      success_count=$((success_count + 1))

      # Progress indicator
      percent=$((current * 100 / total))
      printf "\r  [%3d%%] %d/%d modules downloaded" "${percent}" "${current}" "${total}"

    elif [[ "${result}" =~ ^(DOWNLOAD_FAILED|FILE_NOT_FOUND|FILE_TOO_SMALL|SYNTAX_ERROR|NO_DOWNLOADER):(.+) ]]; then
      error_type="${BASH_REMATCH[1]}"
      mod_name="${BASH_REMATCH[2]}"
      failed_modules+=("${mod_name}:${error_type}")
    fi
  done < <(printf '%s\n' "${modules[@]}" | xargs -P "${parallel_jobs}" -I {} bash -c '_download_single_module "$temp_lib_dir" "$github_repo" "$@"' _ {})

  echo "" # New line after progress

  # Check results
  if [[ ${#failed_modules[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: Failed to download ${#failed_modules[@]} module(s):"
    for failure in "${failed_modules[@]}"; do
      echo "  • ${failure}"
    done
    echo ""
    echo "Falling back to sequential download..."
    return 1
  fi

  echo "  ✓ All ${success_count} modules downloaded and verified"
  return 0
}

# Download modules sequentially (fallback method)
_download_modules_sequential() {
  local temp_lib_dir="$1"
  local github_repo="$2"
  shift 2
  local modules=("$@")

  local total="${#modules[@]}"
  local current=0

  echo "  Downloading ${total} modules sequentially..."

  for module in "${modules[@]}"; do
    current=$((current + 1))
    local module_file="${temp_lib_dir}/${module}.sh"
    local module_url="${github_repo}/lib/${module}.sh"

    printf "  [%d/%d] Downloading %s..." "${current}" "${total}" "${module}.sh"

    # Download
    if command -v curl >/dev/null 2>&1; then
      if ! curl -fsSL --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -o "${module_file}" 2>/dev/null; then
        echo " ✗ FAILED"
        rm -rf "${temp_lib_dir}"
        _show_download_error_help "${module}" "${module_url}"
        return 1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if ! wget -q --timeout="${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -O "${module_file}" 2>/dev/null; then
        echo " ✗ FAILED"
        rm -rf "${temp_lib_dir}"
        _show_download_error_help "${module}" "${module_url}"
        return 1
      fi
    else
      echo " ✗ NO DOWNLOADER"
      rm -rf "${temp_lib_dir}"
      _show_no_downloader_error
      return 1
    fi

    # Verify
    local file_size=0
    file_size=$(get_file_size "${module_file}")

    if [[ ! -f "${module_file}" ]] || [[ "${file_size}" -lt "${MIN_MODULE_FILE_SIZE_BYTES}" ]]; then
      echo " ✗ VERIFY FAILED"
      rm -rf "${temp_lib_dir}"
      _show_verification_error "${module}" "${file_size}"
      return 1
    fi

    if ! bash -n "${module_file}" 2>/dev/null; then
      echo " ✗ SYNTAX ERROR"
      rm -rf "${temp_lib_dir}"
      _show_syntax_error "${module}"
      return 1
    fi

    echo " ✓ (${file_size} bytes)"
  done

  echo "  ✓ All ${total} modules downloaded and verified"
  return 0
}

# Show download error help
_show_download_error_help() {
  local module="$1"
  local url="$2"
  echo ""
  echo "ERROR: Failed to download module: ${module}.sh"
  echo "URL: ${url}"
  echo ""
  echo "Possible causes:"
  echo "  1. Network connectivity issues"
  echo "  2. GitHub rate limiting (try again in a few minutes)"
  echo "  3. Repository branch/tag does not exist"
  echo "  4. Firewall blocking GitHub access"
  echo ""
  echo "Troubleshooting:"
  echo "  • Test connectivity: curl -I https://github.com"
  echo "  • Use git clone instead:"
  echo "    git clone https://github.com/xrf9268-hue/sbx.git"
  echo "    cd sbx-lite && bash install.sh"
  echo ""
}

# Show no downloader error
_show_no_downloader_error() {
  echo ""
  echo "ERROR: Neither curl nor wget is available"
  echo "Please install one of the following:"
  echo "  • curl: apt-get install curl  (Debian/Ubuntu)"
  echo "  • wget: apt-get install wget  (Debian/Ubuntu)"
  echo "  • curl: yum install curl      (CentOS/RHEL)"
  echo "  • wget: yum install wget      (CentOS/RHEL)"
  echo ""
}

# Show verification error
_show_verification_error() {
  local module="$1"
  local file_size="$2"
  echo ""
  echo "ERROR: Downloaded file verification failed: ${module}.sh"
  echo "File size: ${file_size} bytes (minimum: ${MIN_MODULE_FILE_SIZE_BYTES} bytes)"
  echo ""
  echo "This usually indicates:"
  echo "  1. Network error during download (partial file)"
  echo "  2. GitHub returned an error page instead of the file"
  echo "  3. Rate limiting or authentication issues"
  echo ""
  echo "Please try again in a few minutes or use git clone method."
  echo ""
}

# Show syntax error
_show_syntax_error() {
  local module="$1"
  echo ""
  echo "ERROR: Invalid bash syntax in downloaded file: ${module}.sh"
  echo ""
  echo "This may indicate:"
  echo "  1. Corrupted download (network issue)"
  echo "  2. Partial/incomplete download"
  echo "  3. Potential security issue (MITM attack)"
  echo ""
  echo "For security, the installation has been aborted."
  echo "Please try again or use the git clone method."
  echo ""
}

_download_and_validate_manager_script() {
  local github_repo="$1"
  local installer_dir="$2"

  local manager_url="${github_repo}/bin/sbx-manager.sh"
  local manager_file="${installer_dir}/bin/sbx-manager.sh"
  local download_success=0

  echo "  Downloading sbx-manager script..."
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Creating ${installer_dir}/bin directory" >&2
  mkdir -p "${installer_dir}/bin"

  if command -v curl >/dev/null 2>&1; then
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Downloading sbx-manager.sh via curl from ${manager_url}" >&2
    if curl -fsSL --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" \
      --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" "${manager_url}" -o "${manager_file}" 2>/dev/null; then
      download_success=1
    fi
  elif command -v wget >/dev/null 2>&1; then
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Downloading sbx-manager.sh via wget from ${manager_url}" >&2
    if wget -q --timeout="${DOWNLOAD_MAX_TIMEOUT_SEC}" "${manager_url}" -O "${manager_file}" 2>/dev/null; then
      download_success=1
    fi
  else
    echo "ERROR: Neither curl nor wget available for downloading sbx-manager.sh"
    return 1
  fi

  if [[ ${download_success} -eq 0 ]]; then
    echo "ERROR: Failed to download sbx-manager.sh from ${manager_url}"
    echo "       Please check network connection and try again."
    return 1
  fi

  if [[ ! -f "${manager_file}" ]]; then
    echo "ERROR: sbx-manager.sh download completed but file not found"
    return 1
  fi

  local mgr_size=0
  mgr_size=$(get_file_size "${manager_file}")
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: sbx-manager.sh file size: ${mgr_size} bytes" >&2

  if [[ "${mgr_size}" -lt "${MIN_MANAGER_FILE_SIZE_BYTES}" ]]; then
    echo "ERROR: Downloaded sbx-manager.sh is too small (${mgr_size} bytes)"
    echo "       Expected: >${MIN_MANAGER_FILE_SIZE_BYTES} bytes (full version is ~15KB)"
    echo "       File may be corrupted or incomplete."
    return 1
  fi

  if ! bash -n "${manager_file}" 2>/dev/null; then
    echo "ERROR: Invalid bash syntax in downloaded sbx-manager.sh"
    echo "       File may be corrupted."
    return 1
  fi

  echo "  ✓ sbx-manager.sh downloaded and validated (${mgr_size} bytes)"
  return 0
}

#==============================================================================
# Smart Module Loader
#==============================================================================

# Smart module loader: downloads modules if not present (for one-liner install)
_load_modules() {
  local github_repo="https://raw.githubusercontent.com/xrf9268-hue/sbx/main"
  # Module loading order: colors first (required by common and logging), then common loads logging and generators, tools after common
  local modules=(colors common logging generators tools retry download network validation checksum version certificate caddy_cleanup config config_validator schema_validator service ui backup export messages)
  local temp_lib_dir=""

  # Check if lib directory exists
  if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    echo "[*] One-liner install detected, downloading required modules..."
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: SCRIPT_DIR=${SCRIPT_DIR}, lib directory not found" >&2

    # Create temporary directory for modules
    temp_lib_dir=$(create_temp_dir "sbx-lib") || {
      echo "ERROR: Failed to create temporary directory"
      exit 1
    }
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Created temp directory: ${temp_lib_dir}" >&2

    # Determine download strategy: parallel or sequential
    local use_parallel=1
    if [[ "${ENABLE_PARALLEL_DOWNLOAD:-1}" == "0" ]]; then
      use_parallel=0
    fi

    # Download modules (parallel with fallback to sequential on failure)
    if [[ ${use_parallel} -eq 1 ]] && command -v xargs >/dev/null 2>&1; then
      # Try parallel download first
      if ! _download_modules_parallel "${temp_lib_dir}" "${github_repo}" "${modules[@]}"; then
        # Parallel failed, fallback to sequential
        echo "  Retrying with sequential download..."
        if ! _download_modules_sequential "${temp_lib_dir}" "${github_repo}" "${modules[@]}"; then
          echo ""
          echo "ERROR: Module download failed (both parallel and sequential methods)"
          exit 1
        fi
      fi
    else
      # Use sequential download directly
      if ! _download_modules_sequential "${temp_lib_dir}" "${github_repo}" "${modules[@]}"; then
        echo ""
        echo "ERROR: Module download failed"
        exit 1
      fi
    fi

    # Create proper directory structure
    local parent_dir=''
    parent_dir="$(dirname "${temp_lib_dir}")"
    SCRIPT_DIR="${parent_dir}/sbx-install-$$"
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Creating permanent directory: ${SCRIPT_DIR}/lib" >&2
    mkdir -p "${SCRIPT_DIR}/lib"
    mv "${temp_lib_dir}"/*.sh "${SCRIPT_DIR}/lib/"
    rmdir "${temp_lib_dir}"

    _download_and_validate_manager_script "${github_repo}" "${SCRIPT_DIR}" || exit 1

    # Remember the generated directory so shared cleanup can purge it later
    INSTALLER_TEMP_DIR="${SCRIPT_DIR}"

    # Register cleanup for temporary files
    trap 'rm -rf "${SCRIPT_DIR}" 2>/dev/null || true' EXIT INT TERM
  fi

  # Load all library modules
  # Save SCRIPT_DIR to prevent pollution from sourced modules
  local INSTALLER_SCRIPT_DIR="${SCRIPT_DIR}"
  [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Loading modules from: ${INSTALLER_SCRIPT_DIR}/lib" >&2

  # Defensive validation: ensure module names match expected pattern
  # Prevents potential path traversal or injection if modules array is ever modified
  _validate_module_name() {
    local module="$1"
    # Whitelist: only lowercase letters and underscores allowed
    if [[ ! "${module}" =~ ^[a-z_]+$ ]]; then
      echo "ERROR: Invalid module name: ${module}"
      echo "Module names must contain only lowercase letters and underscores."
      exit 1
    fi
  }

  for module in "${modules[@]}"; do
    # Validate module name before constructing path (defense in depth)
    _validate_module_name "${module}"

    local module_path="${INSTALLER_SCRIPT_DIR}/lib/${module}.sh"

    if [[ -f "${module_path}" ]]; then
      # Use debug() after common.sh is loaded, echo before
      if [[ "${module}" == "common" ]]; then
        [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Loading module: ${module}.sh" >&2
      else
        [[ "${DEBUG:-0}" == "1" ]] && debug "Loading module: ${module}.sh"
      fi

      # shellcheck source=/dev/null
      source "${module_path}"

      # Restore SCRIPT_DIR after sourcing (modules may redefine it)
      SCRIPT_DIR="${INSTALLER_SCRIPT_DIR}"

      # Use debug() after common.sh is loaded
      if [[ "${module}" == "common" ]]; then
        [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Module ${module}.sh loaded, SCRIPT_DIR restored" >&2
      else
        [[ "${DEBUG:-0}" == "1" ]] && debug "Module ${module}.sh loaded, SCRIPT_DIR restored"
      fi
    else
      echo "ERROR: Required module not found: ${module_path}"
      echo "Please ensure all lib/*.sh files are present."
      exit 1
    fi
  done

  # Verify API contracts after loading all modules
  _verify_module_apis
}

# Verify that all required functions exist (API contract validation)
# Implements Design by Contract (DbC) principles for module compatibility
_verify_module_apis() {
  local all_ok=true

  # Define required functions per module (API contract)
  local -A module_contracts=(
    ["common"]="msg warn err success die generate_uuid have need_root"
    ["retry"]="retry_with_backoff calculate_backoff is_retriable_error"
    ["download"]="download_file download_file_with_retry verify_downloaded_file"
    ["network"]="get_public_ip allocate_port detect_ipv6_support"
    ["validation"]="validate_domain validate_ip_address sanitize_input"
    ["checksum"]="verify_file_checksum verify_singbox_binary"
    ["version"]="resolve_singbox_version"
    ["config"]="write_config create_reality_inbound add_route_config"
    ["service"]="setup_service validate_port_listening restart_service"
  )

  # Verify each module's API contract
  for module in "${!module_contracts[@]}"; do
    local required_functions="${module_contracts[${module}]}"
    local missing_functions=()

    for func in ${required_functions}; do
      if ! declare -F "${func}" >/dev/null 2>&1; then
        missing_functions+=("${func}")
        all_ok=false
      fi
    done

    if [[ ${#missing_functions[@]} -gt 0 ]]; then
      echo "ERROR: Module API contract violation: ${module}"
      echo "Missing functions: ${missing_functions[*]}"
    fi
  done

  if [[ "${all_ok}" != true ]]; then
    echo ""
    echo "This may indicate:"
    echo "  1. Module version mismatch between install.sh and lib/*.sh"
    echo "  2. Incomplete module download"
    echo "  3. Corrupted module files"
    echo ""
    echo "Please try:"
    echo "  git clone https://github.com/xrf9268-hue/sbx.git"
    echo "  cd sbx-lite && bash install.sh"
    echo ""
    exit 1
  fi
}

# Execute module loading
_load_modules

# Note: The following variables are defined in lib/common.sh and sourced above
# ShellCheck cannot trace them through dynamic sourcing, so we declare them here
# to suppress SC2154 warnings. They are actually defined and exported by the modules.
: "${SB_BIN:=/usr/local/bin/sing-box}"
: "${SB_CONF_DIR:=/etc/sing-box}"
: "${SB_CONF:=${SB_CONF_DIR}/config.json}"
: "${SB_SVC:=/etc/systemd/system/sing-box.service}"
: "${CLIENT_INFO:=${SB_CONF_DIR}/client-info.txt}"
: "${STATE_FILE:=${SB_CONF_DIR}/state.json}"
: "${REALITY_PORT:=443}"
: "${REALITY_PORT_FALLBACK:=24443}"
: "${WS_PORT:=8444}"
: "${WS_PORT_FALLBACK:=24444}"
: "${HY2_PORT:=8443}"
: "${HY2_PORT_FALLBACK:=24445}"
: "${SNI_DEFAULT:=www.microsoft.com}"
: "${CERT_DIR_BASE:=/etc/ssl/sbx}"
: "${CERT_FULLCHAIN:=}"
: "${CERT_KEY:=}"
# Color variables from lib/colors.sh (ShellCheck can't trace dynamic sourcing)
# shellcheck disable=SC2154
: "${B:-}" "${N:-}" "${G:-}" "${Y:-}" "${R:-}" "${CYAN:-}" "${BLUE:-}" "${PURPLE:-}"

#==============================================================================
# Additional Helper Functions
#==============================================================================

# Detect system architecture
detect_arch() {
  local arch='' detected_arch=''
  arch="$(uname -m)"
  case "${arch}" in
    x86_64 | amd64) detected_arch="amd64" ;;
    aarch64 | arm64) detected_arch="arm64" ;;
    armv7l) detected_arch="armv7" ;;
    *) die_with_code "SBX-SYSTEM-010" "Unsupported architecture: ${arch}." \
      "Use a supported architecture: amd64, arm64, or armv7." \
      "uname -m" ;;
  esac

  msg "Detected system architecture: ${detected_arch} (uname: ${arch})"
  echo "${detected_arch}"
}

# Detect libc implementation (glibc vs musl)
# Returns: "-musl" suffix for musl systems, empty string for glibc
detect_libc() {
  # Skip on non-Linux systems
  [[ "$(uname -s)" != "Linux" ]] && {
    echo ""
    return
  }

  # Method 1: Check for musl shared library (most reliable)
  # shellcheck disable=SC2144  # -e with glob is intentional
  if [[ -e /lib/ld-musl-*.so.1 ]]; then
    msg "Detected musl libc (Alpine/embedded Linux)"
    echo "-musl"
    return
  fi

  # Method 2: Parse ldd output
  if command -v ldd >/dev/null 2>&1; then
    if ldd /bin/sh 2>/dev/null | grep -q musl; then
      msg "Detected musl libc via ldd"
      echo "-musl"
      return
    fi
  fi

  # Method 3: Check /etc/os-release for Alpine Linux
  if [[ -f /etc/os-release ]]; then
    if grep -qi "alpine" /etc/os-release; then
      msg "Detected Alpine Linux (musl-based)"
      echo "-musl"
      return
    fi
  fi

  # Default to glibc (empty suffix for backward compatibility)
  [[ "${DEBUG:-0}" == "1" ]] && msg "Detected glibc (standard Linux)"
  echo ""
}

# Get installed sing-box version
get_installed_version() {
  local version=''
  if [[ -x "${SB_BIN}" ]]; then
    # Match version with or without 'v' prefix (e.g., "v1.12.12" or "1.12.12")
    version=$("${SB_BIN}" version 2>/dev/null | head -1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

    # Ensure version has 'v' prefix for consistency with the rest of the codebase
    if [[ "${version}" != "unknown" && "${version}" != v* ]]; then
      version="v${version}"
    fi

    echo "${version}"
  else
    echo "not_installed"
  fi
}

# Get latest version from GitHub
get_latest_version() {
  local api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local response=''
  response=$(safe_http_get "${api}") || {
    warn "Failed to fetch latest version from GitHub"
    echo "unknown"
    return 1
  }

  local version=''
  version=$(echo "${response}" | grep -oE '"tag_name":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
  echo "${version:-unknown}"
}

# Compare versions (semantic versioning)
compare_versions() {
  local current="$1"
  local latest="$2"

  # Remove 'v' prefix
  current="${current#v}"
  latest="${latest#v}"

  # Handle unknown versions
  if [[ "${current}" == "unknown" || "${latest}" == "unknown" ]]; then
    echo "unknown"
    return 0
  fi

  # Exact match
  if [[ "${current}" == "${latest}" ]]; then
    echo "current"
    return 0
  fi

  # Semantic version comparison (major.minor.patch)
  IFS='.' read -r -a current_parts <<<"${current}"
  IFS='.' read -r -a latest_parts <<<"${latest}"

  # Compare each component
  for i in 0 1 2; do
    local curr_part="${current_parts[${i}]:-0}"
    local late_part="${latest_parts[${i}]:-0}"

    # Remove non-numeric suffixes (e.g., "1-beta")
    curr_part="${curr_part%%-*}"
    late_part="${late_part%%-*}"

    if [[ "${curr_part}" -lt "${late_part}" ]]; then
      echo "outdated"
      return 0
    elif [[ "${curr_part}" -gt "${late_part}" ]]; then
      echo "newer"
      return 0
    fi
  done

  # All components equal (shouldn't reach here if equality check worked)
  echo "current"
}

#==============================================================================
# Installation Functions
#==============================================================================

# Check for existing installation
check_existing_installation() {
  local current_version='' service_status='' latest_version='' version_status=''
  local backup_file=''
  current_version="$(get_installed_version)"
  service_status="$(check_service_status && echo "running" || echo "stopped")"

  if [[ "${current_version}" != "not_installed" || -f "${SB_CONF}" || -f "${SB_SVC}" ]]; then
    # Auto-install mode: default to fresh install without prompting
    if [[ "${AUTO_INSTALL:-0}" == "1" ]]; then
      msg "Auto-install mode: performing fresh install..."
      if [[ -f "${SB_CONF}" ]]; then
        backup_file="${SB_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${SB_CONF}" "${backup_file}"
        success "  ✓ Backed up existing config to: ${backup_file}"
      fi
      export SKIP_CONFIG_GEN=0
      export SKIP_BINARY_DOWNLOAD=0
      return 0
    fi

    latest_version="$(get_latest_version)"
    version_status="$(compare_versions "${current_version}" "${latest_version}")"

    # Show existing installation menu
    show_existing_installation_menu "${current_version}" "${service_status}" "${latest_version}" "${version_status}"

    # Get user choice
    local choice=''
    set +e
    choice=$(prompt_menu_choice 1 6)
    local prompt_result=$?
    set -e

    if [[ ${prompt_result} -ne 0 ]]; then
      die_with_code "SBX-UI-010" "Invalid menu choice." \
        "Select a number shown in the menu and retry installation."
    fi

    case "${choice}" in
      1) # Fresh install
        msg "Performing fresh install..."
        if [[ -f "${SB_CONF}" ]]; then
          backup_file="${SB_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
          cp "${SB_CONF}" "${backup_file}"
          success "  ✓ Backed up existing config to: ${backup_file}"
        fi
        export SKIP_CONFIG_GEN=0
        export SKIP_BINARY_DOWNLOAD=0
        ;;
      2) # Upgrade binary only
        msg "Upgrading binary only, preserving configuration..."
        export SKIP_CONFIG_GEN=1
        export SKIP_BINARY_DOWNLOAD=0
        ;;
      3) # Reconfigure
        msg "Reconfiguring (keeping binary)..."
        export SKIP_CONFIG_GEN=0
        export SKIP_BINARY_DOWNLOAD=1
        ;;
      4) # Uninstall
        uninstall_flow
        exit 0
        ;;
      5) # Show current config
        if [[ -f "${SB_CONF}" ]]; then
          echo
          msg "Current configuration:"
          cat "${SB_CONF}"
        else
          warn "No configuration file found"
        fi
        exit 0
        ;;
      6) # Exit
        msg "Exiting..."
        exit 0
        ;;
      *) # Invalid choice (should not happen due to earlier validation)
        die_with_code "SBX-UI-011" "Invalid menu choice." \
          "Select a number shown in the menu and retry installation."
        ;;
    esac
  fi
}

# Ensure required tools are installed
ensure_tools() {
  local required=(curl tar gzip openssl systemctl jq)
  local optional=()
  local missing=()
  local missing_optional=()

  # Check required tools
  for tool in "${required[@]}"; do
    if ! have "${tool}"; then
      missing+=("${tool}")
    fi
  done

  # Check optional tools
  for tool in "${optional[@]}"; do
    if ! have "${tool}"; then
      missing_optional+=("${tool}")
    fi
  done

  # Install required tools if missing
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    msg "Installing missing tools..."

    if have apt-get; then
      apt-get update && apt-get install -y "${missing[@]}"
    elif have dnf; then
      dnf install -y "${missing[@]}"
    elif have yum; then
      yum install -y "${missing[@]}"
    else
      die_with_code "SBX-SYSTEM-011" "Cannot install missing tools automatically: ${missing[*]}." \
        "Install required tools manually, then rerun installer." \
        "apt install -y ${missing[*]}"
    fi
  fi

  # Inform about optional tools
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    info "  ℹ Optional tools not available: ${missing_optional[*]}"
    info "  ℹ Installation will use fallback methods (python3/python)"
    info "  ℹ For best performance, install: ${missing_optional[*]}"
  fi

  success "All required tools are available"
}

# Download sing-box binary
download_singbox() {
  if [[ "${SKIP_BINARY_DOWNLOAD:-0}" = "1" ]]; then
    if [[ -x "${SB_BIN}" ]]; then
      success "Using existing sing-box binary at ${SB_BIN}"
      return 0
    else
      warn "SKIP_BINARY_DOWNLOAD set but no binary found, proceeding with download"
    fi
  fi

  local arch libc_suffix tmp api url="" tag raw
  arch="$(detect_arch)"
  libc_suffix="$(detect_libc)" # "-musl" or ""
  tmp=$(create_temp_dir "download") || die_with_code "SBX-DOWNLOAD-000" \
    "Failed to create temporary directory for download workflow." \
    "Ensure /tmp has free space and is writable." \
    "df -h /tmp && ls -ld /tmp"

  # Resolve version using modular version resolver
  # Supports: stable (default), latest, vX.Y.Z, X.Y.Z
  tag=$(resolve_singbox_version) || {
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-001" "Failed to resolve sing-box version." \
      "Check network connectivity and verify GitHub API access." \
      "curl -I https://api.github.com/repos/SagerNet/sing-box/releases"
  }

  # Get release information for the resolved version
  api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"

  msg "Fetching sing-box ${tag} release info for ${arch}${libc_suffix}..."
  raw=$(safe_http_get "${api}") || {
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-002" "Failed to fetch release information from GitHub." \
      "Check outbound HTTPS access and retry." \
      "curl -I ${api}"
  }

  # Extract download URL (try libc-specific first, then generic)
  # Examples: linux-amd64-musl.tar.gz, linux-amd64.tar.gz
  if [[ -n "${libc_suffix}" ]]; then
    # Try musl-specific binary first
    url=$(echo "${raw}" | grep '"browser_download_url":' | grep -E "linux-${arch}${libc_suffix}\.tar\.gz\"" | head -1 | cut -d'"' -f4)

    if [[ -z "${url}" ]]; then
      warn "musl-specific binary not found for ${tag}, trying generic Linux binary"
      warn "This may work but could cause issues on musl systems"
    fi
  fi

  # Fallback to generic linux binary if musl-specific not found or not needed
  if [[ -z "${url}" ]]; then
    url=$(echo "${raw}" | grep '"browser_download_url":' | grep -E "linux-${arch}\.tar\.gz\"" | head -1 | cut -d'"' -f4)
  fi

  if [[ -z "${url}" ]]; then
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-003" "No compatible release asset found for architecture: ${arch}." \
      "Use a supported architecture or pin a compatible SINGBOX_VERSION." \
      "SINGBOX_VERSION=stable bash install.sh"
  fi

  msg "Downloading sing-box ${tag}..."
  local pkg="${tmp}/sb.tgz"
  safe_http_get "${url}" "${pkg}" || {
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-004" "Failed to download sing-box package." \
      "Check network route, DNS, and TLS interception settings." \
      "curl -I ${url}"
  }

  # ==================== SHA256 Checksum Verification ====================
  # Use modular checksum verification from lib/checksum.sh
  # Skip verification if SKIP_CHECKSUM environment variable is set
  if [[ "${SKIP_CHECKSUM:-0}" != "1" ]]; then
    # Construct platform string with libc suffix (e.g., "linux-amd64-musl" or "linux-amd64")
    local platform="linux-${arch}${libc_suffix}"
    if ! verify_singbox_binary "${pkg}" "${tag}" "${platform}"; then
      rm -rf "${tmp}"
      die_with_code "SBX-DOWNLOAD-005" "Binary checksum verification failed." \
        "Re-download package from official source and do not skip checksum in production." \
        "SKIP_CHECKSUM=0 bash install.sh"
    fi
  else
    warn "⚠ SKIP_CHECKSUM is set, bypassing SHA256 verification"
    warn "⚠ This is NOT recommended for production use"
  fi
  # ==================== Checksum Verification End ====================

  msg "Extracting package..."
  tar -xzf "${pkg}" -C "${tmp}" || {
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-006" "Failed to extract downloaded package." \
      "Verify archive integrity and available disk space." \
      "tar -tzf ${pkg} | head"
  }

  # Find and install binary
  local extracted_bin=''
  extracted_bin=$(find "${tmp}" -name "sing-box" -type f | head -1)

  if [[ -z "${extracted_bin}" ]]; then
    rm -rf "${tmp}"
    die_with_code "SBX-DOWNLOAD-007" "sing-box binary not found in extracted package." \
      "Release asset may be incompatible or corrupted." \
      "find ${tmp} -name sing-box -type f"
  fi

  msg "Installing sing-box binary..."

  # Stop service before replacing binary (prevents "Text file busy" error)
  # The service will be restarted by setup_service or restart_service in main flow
  local service_was_running=0
  if check_service_status 2>/dev/null; then
    msg "Stopping sing-box service for binary replacement..."
    stop_service
    service_was_running=1
  fi

  cp "${extracted_bin}" "${SB_BIN}" || {
    rm -rf "${tmp}"
    # Try to restart service if we stopped it
    [[ "${service_was_running}" -eq 1 ]] && start_service_with_retry 2>/dev/null
    die_with_code "SBX-DOWNLOAD-008" "Failed to install sing-box binary to target path." \
      "Check filesystem permissions and mount flags for /usr/local/bin." \
      "ls -ld /usr/local/bin && id"
  }
  chmod +x "${SB_BIN}"

  rm -rf "${tmp}"
  success "sing-box ${tag} installed successfully"
}

#==============================================================================
# Configuration Material Generation (Refactored for SRP)
#==============================================================================

# Configure server address (domain or IP)
# Sets: DOMAIN, REALITY_ONLY_MODE
_configure_server_address() {
  if [[ -z "${DOMAIN:-}" ]]; then
    if [[ "${AUTO_INSTALL:-0}" == "1" ]]; then
      msg "Auto-install mode: detecting server IP..."
      DOMAIN=$(get_public_ip) || die_with_code "SBX-NETWORK-002" "Failed to detect server IP." \
        "Check outbound connectivity or set DOMAIN manually." \
        "DOMAIN=example.com bash install.sh"
      success "Detected server IP: ${DOMAIN}"
      export REALITY_ONLY_MODE=1
    else
      echo
      echo "========================================"
      echo "Server Address Configuration"
      echo "========================================"
      echo "Options:"
      echo "  1. Press Enter for Reality-only (auto-detect IP)"
      echo "  2. Enter domain name for full setup (Reality + WS-TLS + Hysteria2)"
      echo "  3. Enter IP address manually for Reality-only"
      echo
      echo "Note: Domain must be 'DNS only' (gray cloud) in Cloudflare"
      echo

      local input=''
      read -rp "Domain or IP (press Enter to auto-detect): " input
      input=$(sanitize_input "${input}")

      if [[ -z "${input}" ]]; then
        msg "Auto-detecting server IP..."
        DOMAIN=$(get_public_ip) || die_with_code "SBX-NETWORK-002" "Failed to detect server IP." \
          "Check outbound connectivity or provide DOMAIN/IP manually." \
          "DOMAIN=example.com bash install.sh"
        success "Detected server IP: ${DOMAIN}"
        export REALITY_ONLY_MODE=1
      elif validate_ip_address "${input}"; then
        DOMAIN="${input}"
        success "Using IP address: ${DOMAIN}"
        export REALITY_ONLY_MODE=1
      elif validate_domain "${input}"; then
        DOMAIN="${input}"
        success "Using domain: ${DOMAIN}"
        export REALITY_ONLY_MODE=0
      else
        die_with_code "SBX-CONFIG-001" "Invalid domain or IP address: ${input}" \
          "Provide a valid public domain (example.com) or public IP address." \
          "DOMAIN=example.com bash install.sh"
      fi
    fi
  else
    if validate_ip_address "${DOMAIN}"; then
      export REALITY_ONLY_MODE=1
    else
      export REALITY_ONLY_MODE=0
    fi
  fi
}

# Configure Cloudflare proxy mode
# Sets: CF_MODE, ENABLE_REALITY, ENABLE_WS, ENABLE_HY2, WS_PORT
_configure_cloudflare_mode() {
  export CF_MODE="${CF_MODE:-0}"

  if [[ "${CF_MODE}" == "1" ]]; then
    if [[ "${REALITY_ONLY_MODE}" == "1" ]]; then
      die_with_code "SBX-CONFIG-002" "CF_MODE requires a domain name, not an IP address." \
        "Set DOMAIN to a valid DNS name when enabling CF_MODE." \
        "DOMAIN=example.com CF_MODE=1 bash install.sh"
    fi

    ENABLE_REALITY="${ENABLE_REALITY:-0}"
    ENABLE_WS="${ENABLE_WS:-1}"
    ENABLE_HY2="${ENABLE_HY2:-0}"
    ENABLE_TUIC="${ENABLE_TUIC:-0}"
    ENABLE_TROJAN="${ENABLE_TROJAN:-0}"

    if [[ "${WS_PORT_USER_SPECIFIED:-0}" == "1" ]]; then
      WS_PORT="${WS_PORT:-443}"
    else
      WS_PORT="443"
    fi

    echo
    info "Cloudflare proxy mode enabled (CF_MODE=1)"
    info "  - VLESS-WS-TLS will use port ${WS_PORT}"
    [[ "${ENABLE_REALITY}" == "0" ]] && info "  - Reality protocol: disabled (not compatible with CF proxy)"
    [[ "${ENABLE_REALITY}" == "1" ]] && info "  - Reality protocol: enabled on fallback port (direct connection only)"
    [[ "${ENABLE_HY2}" == "0" ]] && info "  - Hysteria2 protocol: disabled (CF doesn't proxy UDP)"
    echo
    warn "Cloudflare settings required:"
    warn "  - DNS proxy status: Proxied (orange cloud)"
    warn "  - SSL/TLS mode: Full or Full (strict)"
    echo
  else
    ENABLE_REALITY="${ENABLE_REALITY:-1}"
    ENABLE_WS="${ENABLE_WS:-1}"
    ENABLE_HY2="${ENABLE_HY2:-1}"
    ENABLE_TUIC="${ENABLE_TUIC:-0}"
    ENABLE_TROJAN="${ENABLE_TROJAN:-0}"
  fi
  export ENABLE_REALITY ENABLE_WS ENABLE_HY2 ENABLE_TUIC ENABLE_TROJAN
}

# Validate protocol configuration
_validate_protocol_config() {
  if [[ "${REALITY_ONLY_MODE:-0}" == "1" ]]; then
    if [[ "${ENABLE_REALITY}" != "1" ]]; then
      die_with_code "SBX-CONFIG-003" "Reality must stay enabled in IP-only mode." \
        "Set ENABLE_REALITY=1 when DOMAIN is an IP or omitted." \
        "ENABLE_REALITY=1 bash install.sh"
    fi
    return 0
  fi

  if [[ "${ENABLE_REALITY}" != "1" && "${ENABLE_WS}" != "1" && "${ENABLE_HY2}" != "1" &&
    "${ENABLE_TUIC:-0}" != "1" && "${ENABLE_TROJAN:-0}" != "1" ]]; then
    die_with_code "SBX-CONFIG-004" "All protocols are disabled." \
      "Enable at least one of ENABLE_REALITY, ENABLE_WS, ENABLE_HY2, ENABLE_TUIC, or ENABLE_TROJAN." \
      "ENABLE_REALITY=1 bash install.sh"
  fi

  return 0
}

# Configure Reality SNI domain with active validation and fallback probing.
# Sets: SNI
_configure_reality_sni() {
  local explicit_sni="${SNI_DOMAIN:-${SNI:-}}"
  local preferred_sni="${explicit_sni:-${SNI_DEFAULT}}"
  local fallback_sni_csv="${SNI_FALLBACK_DOMAINS:-www.apple.com,www.amazon.com}"
  local timeout_sec="${SNI_VALIDATION_TIMEOUT_SEC:-5}"
  local selected_sni=''

  # Keep default when Reality protocol is disabled.
  if [[ "${ENABLE_REALITY}" != "1" ]]; then
    export SNI="${preferred_sni}"
    return 0
  fi

  if ! command -v select_reality_sni_domain >/dev/null 2>&1; then
    warn "SNI probe helper unavailable, using ${preferred_sni}"
    export SNI="${preferred_sni}"
    return 0
  fi

  if selected_sni=$(select_reality_sni_domain "${preferred_sni}" "${fallback_sni_csv}" "${timeout_sec}"); then
    export SNI="${selected_sni}"
    if [[ "${selected_sni}" != "${preferred_sni}" ]]; then
      warn "Reality SNI fallback selected: ${selected_sni} (preferred ${preferred_sni} failed)"
    else
      success "  ✓ Reality SNI: ${selected_sni}"
    fi
    return 0
  fi

  if [[ -n "${explicit_sni}" ]]; then
    die_with_code "SBX-CONFIG-005" "Configured SNI domain failed validation: ${explicit_sni}." \
      "Provide a reachable TLS1.3-capable SNI domain." \
      "SNI_DOMAIN=www.microsoft.com bash install.sh"
  fi

  warn "All SNI probes failed, using default ${preferred_sni}"
  export SNI="${preferred_sni}"
  return 0
}

# Generate cryptographic credentials
# Sets: UUID, PRIV, PUB, SID, HY2_PASS, TUIC_PASS, TROJAN_PASS
_generate_credentials() {
  export UUID
  UUID=$(generate_uuid)
  success "  ✓ UUID generated"

  local keypair=''
  keypair=$(generate_reality_keypair) || die_with_code "SBX-CONFIG-006" "Failed to generate Reality keypair." \
    "Ensure openssl is available and retry." \
    "openssl rand -hex 32"
  export PRIV PUB
  read -r PRIV PUB <<<"${keypair}"
  success "  ✓ Reality keypair generated"

  export SID
  SID=$(openssl rand -hex 4)
  validate_short_id "${SID}" || die_with_code "SBX-CONFIG-007" "Generated invalid short ID: ${SID}." \
    "Regenerate short ID with 1-8 hex chars."
  success "  ✓ Short ID generated: ${SID}"

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    if [[ "${ENABLE_TUIC:-0}" == "1" ]]; then
      export TUIC_PASS
      TUIC_PASS=$(generate_hex_string 16)
      success "  ✓ TUIC password generated"
    fi

    if [[ "${ENABLE_TROJAN:-0}" == "1" ]]; then
      export TROJAN_PASS
      TROJAN_PASS=$(generate_hex_string 16)
      success "  ✓ Trojan password generated"
    fi
  fi
}

# Allocate ports for enabled protocols
# Sets: REALITY_PORT_CHOSEN, WS_PORT_CHOSEN, HY2_PORT_CHOSEN, HY2_PASS
_allocate_ports() {
  msg "Allocating ports..."

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    export REALITY_PORT_CHOSEN
    REALITY_PORT_CHOSEN=$(allocate_port "${REALITY_PORT}" "${REALITY_PORT_FALLBACK}" "Reality") || die_with_code "SBX-NETWORK-003" "Failed to allocate Reality port." \
      "Free occupied ports or set REALITY_PORT to an available one." \
      "REALITY_PORT=30443 bash install.sh"
    success "  ✓ Reality port: ${REALITY_PORT_CHOSEN}"
  else
    export REALITY_PORT_CHOSEN=""
  fi

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    export WS_PORT_CHOSEN="" HY2_PORT_CHOSEN="" HY2_PASS=""
    export TUIC_PORT_CHOSEN="" TROJAN_PORT_CHOSEN=""

    if [[ "${ENABLE_WS}" == "1" ]]; then
      WS_PORT_CHOSEN=$(allocate_port "${WS_PORT}" "${WS_PORT_FALLBACK}" "WS-TLS") || die_with_code "SBX-NETWORK-004" "Failed to allocate WS port." \
        "Free occupied ports or set WS_PORT to an available one." \
        "WS_PORT=30444 bash install.sh"
      success "  ✓ WS-TLS port: ${WS_PORT_CHOSEN}"
    fi

    if [[ "${ENABLE_HY2}" == "1" ]]; then
      HY2_PORT_CHOSEN=$(allocate_port "${HY2_PORT}" "${HY2_PORT_FALLBACK}" "Hysteria2") || die_with_code "SBX-NETWORK-005" "Failed to allocate Hysteria2 port." \
        "Free occupied ports or set HY2_PORT to an available one." \
        "HY2_PORT=30445 bash install.sh"
      HY2_PASS=$(generate_hex_string 16)
      success "  ✓ Hysteria2 port: ${HY2_PORT_CHOSEN}"
    fi

    if [[ "${ENABLE_TUIC:-0}" == "1" ]]; then
      TUIC_PORT_CHOSEN=$(allocate_port "${TUIC_PORT}" "${TUIC_PORT_FALLBACK}" "TUIC") || die_with_code "SBX-NETWORK-006" "Failed to allocate TUIC port." \
        "Free occupied ports or set TUIC_PORT to an available one." \
        "TUIC_PORT=8445 bash install.sh"
      success "  ✓ TUIC port: ${TUIC_PORT_CHOSEN}"
    fi

    if [[ "${ENABLE_TROJAN:-0}" == "1" ]]; then
      TROJAN_PORT_CHOSEN=$(allocate_port "${TROJAN_PORT}" "${TROJAN_PORT_FALLBACK}" "Trojan") || die_with_code "SBX-NETWORK-007" "Failed to allocate Trojan port." \
        "Free occupied ports or set TROJAN_PORT to an available one." \
        "TROJAN_PORT=8446 bash install.sh"
      success "  ✓ Trojan port: ${TROJAN_PORT_CHOSEN}"
    fi
  fi
}

# Generate configuration materials (UUIDs, keys, ports, etc.)
# Orchestrates the configuration material generation process
gen_materials() {
  msg "Generating configuration materials..."

  _configure_server_address
  _configure_cloudflare_mode
  _validate_protocol_config
  _configure_reality_sni
  _generate_credentials
  _allocate_ports

  success "Configuration materials generated successfully"
}

# Save client information for sbx-manager
save_client_info() {
  msg "Saving client information..."

  cat >"${CLIENT_INFO}" <<EOF
# sing-box client configuration
# Generated: $(date)

DOMAIN="${DOMAIN}"
UUID="${UUID}"
PUBLIC_KEY="${PUB}"
SHORT_ID="${SID}"
SNI="${SNI:-${SNI_DEFAULT}}"
REALITY_PORT="${REALITY_PORT_CHOSEN}"
EOF

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    if [[ "${ENABLE_WS:-0}" == "1" ]]; then
      cat >>"${CLIENT_INFO}" <<EOF
WS_PORT="${WS_PORT_CHOSEN}"
EOF
    fi

    if [[ "${ENABLE_HY2:-0}" == "1" ]]; then
      cat >>"${CLIENT_INFO}" <<EOF
HY2_PORT="${HY2_PORT_CHOSEN}"
HY2_PASS="${HY2_PASS}"
EOF
    fi

    if [[ "${ENABLE_TUIC:-0}" == "1" ]]; then
      cat >>"${CLIENT_INFO}" <<EOF
TUIC_PORT="${TUIC_PORT_CHOSEN}"
TUIC_PASS="${TUIC_PASS}"
EOF
    fi

    if [[ "${ENABLE_TROJAN:-0}" == "1" ]]; then
      cat >>"${CLIENT_INFO}" <<EOF
TROJAN_PORT="${TROJAN_PORT_CHOSEN}"
TROJAN_PASS="${TROJAN_PASS}"
EOF
    fi

    if [[ -n "${CERT_FULLCHAIN:-}" || -n "${CERT_KEY:-}" ]]; then
      cat >>"${CLIENT_INFO}" <<EOF
CERT_FULLCHAIN="${CERT_FULLCHAIN}"
CERT_KEY="${CERT_KEY}"
EOF
    fi
  fi

  chmod "${SECURE_FILE_PERMISSIONS}" "${CLIENT_INFO}"
  success "  ✓ Client info saved to: ${CLIENT_INFO}"
}

# Save structured state for future compatibility and typed access.
save_state_info() {
  msg "Saving structured state..."

  local state_file="${TEST_STATE_FILE:-${STATE_FILE}}"
  local mode="multi_protocol"
  local installed_at=''
  local resolved_version=''
  local server_domain=''
  local server_ip=''
  local ws_enabled=false
  local hy2_enabled=false
  local cert_path=''
  local cert_key=''
  local ws_port=''
  local hy2_port=''
  local hy2_pass=''

  [[ "${REALITY_ONLY_MODE:-0}" == "1" ]] && mode="reality_only"
  installed_at=$(date -Iseconds 2>/dev/null || date)
  resolved_version=$(get_installed_version 2>/dev/null || echo "")

  if validate_ip_address "${DOMAIN}" >/dev/null 2>&1; then
    server_ip="${DOMAIN}"
  else
    server_domain="${DOMAIN}"
  fi

  local tuic_enabled=false
  local trojan_enabled=false
  local tuic_port=''
  local tuic_pass=''
  local trojan_port=''
  local trojan_pass=''

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    local enable_ws="${ENABLE_WS:-}"
    local enable_hy2="${ENABLE_HY2:-}"
    local enable_tuic="${ENABLE_TUIC:-0}"
    local enable_trojan="${ENABLE_TROJAN:-0}"

    [[ -z "${enable_ws}" && -n "${WS_PORT_CHOSEN:-}" ]] && enable_ws="1"
    [[ -z "${enable_hy2}" && -n "${HY2_PORT_CHOSEN:-}" ]] && enable_hy2="1"

    if [[ "${enable_ws}" == "1" ]]; then
      ws_enabled=true
      ws_port="${WS_PORT_CHOSEN:-}"
    fi

    if [[ "${enable_hy2}" == "1" ]]; then
      hy2_enabled=true
      hy2_port="${HY2_PORT_CHOSEN:-}"
      hy2_pass="${HY2_PASS:-}"
    fi

    if [[ "${enable_tuic}" == "1" ]]; then
      tuic_enabled=true
      tuic_port="${TUIC_PORT_CHOSEN:-}"
      tuic_pass="${TUIC_PASS:-}"
    fi

    if [[ "${enable_trojan}" == "1" ]]; then
      trojan_enabled=true
      trojan_port="${TROJAN_PORT_CHOSEN:-}"
      trojan_pass="${TROJAN_PASS:-}"
    fi

    cert_path="${CERT_FULLCHAIN:-}"
    cert_key="${CERT_KEY:-}"
  fi

  jq -n \
    --arg version "1.0" \
    --arg installed_at "${installed_at}" \
    --arg singbox_version "${resolved_version}" \
    --arg mode "${mode}" \
    --arg server_domain "${server_domain}" \
    --arg server_ip "${server_ip}" \
    --arg reality_uuid "${UUID}" \
    --arg reality_public_key "${PUB}" \
    --arg reality_short_id "${SID}" \
    --arg reality_sni "${SNI:-${SNI_DEFAULT}}" \
    --argjson reality_port "${REALITY_PORT_CHOSEN:-0}" \
    --argjson ws_enabled "${ws_enabled}" \
    --argjson ws_port "${ws_port:-0}" \
    --arg cert_path "${cert_path}" \
    --arg cert_key "${cert_key}" \
    --argjson hy2_enabled "${hy2_enabled}" \
    --argjson hy2_port "${hy2_port:-0}" \
    --arg hy2_pass "${hy2_pass}" \
    --argjson tuic_enabled "${tuic_enabled}" \
    --argjson tuic_port "${tuic_port:-0}" \
    --arg tuic_pass "${tuic_pass}" \
    --argjson trojan_enabled "${trojan_enabled}" \
    --argjson trojan_port "${trojan_port:-0}" \
    --arg trojan_pass "${trojan_pass}" \
    '{
      version: $version,
      installed_at: $installed_at,
      singbox_version: (if $singbox_version == "" then null else $singbox_version end),
      mode: $mode,
      server: {
        domain: (if $server_domain == "" then null else $server_domain end),
        ip: (if $server_ip == "" then null else $server_ip end)
      },
      protocols: {
        reality: {
          enabled: true,
          port: (if $reality_port == 0 then null else $reality_port end),
          uuid: $reality_uuid,
          public_key: $reality_public_key,
          short_id: $reality_short_id,
          sni: $reality_sni
        },
        ws_tls: {
          enabled: $ws_enabled,
          port: (if $ws_enabled and $ws_port != 0 then $ws_port else null end),
          certificate: (if $ws_enabled and $cert_path != "" then $cert_path else null end),
          key: (if $ws_enabled and $cert_key != "" then $cert_key else null end)
        },
        hysteria2: {
          enabled: $hy2_enabled,
          port: (if $hy2_enabled and $hy2_port != 0 then $hy2_port else null end),
          password: (if $hy2_enabled and $hy2_pass != "" then $hy2_pass else null end)
        },
        tuic: {
          enabled: $tuic_enabled,
          port: (if $tuic_enabled and $tuic_port != 0 then $tuic_port else null end),
          password: (if $tuic_enabled and $tuic_pass != "" then $tuic_pass else null end)
        },
        trojan: {
          enabled: $trojan_enabled,
          port: (if $trojan_enabled and $trojan_port != 0 then $trojan_port else null end),
          password: (if $trojan_enabled and $trojan_pass != "" then $trojan_pass else null end)
        }
      }
    }' >"${state_file}"

  chmod "${SECURE_FILE_PERMISSIONS}" "${state_file}"
  success "  ✓ State saved to: ${state_file}"
}

# Install sbx-manager script
install_manager_script() {
  msg "Installing management script..."

  local manager_template="${SCRIPT_DIR}/bin/sbx-manager.sh"
  local manager_path="/usr/local/bin/sbx-manager"
  local symlink_path="/usr/local/bin/sbx"
  local lib_path="/usr/local/lib/sbx"
  local backup_path=''
  local temp_manager=''

  if [[ -f "${manager_template}" ]]; then
    # Safely handle existing manager binary
    if [[ -e "${manager_path}" && ! -f "${manager_path}" ]]; then
      die_with_code "SBX-SYSTEM-020" "${manager_path} exists but is not a regular file." \
        "Remove or rename the path before installing sbx-manager."
    fi

    # Safely handle existing symlink
    if [[ -L "${symlink_path}" ]]; then
      # It's a symlink, safe to remove and recreate
      rm "${symlink_path}"
    elif [[ -e "${symlink_path}" ]]; then
      # File exists but is not a symlink - backup and warn
      backup_path="${symlink_path}.backup.$(date +%s)"
      warn "File exists at ${symlink_path} (not a symlink)"
      mv "${symlink_path}" "${backup_path}"
      warn "  Backed up to ${backup_path}"
    fi

    # Install manager using temporary file + atomic move
    temp_manager=$(create_temp_file "manager") || die_with_code "SBX-SYSTEM-021" "Failed to create temporary file for manager installation." \
      "Check temporary directory permissions and free disk space."
    chmod 755 "${temp_manager}" # Manager needs executable permission
    cp "${manager_template}" "${temp_manager}" || {
      rm -f "${temp_manager}"
      die_with_code "SBX-SYSTEM-022" "Failed to copy manager template." \
        "Verify installer files are intact and readable."
    }

    # Atomic move to final location
    mv "${temp_manager}" "${manager_path}" || die_with_code "SBX-SYSTEM-023" "Failed to install manager." \
      "Check write permission for /usr/local/bin."

    # Create symlink safely
    ln -sf "${manager_path}" "${symlink_path}"

    # Safely install library modules
    if [[ -e "${lib_path}" && ! -d "${lib_path}" ]]; then
      die_with_code "SBX-SYSTEM-024" "${lib_path} exists but is not a directory." \
        "Remove or rename the path before installation."
    fi

    mkdir -p "${lib_path}"
    cp "${SCRIPT_DIR}"/lib/*.sh "${lib_path}/"
    chmod 644 "${lib_path}"/*.sh

    success "  ✓ Management commands installed: sbx-manager, sbx"
    success "  ✓ Library modules installed to ${lib_path}/"
  else
    # This fallback should never be reached in one-liner install (we download the file now)
    # Keep as safety net for unexpected scenarios
    err "Manager template not found at: ${manager_template}"
    err "This indicates an installation issue. Please report this error."
    err "Creating minimal fallback version (limited functionality)..."

    # Fallback to inline version if template not found
    cat >/usr/local/bin/sbx-manager <<'EOF'
#!/bin/bash
case "$1" in
    info)
      [[ -f /etc/sing-box/state.json ]] && cat /etc/sing-box/state.json
      [[ -f /etc/sing-box/client-info.txt ]] && cat /etc/sing-box/client-info.txt
      ;;
    status) systemctl status sing-box ;;
    restart) systemctl restart sing-box ;;
    *) echo "Usage: sbx {info|status|restart}"; exit 1 ;;
esac
EOF
    chmod +x /usr/local/bin/sbx-manager
    ln -sf /usr/local/bin/sbx-manager /usr/local/bin/sbx

    warn "  ⚠ WARNING: Minimal manager installed (missing advanced features)"
    warn "     - 'sbx info' will not show URIs or QR code hints"
    warn "     - 'sbx qr' command not available"
    warn "     - 'sbx export' and 'sbx backup' commands not available"
    warn ""
    warn "  To get full functionality, please reinstall or manually download:"
    warn "  curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/bin/sbx-manager.sh \\"
    warn "    -o /usr/local/bin/sbx-manager && chmod 755 /usr/local/bin/sbx-manager"
  fi
}

# Open firewall ports
open_firewall() {
  local ports_to_open=()
  [[ -n "${REALITY_PORT_CHOSEN:-}" ]] && ports_to_open+=("${REALITY_PORT_CHOSEN}")

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    [[ -n "${WS_PORT_CHOSEN:-}" ]] && ports_to_open+=("${WS_PORT_CHOSEN}")
    [[ -n "${HY2_PORT_CHOSEN:-}" ]] && ports_to_open+=("${HY2_PORT_CHOSEN}")
    [[ -n "${TUIC_PORT_CHOSEN:-}" ]] && ports_to_open+=("${TUIC_PORT_CHOSEN}")
    [[ -n "${TROJAN_PORT_CHOSEN:-}" ]] && ports_to_open+=("${TROJAN_PORT_CHOSEN}")
  fi

  [[ ${#ports_to_open[@]} -eq 0 ]] && return 0

  msg "Configuring firewall..."

  # TUIC uses UDP; Hysteria2 also uses UDP
  _is_udp_port() {
    local p="$1"
    [[ -n "${HY2_PORT_CHOSEN:-}" && "${p}" == "${HY2_PORT_CHOSEN}" ]] && return 0
    [[ -n "${TUIC_PORT_CHOSEN:-}" && "${p}" == "${TUIC_PORT_CHOSEN}" ]] && return 0
    return 1
  }

  # Try different firewall managers
  if have firewall-cmd; then
    for port in "${ports_to_open[@]}"; do
      firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null || true
      _is_udp_port "${port}" && firewall-cmd --permanent --add-port="${port}/udp" 2>/dev/null || true
    done
    firewall-cmd --reload 2>/dev/null || true
    success "  ✓ Firewall configured (firewalld)"
  elif have ufw; then
    for port in "${ports_to_open[@]}"; do
      ufw allow "${port}/tcp" 2>/dev/null || true
      _is_udp_port "${port}" && ufw allow "${port}/udp" 2>/dev/null || true
    done
    success "  ✓ Firewall configured (ufw)"
  else
    info "  ℹ No firewall manager detected (firewall-cmd/ufw)"
    info "  ℹ Manually open ports: ${ports_to_open[*]}"
  fi
}

# Print installation summary
print_summary() {
  echo
  echo -e "${B}${G}═══════════════════════════════════════${N}"
  echo -e "${B}${G}   Installation Complete!${N}"
  echo -e "${B}${G}═══════════════════════════════════════${N}"
  echo
  echo -e "${G}✓${N} sing-box installed and running"
  echo -e "${G}✓${N} Configuration: ${SB_CONF}"
  echo -e "${G}✓${N} Service: systemctl status sing-box"
  echo
  echo -e "${CYAN}Server:${N} ${DOMAIN}"
  echo -e "${CYAN}Protocols:${N}"

  # Show protocols based on ENABLE_* variables
  local enable_reality="${ENABLE_REALITY:-1}"
  local enable_ws="${ENABLE_WS:-1}"
  local enable_hy2="${ENABLE_HY2:-1}"
  local enable_tuic="${ENABLE_TUIC:-0}"
  local enable_trojan="${ENABLE_TROJAN:-0}"

  if [[ "${enable_reality}" == "1" && -n "${REALITY_PORT_CHOSEN:-}" ]]; then
    echo "  • VLESS-REALITY (port ${REALITY_PORT_CHOSEN})"
  fi

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    if [[ "${enable_ws}" == "1" && -n "${WS_PORT_CHOSEN:-}" ]]; then
      echo "  • VLESS-WS-TLS (port ${WS_PORT_CHOSEN})"
    fi
    if [[ "${enable_hy2}" == "1" && -n "${HY2_PORT_CHOSEN:-}" ]]; then
      echo "  • Hysteria2 (port ${HY2_PORT_CHOSEN})"
    fi
    if [[ "${enable_tuic}" == "1" && -n "${TUIC_PORT_CHOSEN:-}" ]]; then
      echo "  • TUIC V5 (port ${TUIC_PORT_CHOSEN})"
    fi
    if [[ "${enable_trojan}" == "1" && -n "${TROJAN_PORT_CHOSEN:-}" ]]; then
      echo "  • Trojan (port ${TROJAN_PORT_CHOSEN})"
    fi
  fi

  # Show Cloudflare mode instructions
  if [[ "${CF_MODE:-0}" == "1" ]]; then
    echo
    echo -e "${Y}⚠ Cloudflare Proxy Mode Enabled${N}"
    echo -e "${CYAN}Cloudflare Settings Required:${N}"
    echo "  • DNS Proxy Status: Orange cloud (Proxied)"
    echo "  • SSL/TLS Mode: Full"
    echo "  • Only VLESS-WS-TLS works through CF proxy"
  fi

  # Display connection URIs
  echo
  echo -e "${CYAN}=== Client Connection URIs ===${N}"
  echo

  # Reality URI (if enabled)
  if [[ "${enable_reality}" == "1" && -n "${REALITY_PORT_CHOSEN:-}" ]]; then
    local reality_sni="${SNI:-${SNI_DEFAULT}}"
    local uri_real="vless://${UUID}@${DOMAIN}:${REALITY_PORT_CHOSEN}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${reality_sni}&pbk=${PUB}&sid=${SID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
    echo -e "${G}VLESS-Reality:${N}"
    echo "  ${uri_real}"
  fi

  # WS-TLS, Hysteria2, TUIC, Trojan URIs (if not Reality-only mode and enabled)
  if [[ "${REALITY_ONLY_MODE:-0}" != "1" && -n "${CERT_FULLCHAIN:-}" ]]; then
    if [[ "${enable_ws}" == "1" && -n "${WS_PORT_CHOSEN:-}" ]]; then
      echo
      local uri_ws="vless://${UUID}@${DOMAIN}:${WS_PORT_CHOSEN}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
      echo -e "${G}VLESS-WS-TLS:${N}"
      echo "  ${uri_ws}"
    fi

    if [[ "${enable_hy2}" == "1" && -n "${HY2_PORT_CHOSEN:-}" ]]; then
      echo
      local uri_hy2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT_CHOSEN}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
      echo -e "${G}Hysteria2:${N}"
      echo "  ${uri_hy2}"
    fi

    if [[ "${enable_tuic}" == "1" && -n "${TUIC_PORT_CHOSEN:-}" ]]; then
      echo
      local uri_tuic="tuic://${UUID}:${TUIC_PASS}@${DOMAIN}:${TUIC_PORT_CHOSEN}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#TUIC-${DOMAIN}"
      echo -e "${G}TUIC V5:${N}"
      echo "  ${uri_tuic}"
    fi

    if [[ "${enable_trojan}" == "1" && -n "${TROJAN_PORT_CHOSEN:-}" ]]; then
      echo
      local uri_trojan="trojan://${TROJAN_PASS}@${DOMAIN}:${TROJAN_PORT_CHOSEN}?sni=${DOMAIN}&security=tls&type=tcp&fp=chrome#Trojan-${DOMAIN}"
      echo -e "${G}Trojan:${N}"
      echo "  ${uri_trojan}"
    fi
  fi

  echo
  echo -e "${Y}Management Commands:${N}"
  echo "  sbx info      - Show configuration and connection URIs"
  echo "  sbx status    - Check service status"
  echo "  sbx restart   - Restart service"
  echo "  sbx log       - View live logs"
  echo "  sbx backup    - Backup/restore configuration"
  echo "  sbx export    - Export client configurations"
  echo "  sbx help      - Show all commands"
  echo
  echo -e "${CYAN}💡 Tip:${N} Use '${B}sbx info${N}' to view this information again"
  echo
}

#==============================================================================
# Main Installation Flow
#==============================================================================

dry_run_flow() {
  show_logo

  local mode_desc=''
  local display_domain="${DOMAIN:-}"
  local reality_port_preview=''
  local ws_port_preview=''
  local hy2_port_preview=''
  local sni_preview="${SNI_DOMAIN:-${SNI:-${SNI_DEFAULT}}}"
  local cert_desc=''
  local arch_desc=''
  local -a preview_ports=()

  if [[ -z "${DOMAIN:-}" ]]; then
    export REALITY_ONLY_MODE=1
    mode_desc="Reality-only (no domain specified)"
    display_domain="<auto-detect during install>"
  elif validate_ip_address "${DOMAIN}" >/dev/null 2>&1; then
    export REALITY_ONLY_MODE=1
    mode_desc="Reality-only (ip: ${DOMAIN})"
    display_domain="${DOMAIN}"
  elif validate_domain "${DOMAIN}"; then
    export REALITY_ONLY_MODE=0
    mode_desc="Multi-protocol (domain: ${DOMAIN})"
    display_domain="${DOMAIN}"
  else
    die_with_code "SBX-CONFIG-001" "Invalid domain or IP address: ${DOMAIN}" \
      "Provide a valid public domain (example.com) or public IP address." \
      "DOMAIN=example.com bash install.sh"
  fi

  _configure_cloudflare_mode
  _validate_protocol_config
  reality_port_preview="${REALITY_PORT:-${REALITY_PORT_DEFAULT}}"
  ws_port_preview="${WS_PORT:-${WS_PORT_DEFAULT}}"
  hy2_port_preview="${HY2_PORT:-${HY2_PORT_DEFAULT}}"
  local tuic_port_preview="${TUIC_PORT:-${TUIC_PORT_DEFAULT}}"
  local trojan_port_preview="${TROJAN_PORT:-${TROJAN_PORT_DEFAULT}}"

  echo
  echo "sbx dry-run preview:"
  echo "  Mode: ${mode_desc}"
  echo "  Server: ${display_domain}"
  echo "  Protocols:"

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    echo "    - VLESS-REALITY on port ${reality_port_preview}/tcp"
    preview_ports+=("${reality_port_preview}/tcp")
  fi

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    if [[ "${ENABLE_WS}" == "1" ]]; then
      echo "    - VLESS-WS-TLS on port ${ws_port_preview}/tcp"
      preview_ports+=("${ws_port_preview}/tcp")
    fi
    if [[ "${ENABLE_HY2}" == "1" ]]; then
      echo "    - Hysteria2 on port ${hy2_port_preview}/udp"
      preview_ports+=("${hy2_port_preview}/udp")
    fi
    if [[ "${ENABLE_TUIC:-0}" == "1" ]]; then
      echo "    - TUIC V5 on port ${tuic_port_preview}/udp"
      preview_ports+=("${tuic_port_preview}/udp")
    fi
    if [[ "${ENABLE_TROJAN:-0}" == "1" ]]; then
      echo "    - Trojan on port ${trojan_port_preview}/tcp"
      preview_ports+=("${trojan_port_preview}/tcp")
    fi
  fi

  if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
    if [[ -n "${CERT_FULLCHAIN:-}" && -n "${CERT_KEY:-}" ]]; then
      cert_desc="Manual certificate files"
    elif [[ "${CERT_MODE:-}" == "cf_dns" ]]; then
      cert_desc="ACME DNS-01 (Cloudflare API)"
    else
      cert_desc="ACME HTTP-01 (port 80 required)"
    fi
    echo "  Certificates: ${cert_desc}"
  fi

  arch_desc=$(uname -m 2>/dev/null || echo "unknown")
  echo "  SNI: ${sni_preview} (validated during real install)"
  echo "  Binary: sing-box ${SINGBOX_VERSION:-stable} (${arch_desc})"
  echo "  Config: ${SB_CONF}"
  echo "  Service: ${SB_SVC}"

  if [[ ${#preview_ports[@]} -gt 0 ]]; then
    echo "  Firewall: open ${preview_ports[*]}"
  else
    echo "  Firewall: no protocol ports selected"
  fi

  echo "  No changes made."
}

install_flow() {
  show_logo
  need_root

  # Validate environment variables if provided
  if [[ -n "${DOMAIN:-}" ]]; then
    validate_env_vars
  fi

  # Check for existing installation
  check_existing_installation

  # Ensure required tools
  ensure_tools

  # Download sing-box binary
  download_singbox

  # Generate configuration (unless skip flag is set)
  if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
    gen_materials

    # Issue certificate if not Reality-only mode
    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      maybe_issue_cert
    fi

    # Create ACME data directory for native certificate management
    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      mkdir -p "${ACME_DATA_DIRECTORY}"
      chmod "${SECURE_DIR_PERMISSIONS}" "${ACME_DATA_DIRECTORY}"
    fi

    # Write configuration
    write_config

    # Setup and start service
    setup_service

    # Save client info
    save_client_info
    save_state_info

    # Install manager script
    install_manager_script
  else
    success "Binary upgrade completed, preserving existing configuration"
    restart_service
  fi

  # Configure firewall
  open_firewall

  # Show summary
  if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
    print_summary
  else
    success "Upgrade complete! Run 'sbx info' to view configuration"
  fi
}

#==============================================================================
# Uninstall Flow
#==============================================================================

uninstall_flow() {
  show_logo
  need_root

  # Show what will be removed
  echo
  warn "The following will be completely removed:"
  [[ -x "${SB_BIN}" ]] && echo "  - Binary: ${SB_BIN}"
  [[ -f "${SB_CONF}" ]] && echo "  - Config: ${SB_CONF}"
  [[ -d "${SB_CONF_DIR}" ]] && echo "  - Config directory: ${SB_CONF_DIR}"
  [[ -f "${SB_SVC}" ]] && echo "  - Service: ${SB_SVC}"
  [[ -x "/usr/local/bin/sbx-manager" ]] && echo "  - Management commands: sbx-manager, sbx"
  [[ -d "/usr/local/lib/sbx" ]] && echo "  - Library modules: /usr/local/lib/sbx"
  [[ -d "${CERT_DIR_BASE}" ]] && echo "  - Certificates: ${CERT_DIR_BASE}"

  if [[ "${FORCE:-0}" != "1" ]]; then
    echo
    if ! prompt_yes_no "Continue with complete removal?" N; then
      msg "Uninstall cancelled"
      exit 0
    fi
  fi

  echo
  msg "Removing sing-box..."

  # Stop and disable service
  if check_service_status; then
    stop_service
  fi

  # Remove service
  remove_service

  # Remove files
  msg "Removing files..."
  rm -f "${SB_BIN}" /usr/local/bin/sbx-manager /usr/local/bin/sbx
  rm -rf "${SB_CONF_DIR}" "${CERT_DIR_BASE}" /usr/local/lib/sbx
  rm -rf "${ACME_DATA_DIRECTORY}"

  # Remove legacy Caddy if installed (pre-1.13.0 installations)
  if have caddy; then
    msg "Removing legacy Caddy installation..."
    caddy_uninstall || warn "Failed to remove Caddy completely"
  fi

  success "sing-box uninstalled successfully"
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
  local action="install"
  local dry_run=0
  local arg=''

  for arg in "$@"; do
    case "${arg}" in
      uninstall | remove)
        action="uninstall"
        ;;
      --dry-run)
        dry_run=1
        ;;
      "") ;;
      *)
        die_with_code "SBX-CLI-001" "Unknown argument: ${arg}" \
          "Use supported arguments only." \
          "bash install.sh --help"
        ;;
    esac
  done

  if [[ "${action}" == "uninstall" ]]; then
    if [[ "${dry_run}" == "1" ]]; then
      die_with_code "SBX-CLI-002" "--dry-run is not supported for uninstall." \
        "Run dry-run only for install flow, or remove --dry-run for uninstall." \
        "bash install.sh uninstall"
    fi
    uninstall_flow
    return
  fi

  if [[ "${dry_run}" == "1" ]]; then
    dry_run_flow
  else
    install_flow
  fi
}

# Execute main function only when run directly (not when sourced for tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
