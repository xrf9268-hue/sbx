#!/usr/bin/env bash
# lib/validation.sh - Input validation and security checks
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_VALIDATION_LOADED:-}" ]] && return 0
readonly _SBX_VALIDATION_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/tools.sh"

# Declare external variables from common.sh
# shellcheck disable=SC2154
: "${CERT_EXPIRY_WARNING_SEC:?}" "${CERT_EXPIRY_WARNING_DAYS:?}"
# shellcheck disable=SC2154
: "${REALITY_PORT_DEFAULT:?}" "${WS_PORT_DEFAULT:?}" "${HY2_PORT_DEFAULT:?}"
# shellcheck disable=SC2154
: "${REALITY_SHORT_ID_MIN_LENGTH:?}" "${REALITY_SHORT_ID_MAX_LENGTH:?}"
# shellcheck disable=SC2154
: "${X25519_KEY_MIN_LENGTH:?}" "${X25519_KEY_MAX_LENGTH:?}" "${X25519_KEY_BYTES:?}"
# shellcheck disable=SC2154
: "${SB_BIN:?}"

#==============================================================================
# Module Constants
#==============================================================================

# MD5 hash constant for empty input (indicates openssl extraction failure)
readonly EMPTY_MD5_HASH="d41d8cd98f00b204e9800998ecf8427e"

#==============================================================================
# Input Sanitization
#==============================================================================

# Enhanced input sanitization to prevent command injection
sanitize_input() {
  local input="$1"
  # Remove potential dangerous characters using tr for explicit character removal
  # This avoids escaping issues with backticks in parameter expansion
  input="$(printf '%s' "${input}" | tr -d ';|&`$()<>')"
  # Limit length after sanitization
  input="${input:0:${MAX_INPUT_LENGTH:-256}}"
  printf '%s' "${input}"
}

#==============================================================================
# Domain and Network Validation
#==============================================================================

# Validate port number (canonical implementation)
# Validates that port is numeric and within valid range (1-65535)
# Args:
#   $1 - port number to validate
#   $2 - (optional) descriptive name for error messages (default: "Port")
# Returns:
#   0 - port is valid
#   1 - port is invalid
# Example:
#   validate_port 443 "HTTPS Port" || die "Invalid HTTPS port"
validate_port() {
  local port="$1"
  local port_name="${2:-Port}"

  # Validate numeric
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    err "${port_name} must be numeric: ${port}"
    return 1
  fi

  # Validate range (1-65535)
  if [[ "${port}" -lt 1 || "${port}" -gt 65535 ]]; then
    err "${port_name} must be between 1-65535: ${port}"
    return 1
  fi

  return 0
}

# Validate domain format with comprehensive checks
validate_domain() {
  local domain="$1"

  # Enhanced domain validation
  [[ -n "${domain}" ]] || return 1

  # Check length (max 253 characters for FQDN)
  [[ ${#domain} -le "${MAX_DOMAIN_LENGTH:-253}" ]] || return 1

  # Must contain at least one dot (require domain.tld format)
  [[ "${domain}" =~ \. ]] || return 1

  # Check for valid domain format (letters, numbers, dots, hyphens only)
  [[ "${domain}" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1

  # Must not start or end with hyphen or dot
  [[ ! "${domain}" =~ ^[-.]|[-.]$ ]] || return 1

  # Must not contain consecutive dots
  [[ ! "${domain}" =~ \.\. ]] || return 1

  # Each label (part between dots) must not end with hyphen
  # Split by dots and check each label
  # Note: 'local IFS' creates function-scoped variable, automatically restored on return
  local IFS='.'
  local -a labels
  read -ra labels <<< "${domain}"
  for label in "${labels[@]}"; do
    # Label must not be empty
    [[ -n "${label}" ]] || return 1
    # Label must not end with hyphen
    [[ ! "${label}" =~ -$ ]] || return 1
  done

  # Reserved names
  [[ "${domain}" != "localhost" ]] || return 1
  [[ "${domain}" != "127.0.0.1" ]] || return 1
  [[ ! "${domain}" =~ ^[0-9.]+$ ]] || return 1 # Not an IP address

  return 0
}

#==============================================================================
# Certificate Validation
#==============================================================================

# Validate certificate files with comprehensive security checks
validate_cert_files() {
  local fullchain="$1"
  local key="$2"

  # Step 1: Basic file integrity validation (existence, readability, non-empty)
  if ! validate_file_integrity "${fullchain}" true 1; then
    err "Certificate file validation failed: ${fullchain}"
    return 1
  fi
  if ! validate_file_integrity "${key}" true 1; then
    err "Private key file validation failed: ${key}"
    return 1
  fi

  # Step 2: Certificate format validation
  if ! openssl x509 -in "${fullchain}" -noout 2> /dev/null; then
    err "Invalid certificate format (not a valid X.509 certificate)"
    err "  File: ${fullchain}"
    return 1
  fi

  # Step 3: Private key format validation
  # Try to parse as any valid key type (RSA, EC, Ed25519, etc.)
  if ! openssl pkey -in "${key}" -noout 2> /dev/null; then
    err "Invalid private key format (not a valid private key)"
    err "  File: ${key}"
    return 1
  fi

  # Step 4: Certificate expiration check (warning only)
  if ! openssl x509 -in "${fullchain}" -checkend "${CERT_EXPIRY_WARNING_SEC}" -noout 2> /dev/null; then
    warn "Certificate will expire within ${CERT_EXPIRY_WARNING_DAYS} days"
  fi

  # Step 5: Certificate-Key matching validation
  # Extract public key hash from certificate
  local cert_pubkey=''
  cert_pubkey=$(openssl x509 -in "${fullchain}" -noout -pubkey 2> /dev/null | openssl md5 2> /dev/null | awk '{print $2}')

  if [[ -z "${cert_pubkey}" || "${cert_pubkey}" == "${EMPTY_MD5_HASH}" ]]; then
    err "Failed to extract public key from certificate"
    err "  This may indicate a corrupted certificate file"
    return 1
  fi

  # Extract public key hash from private key using generic pkey command
  local key_pubkey=''
  key_pubkey=$(openssl pkey -in "${key}" -pubout 2> /dev/null | openssl md5 2> /dev/null | awk '{print $2}')

  if [[ -z "${key_pubkey}" || "${key_pubkey}" == "${EMPTY_MD5_HASH}" ]]; then
    err "Failed to extract public key from private key"
    err "  This may indicate a corrupted or unsupported key file"
    return 1
  fi

  # Compare public key hashes
  if [[ "${cert_pubkey}" != "${key_pubkey}" ]]; then
    err "Certificate and private key do not match"
    err "  Certificate pubkey MD5: ${cert_pubkey}"
    err "  Private key pubkey MD5: ${key_pubkey}"
    err "  Make sure the certificate was generated from this private key"
    return 1
  fi

  # All validations passed
  success "Certificate validation passed"
  debug "Certificate: ${fullchain}"
  debug "Private key: ${key}"
  debug "Certificate-key match confirmed (pubkey MD5: ${cert_pubkey})"

  # Log expiry information if available
  local expiry_date=''
  expiry_date=$(openssl x509 -in "${fullchain}" -noout -enddate 2> /dev/null | cut -d= -f2)
  [[ -n "${expiry_date}" ]] && debug "Certificate expires: ${expiry_date}"

  return 0
}

#==============================================================================
# Cloudflare API Token Validation
#==============================================================================

# Validate Cloudflare API Token format
# Args: $1 - token string
# Returns: 0 if valid, 1 if invalid
validate_cf_api_token() {
  local token="${1:-}"

  # Check non-empty
  [[ -z "${token}" ]] && return 1

  # Check length bounds
  local len=${#token}
  [[ ${len} -lt ${CF_API_TOKEN_MIN_LENGTH} || ${len} -gt ${CF_API_TOKEN_MAX_LENGTH} ]] && return 1

  # Check format (alphanumeric, underscores, dashes)
  [[ ! "${token}" =~ ^[a-zA-Z0-9_-]+$ ]] && return 1

  return 0
}

#==============================================================================
# Environment Variables Validation
#==============================================================================

# Validate environment variables on startup
validate_env_vars() {
  # Validate DOMAIN if provided
  if [[ -n "${DOMAIN}" ]]; then
    # Check if it's an IP address or domain
    if validate_ip_address "${DOMAIN}" 2> /dev/null; then
      msg "Using IP address mode: ${DOMAIN}"
    elif validate_domain "${DOMAIN}"; then
      msg "Using domain mode: ${DOMAIN}"
    else
      die "Invalid DOMAIN format: ${DOMAIN}"
    fi
  fi

  # Validate certificate mode
  if [[ -n "${CERT_MODE}" ]]; then
    case "${CERT_MODE}" in
      cf_dns)
        # Support legacy CF_Token for backward compatibility
        if [[ -z "${CF_API_TOKEN:-}" && -n "${CF_Token:-}" ]]; then
          export CF_API_TOKEN="${CF_Token}"
          warn "CF_Token is deprecated, use CF_API_TOKEN instead"
        fi
        [[ -n "${CF_API_TOKEN:-}" ]] || die "CF_API_TOKEN required for Cloudflare DNS-01 challenge"
        validate_cf_api_token "${CF_API_TOKEN}" || die "Invalid CF_API_TOKEN format (must be ${CF_API_TOKEN_MIN_LENGTH}-${CF_API_TOKEN_MAX_LENGTH} alphanumeric characters)"
        ;;
      le_http | caddy)
        # No additional validation needed for HTTP-01 challenge
        ;;
      *)
        die "Invalid CERT_MODE: ${CERT_MODE} (must be cf_dns, caddy, or le_http)"
        ;;
    esac
  fi

  # Validate certificate files if provided
  if [[ -n "${CERT_FULLCHAIN}" || -n "${CERT_KEY}" ]]; then
    [[ -n "${CERT_FULLCHAIN}" && -n "${CERT_KEY}" ]] \
      || die "Both CERT_FULLCHAIN and CERT_KEY must be specified together"

    validate_cert_files "${CERT_FULLCHAIN}" "${CERT_KEY}" \
      || die "Certificate file validation failed"
  fi

  # Validate port numbers if custom values provided
  if [[ -n "${REALITY_PORT}" && "${REALITY_PORT}" != "${REALITY_PORT_DEFAULT}" ]]; then
    validate_port "${REALITY_PORT}" || die "Invalid REALITY_PORT: ${REALITY_PORT}"
  fi

  if [[ -n "${WS_PORT}" && "${WS_PORT}" != "${WS_PORT_DEFAULT}" ]]; then
    validate_port "${WS_PORT}" || die "Invalid WS_PORT: ${WS_PORT}"
  fi

  if [[ -n "${HY2_PORT}" && "${HY2_PORT}" != "${HY2_PORT_DEFAULT}" ]]; then
    validate_port "${HY2_PORT}" || die "Invalid HY2_PORT: ${HY2_PORT}"
  fi

  # Validate version string if provided
  if [[ -n "${SINGBOX_VERSION}" ]]; then
    [[ "${SINGBOX_VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] \
      || die "Invalid SINGBOX_VERSION format: ${SINGBOX_VERSION}"
  fi

  return 0
}

#==============================================================================
# Reality Configuration Validation
#==============================================================================

# Validate Reality short ID (must be exactly 8 hex characters for sing-box)
validate_short_id() {
  local sid="$1"

  # Allow 1-8 hexadecimal characters for flexibility (using constants)
  # Note: sing-box typically uses 8 chars, but shorter IDs are valid
  local pattern="^[0-9a-fA-F]{${REALITY_SHORT_ID_MIN_LENGTH},${REALITY_SHORT_ID_MAX_LENGTH}}$"
  [[ "${sid}" =~ ${pattern} ]] || {
    format_validation_error_with_command "Reality short ID" "${sid}" "openssl rand -hex 4" \
      "Length: ${REALITY_SHORT_ID_MIN_LENGTH}-${REALITY_SHORT_ID_MAX_LENGTH} hexadecimal characters" \
      "Format: Only 0-9, a-f, A-F allowed" \
      "Example: a1b2c3d4"
    err ""
    err "Note: sing-box uses 8-char short IDs (different from Xray's 16-char limit)"
    return 1
  }
  return 0
}

# Validate Reality SNI (Server Name Indication for handshake)
# The SNI should be a high-traffic domain that supports TLS 1.3
validate_reality_sni() {
  local sni="$1"

  # Must be non-empty
  [[ -n "${sni}" ]] || {
    format_validation_error "Reality SNI" "(empty)" \
      "The SNI (Server Name Indication) is used for the Reality handshake" \
      "Choose a high-traffic domain that supports TLS 1.3" \
      "" \
      "Recommended: www.microsoft.com (default), www.apple.com, www.amazon.com, www.cloudflare.com" \
      "Avoid: Government websites, censored domains, low-traffic sites"
    err ""
    err "See: docs/REALITY_BEST_PRACTICES.md for SNI selection guide"
    return 1
  }

  # Allow wildcard domains for Reality (e.g., *.example.com)
  local cleaned_sni="${sni#\*.}"

  # Check basic domain format (alphanumeric, dots, hyphens)
  [[ "${cleaned_sni}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?$ ]] || {
    format_validation_error "Reality SNI format" "${sni}" \
      "Valid domain name (RFC 1035)" \
      "Max length: 253 characters" \
      "Format: letters, numbers, dots, hyphens only" \
      "Must start and end with alphanumeric character"
    err ""
    err "Examples:"
    err "  ✓ www.microsoft.com"
    err "  ✓ *.cloudflare.com (wildcard)"
    err "  ✗ microsoft.com- (ends with hyphen)"
    err "  ✗ -microsoft.com (starts with hyphen)"
    return 1
  }

  # Validate domain doesn't contain invalid patterns
  if [[ "${cleaned_sni}" =~ \.\. ]]; then
    err "Invalid Reality SNI: Contains consecutive dots: ${sni}"
    err ""
    err "Domain names cannot have consecutive dots (..)"
    err "Example: www..microsoft.com is invalid"
    return 1
  fi

  return 0
}

# Validate Reality keypair (X25519 private and public keys)
validate_reality_keypair() {
  local priv="$1"
  local pub="$2"

  # Both keys must be non-empty
  [[ -n "${priv}" ]] || {
    format_validation_error_with_command "Reality keypair" "(empty private key)" \
      "sing-box generate reality-keypair" \
      "Private key cannot be empty" \
      "Example: PrivateKey: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
    return 1
  }
  [[ -n "${pub}" ]] || {
    format_validation_error_with_command "Reality keypair" "(empty public key)" \
      "sing-box generate reality-keypair" \
      "Public key cannot be empty"
    return 1
  }

  # Validate format: base64url characters (A-Za-z0-9_-)
  # Reality keys are base64url-encoded without padding
  [[ "${priv}" =~ ^[A-Za-z0-9_-]+$ ]] || {
    format_validation_error_with_command "Reality private key" "${priv}" \
      "sing-box generate reality-keypair" \
      "Base64url encoding (A-Za-z0-9_-)" \
      "No padding (=) characters" \
      "Length: 42-44 characters"
    return 1
  }
  [[ "${pub}" =~ ^[A-Za-z0-9_-]+$ ]] || {
    format_validation_error_with_command "Reality public key" "${pub}" \
      "sing-box generate reality-keypair" \
      "Base64url encoding (A-Za-z0-9_-)" \
      "No padding (=) characters" \
      "Length: 42-44 characters"
    return 1
  }

  # X25519 keys are 32 bytes, base64url-encoded = 43 chars
  # Allow some flexibility (42-44 chars)
  local priv_len="${#priv}"
  local pub_len="${#pub}"

  if [[ ${priv_len} -lt "${X25519_KEY_MIN_LENGTH}" || ${priv_len} -gt "${X25519_KEY_MAX_LENGTH}" ]]; then
    format_validation_error_with_command "Reality private key length" "${priv_len}" \
      "sing-box generate reality-keypair" \
      "Expected: ${X25519_KEY_MIN_LENGTH}-${X25519_KEY_MAX_LENGTH} characters" \
      "X25519 key = ${X25519_KEY_BYTES} bytes base64url-encoded"
    return 1
  fi
  if [[ ${pub_len} -lt "${X25519_KEY_MIN_LENGTH}" || ${pub_len} -gt "${X25519_KEY_MAX_LENGTH}" ]]; then
    format_validation_error_with_command "Reality public key length" "${pub_len}" \
      "sing-box generate reality-keypair" \
      "Expected: ${X25519_KEY_MIN_LENGTH}-${X25519_KEY_MAX_LENGTH} characters" \
      "X25519 key = ${X25519_KEY_BYTES} bytes base64url-encoded"
    return 1
  fi

  return 0
}

#==============================================================================
# User Input Validation
#==============================================================================

# Validate numeric choice from menu
validate_menu_choice() {
  local choice="$1"
  local min="${2:-1}"
  local max="${3:-9}"

  [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
  [[ "${choice}" -ge "${min}" && "${choice}" -le "${max}" ]] || return 1

  return 0
}

# Validate Yes/No input
validate_yes_no() {
  local input="$1"
  [[ "${input}" =~ ^[YyNn]$ ]] || return 1
  return 0
}

#==============================================================================
# Configuration File Validation
#==============================================================================

# Validate sing-box configuration JSON syntax
validate_singbox_config() {
  local config_file="${1:-${SB_CONF}}"

  [[ -f "${config_file}" ]] || {
    err "Configuration file not found: ${config_file}"
    return 1
  }

  # Check if sing-box binary exists
  [[ -f "${SB_BIN}" ]] || {
    err "sing-box binary not found: ${SB_BIN}"
    return 1
  }

  # Use sing-box built-in validation
  if ! "${SB_BIN}" check -c "${config_file}" 2>&1; then
    err "Configuration validation failed"
    return 1
  fi

  return 0
}

# NOTE: validate_json_syntax() is now provided by lib/tools.sh
# This module sources lib/tools.sh which contains the authoritative implementation.
# The function is re-exported here for backward compatibility.

#==============================================================================
# Transport & Security Pairing Validation - Helper Functions
#==============================================================================

# Validate Vision flow requirements (TCP + Reality)
# Arguments:
#   $1 - transport value
#   $2 - security value
#   $3 - flow value
# Returns: 0 if valid, 1 if invalid
_validate_vision_requirements() {
  local transport="$1"
  local security="$2"
  local flow="$3"

  # Vision REQUIRES TCP transport
  if [[ "${transport}" != "tcp" ]]; then
    err "Invalid configuration: Vision flow requires TCP transport"
    err ""
    err "Current settings:"
    err "  Transport: ${transport}"
    err "  Security:  ${security}"
    err "  Flow:      ${flow}"
    err ""
    err "Valid Vision configuration:"
    err "  Transport: tcp"
    err "  Security:  reality"
    err "  Flow:      xtls-rprx-vision"
    err ""
    err "See: https://sing-box.sagernet.org/configuration/inbound/vless/"
    return 1
  fi

  # Vision REQUIRES Reality security
  if [[ "${security}" != "reality" ]]; then
    err "Invalid configuration: Vision flow requires Reality security"
    err ""
    err "Current settings:"
    err "  Transport: ${transport}"
    err "  Security:  ${security}"
    err "  Flow:      ${flow}"
    err ""
    err "Valid Vision configuration:"
    err "  Transport: tcp"
    err "  Security:  reality"
    err "  Flow:      xtls-rprx-vision"
    err ""
    err "For TLS security, use flow=\"\" (empty flow field)"
    return 1
  fi

  return 0
}

# Validate incompatible transport+security combinations
# Arguments:
#   $1 - transport value
#   $2 - security value
# Returns: 0 if valid, 1 if incompatible
_validate_incompatible_combinations() {
  local transport="$1"
  local security="$2"

  case "${transport}:${security}" in
    "ws:reality")
      err "Invalid configuration: WebSocket transport is incompatible with Reality security"
      err ""
      err "Valid alternatives:"
      err "  - WebSocket + TLS:     transport=ws,  security=tls"
      err "  - TCP + Reality:       transport=tcp, security=reality, flow=xtls-rprx-vision"
      err ""
      err "Reality protocol requires TCP transport for proper handshake"
      return 1
      ;;
    "grpc:reality")
      err "Invalid configuration: gRPC transport is incompatible with Reality security"
      err ""
      err "Valid alternatives:"
      err "  - gRPC + TLS:          transport=grpc, security=tls"
      err "  - TCP + Reality:       transport=tcp,  security=reality, flow=xtls-rprx-vision"
      err ""
      err "Reality protocol requires TCP transport for proper handshake"
      return 1
      ;;
    "http:reality")
      err "Invalid configuration: HTTP transport is incompatible with Reality security"
      err ""
      err "Valid alternatives:"
      err "  - HTTP + TLS:          transport=http, security=tls"
      err "  - TCP + Reality:       transport=tcp,  security=reality, flow=xtls-rprx-vision"
      err ""
      err "Use TCP+Reality for Vision protocol"
      return 1
      ;;
    "quic:reality")
      err "Invalid configuration: QUIC transport is incompatible with Reality security"
      err ""
      err "Valid alternatives:"
      err "  - TCP + Reality:       transport=tcp, security=reality, flow=xtls-rprx-vision"
      err ""
      err "Reality protocol requires TCP transport"
      return 1
      ;;
    *)
      # Valid combinations or unchecked pairs - allow through
      return 0
      ;;
  esac
}

#==============================================================================
# Transport & Security Pairing Validation - Main Function
#==============================================================================

# Validate transport+security+flow pairing for VLESS/Reality
# Ensures compatible combinations according to sing-box requirements
#
# Args:
#   $1 - transport type (tcp, ws, grpc, http, quic)
#   $2 - security type (reality, tls, none)
#   $3 - flow value (xtls-rprx-vision, empty)
#
# Returns:
#   0 if pairing is valid
#   1 if pairing is invalid
#
# sing-box Requirements:
#   - Vision flow (xtls-rprx-vision) REQUIRES TCP transport
#   - Vision flow (xtls-rprx-vision) REQUIRES Reality security
#   - WebSocket is INCOMPATIBLE with Reality (use WS+TLS instead)
#   - gRPC is INCOMPATIBLE with Reality (use gRPC+TLS instead)
#   - HTTP is INCOMPATIBLE with Reality (use TCP+Reality for Vision)
validate_transport_security_pairing() {
  local transport="${1:-tcp}" # Default to TCP
  local security="${2:-}"     # TLS, Reality, or none
  local flow="${3:-}"         # xtls-rprx-vision or empty

  # Validate Vision flow requirements
  if [[ "${flow}" == "xtls-rprx-vision" ]]; then
    _validate_vision_requirements "${transport}" "${security}" "${flow}" || return 1
  fi

  # Validate Reality security requirements
  if [[ "${security}" == "reality" ]]; then
    # Reality works best with TCP (and Vision flow)
    if [[ -n "${flow}" && "${flow}" != "xtls-rprx-vision" ]]; then
      warn "Unusual configuration: Reality security with non-Vision flow: ${flow}"
      warn "Common Reality configuration uses flow=\"xtls-rprx-vision\""
    fi
  fi

  # Validate incompatible transport+security combinations
  _validate_incompatible_combinations "${transport}" "${security}" || return 1

  # If we reach here, pairing is valid
  msg "Transport+security+flow pairing validated: ${transport}+${security}${flow:++${flow}}"
  return 0
}

#==============================================================================
# Parameter Validation Helpers
#==============================================================================

# Require a variable to be non-empty
#
# Usage: require VAR_NAME ["description"] || return 1
#
# Args:
#   $1 - Variable name (not the value!)
#   $2 - Optional description (defaults to variable name)
#
# Returns:
#   0 if variable is non-empty
#   1 if variable is empty or unset
#
# Examples:
#   require UUID || return 1
#   require DOMAIN "domain name" || return 1
#
require() {
  local var_name="$1"
  local description="${2:-${var_name}}"

  # Use indirect variable expansion to get the value
  local var_value="${!var_name:-}"

  if [[ -z "${var_value}" ]]; then
    err "Required parameter missing: ${description}"
    err "Variable: ${var_name}"
    return 1
  fi

  return 0
}

# Require multiple variables to be non-empty
#
# Usage: require_all VAR1 VAR2 VAR3 ... || return 1
#
# Args:
#   $@ - Variable names to check
#
# Returns:
#   0 if all variables are non-empty
#   1 if any variable is empty or unset
#
# Example:
#   require_all UUID DOMAIN PORT || return 1
#
require_all() {
  local var_name=''
  local failed=0

  for var_name in "$@"; do
    if ! require "${var_name}"; then
      failed=1
    fi
  done

  return "${failed}"
}

# Require variable and validate with function
#
# Usage: require_valid VAR_NAME "description" validator_function || return 1
#
# Args:
#   $1 - Variable name
#   $2 - Description
#   $3 - Validator function name
#
# Returns:
#   0 if variable exists and passes validation
#   1 if variable is empty or fails validation
#
# Example:
#   require_valid UUID "UUID" validate_uuid || return 1
#   require_valid DOMAIN "domain name" validate_domain || return 1
#
require_valid() {
  local var_name="$1"
  local description="$2"
  local validator="$3"

  # First check if variable exists
  require "${var_name}" "${description}" || return 1

  # Get the variable value
  local var_value="${!var_name}"

  # Run validator function
  if ! "${validator}" "${var_value}"; then
    err "Validation failed for: ${description}"
    err "Variable: ${var_name}"
    err "Value: ${var_value}"
    return 1
  fi

  return 0
}

#==============================================================================
# File Integrity Validation Helpers
#==============================================================================

# Validate file exists, readable, and optionally non-empty
#
# Usage: validate_file_integrity <file_path> [require_content] [min_size_bytes]
#
# Args:
#   $1 - File path to validate
#   $2 - Require non-empty content (default: true)
#   $3 - Minimum size in bytes (default: 1)
#
# Returns:
#   0 if file passes all checks
#   1 if any validation fails
#
# Examples:
#   validate_file_integrity "/etc/config.json" || return 1
#   validate_file_integrity "/tmp/data" true 100 || return 1
#   validate_file_integrity "/tmp/empty.txt" false || return 1
#
validate_file_integrity() {
  local file_path="$1"
  local require_content="${2:-true}"
  local min_size="${3:-1}"

  # Check file exists
  if [[ ! -e "${file_path}" ]]; then
    err "File not found: ${file_path}"
    err "Please ensure the file exists and path is correct"
    return 1
  fi

  # Check it's a regular file (not directory, symlink, etc.)
  if [[ ! -f "${file_path}" ]]; then
    err "Not a regular file: ${file_path}"
    if [[ -d "${file_path}" ]]; then
      err "Type: directory"
    else
      err "Type: $(file -b "${file_path}" 2> /dev/null || echo "unknown")"
    fi
    return 1
  fi

  # Check readable
  if [[ ! -r "${file_path}" ]]; then
    err "File not readable: ${file_path}"
    err "Permissions: $(ls -l "${file_path}" 2> /dev/null | awk '{print $1}' || echo "unknown")"
    err "Try: sudo chmod +r \"${file_path}\""
    return 1
  fi

  # Check size if required
  if [[ "${require_content}" == "true" ]]; then
    if [[ ! -s "${file_path}" ]]; then
      err "File is empty: ${file_path}"
      err "Size: 0 bytes"
      return 1
    fi

    # Check minimum size if specified
    local actual_size=0
    actual_size=$(get_file_size "${file_path}")
    if [[ "${actual_size}" -lt "${min_size}" ]]; then
      err "File too small: ${file_path}"
      err "Expected: at least ${min_size} bytes"
      err "Actual: ${actual_size} bytes"
      return 1
    fi
  fi

  return 0
}

# Validate multiple files at once
#
# Usage: validate_files_integrity <file1> <file2> ...
#
# Args:
#   $@ - File paths to validate
#
# Returns:
#   0 if all files pass validation
#   1 if any file fails validation
#
# Example:
#   validate_files_integrity "$CERT" "$KEY" || return 1
#
validate_files_integrity() {
  local file=''
  local failed=0

  for file in "$@"; do
    if ! validate_file_integrity "${file}"; then
      failed=1
    fi
  done

  return "${failed}"
}

#==============================================================================
# Export Functions
#==============================================================================

# Note: validate_json_syntax is defined in lib/tools.sh and re-exported here for compatibility
export -f sanitize_input validate_port validate_domain validate_cert_files validate_env_vars
export -f validate_short_id validate_reality_sni validate_menu_choice validate_yes_no
export -f validate_singbox_config validate_json_syntax validate_transport_security_pairing
export -f validate_cf_api_token
export -f require require_all require_valid
export -f validate_file_integrity validate_files_integrity
