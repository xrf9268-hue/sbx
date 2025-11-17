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
  input="$(printf '%s' "$input" | tr -d ';|&`$()<>')"
  # Limit length after sanitization
  input="${input:0:${MAX_INPUT_LENGTH:-256}}"
  printf '%s' "$input"
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
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    err "${port_name} must be numeric: $port"
    return 1
  fi

  # Validate range (1-65535)
  if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
    err "${port_name} must be between 1-65535: $port"
    return 1
  fi

  return 0
}

# Validate domain format with comprehensive checks
validate_domain() {
  local domain="$1"

  # Enhanced domain validation
  [[ -n "$domain" ]] || return 1

  # Check length (max 253 characters for FQDN)
  [[ ${#domain} -le "${MAX_DOMAIN_LENGTH:-253}" ]] || return 1

  # Must contain at least one dot (require domain.tld format)
  [[ "$domain" =~ \. ]] || return 1

  # Check for valid domain format (letters, numbers, dots, hyphens only)
  [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1

  # Must not start or end with hyphen or dot
  [[ ! "$domain" =~ ^[-.]|[-.]$ ]] || return 1

  # Must not contain consecutive dots
  [[ ! "$domain" =~ \.\. ]] || return 1

  # Each label (part between dots) must not end with hyphen
  # Split by dots and check each label
  local IFS='.'
  local -a labels
  read -ra labels <<< "$domain"
  for label in "${labels[@]}"; do
    # Label must not be empty
    [[ -n "$label" ]] || return 1
    # Label must not end with hyphen
    [[ ! "$label" =~ -$ ]] || return 1
  done

  # Reserved names
  [[ "$domain" != "localhost" ]] || return 1
  [[ "$domain" != "127.0.0.1" ]] || return 1
  [[ ! "$domain" =~ ^[0-9.]+$ ]] || return 1  # Not an IP address

  return 0
}

#==============================================================================
# Certificate Validation
#==============================================================================

# Validate certificate files with comprehensive security checks
validate_cert_files() {
  local fullchain="$1"
  local key="$2"

  # Step 1: Basic path validation
  if [[ -z "$fullchain" || -z "$key" ]]; then
    err "Certificate paths cannot be empty"
    return 1
  fi

  # Step 2: File existence check
  if [[ ! -f "$fullchain" ]]; then
    err "Certificate file not found: $fullchain"
    return 1
  fi
  if [[ ! -f "$key" ]]; then
    err "Private key file not found: $key"
    return 1
  fi

  # Step 3: File readability check
  if [[ ! -r "$fullchain" ]]; then
    err "Certificate file not readable: $fullchain"
    return 1
  fi
  if [[ ! -r "$key" ]]; then
    err "Private key file not readable: $key"
    return 1
  fi

  # Step 4: Non-empty file check
  if [[ ! -s "$fullchain" ]]; then
    err "Certificate file is empty: $fullchain"
    return 1
  fi
  if [[ ! -s "$key" ]]; then
    err "Private key file is empty: $key"
    return 1
  fi

  # Step 5: Certificate format validation
  if ! openssl x509 -in "$fullchain" -noout 2>/dev/null; then
    err "Invalid certificate format (not a valid X.509 certificate)"
    err "  File: $fullchain"
    return 1
  fi

  # Step 6: Private key format validation
  # Try to parse as any valid key type (RSA, EC, Ed25519, etc.)
  if ! openssl pkey -in "$key" -noout 2>/dev/null; then
    err "Invalid private key format (not a valid private key)"
    err "  File: $key"
    return 1
  fi

  # Step 7: Certificate expiration check (warning only)
  if ! openssl x509 -in "$fullchain" -checkend 2592000 -noout 2>/dev/null; then
    warn "Certificate will expire within 30 days"
  fi

  # Step 8: Certificate-Key matching validation
  # Extract public key hash from certificate
  local cert_pubkey
  cert_pubkey=$(openssl x509 -in "$fullchain" -noout -pubkey 2>/dev/null | openssl md5 2>/dev/null | awk '{print $2}')

  if [[ -z "$cert_pubkey" || "$cert_pubkey" == "$EMPTY_MD5_HASH" ]]; then
    err "Failed to extract public key from certificate"
    err "  This may indicate a corrupted certificate file"
    return 1
  fi

  # Extract public key hash from private key using generic pkey command
  local key_pubkey
  key_pubkey=$(openssl pkey -in "$key" -pubout 2>/dev/null | openssl md5 2>/dev/null | awk '{print $2}')

  if [[ -z "$key_pubkey" || "$key_pubkey" == "$EMPTY_MD5_HASH" ]]; then
    err "Failed to extract public key from private key"
    err "  This may indicate a corrupted or unsupported key file"
    return 1
  fi

  # Compare public key hashes
  if [[ "$cert_pubkey" != "$key_pubkey" ]]; then
    err "Certificate and private key do not match"
    err "  Certificate pubkey MD5: $cert_pubkey"
    err "  Private key pubkey MD5: $key_pubkey"
    err "  Make sure the certificate was generated from this private key"
    return 1
  fi

  # All validations passed
  success "Certificate validation passed"
  debug "Certificate: $fullchain"
  debug "Private key: $key"
  debug "Certificate-key match confirmed (pubkey MD5: $cert_pubkey)"

  # Log expiry information if available
  local expiry_date
  expiry_date=$(openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2)
  [[ -n "$expiry_date" ]] && debug "Certificate expires: $expiry_date"

  return 0
}

#==============================================================================
# Environment Variables Validation
#==============================================================================

# Validate environment variables on startup
validate_env_vars() {
  # Validate DOMAIN if provided
  if [[ -n "$DOMAIN" ]]; then
    # Check if it's an IP address or domain
    if validate_ip_address "$DOMAIN" 2>/dev/null; then
      msg "Using IP address mode: $DOMAIN"
    elif validate_domain "$DOMAIN"; then
      msg "Using domain mode: $DOMAIN"
    else
      die "Invalid DOMAIN format: $DOMAIN"
    fi
  fi

  # Validate certificate mode
  if [[ -n "$CERT_MODE" ]]; then
    case "$CERT_MODE" in
      cf_dns)
        [[ -n "$CF_Token" ]] || die "CF_Token required for Cloudflare DNS-01 challenge"
        ;;
      le_http)
        # No additional validation needed
        ;;
      *)
        die "Invalid CERT_MODE: $CERT_MODE (must be cf_dns or le_http)"
        ;;
    esac
  fi

  # Validate certificate files if provided
  if [[ -n "$CERT_FULLCHAIN" || -n "$CERT_KEY" ]]; then
    [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]] || \
      die "Both CERT_FULLCHAIN and CERT_KEY must be specified together"

    validate_cert_files "$CERT_FULLCHAIN" "$CERT_KEY" || \
      die "Certificate file validation failed"
  fi

  # Validate port numbers if custom values provided
  if [[ -n "${REALITY_PORT}" && "${REALITY_PORT}" != "$REALITY_PORT_DEFAULT" ]]; then
    validate_port "$REALITY_PORT" || die "Invalid REALITY_PORT: $REALITY_PORT"
  fi

  if [[ -n "${WS_PORT}" && "${WS_PORT}" != "$WS_PORT_DEFAULT" ]]; then
    validate_port "$WS_PORT" || die "Invalid WS_PORT: $WS_PORT"
  fi

  if [[ -n "${HY2_PORT}" && "${HY2_PORT}" != "$HY2_PORT_DEFAULT" ]]; then
    validate_port "$HY2_PORT" || die "Invalid HY2_PORT: $HY2_PORT"
  fi

  # Validate version string if provided
  if [[ -n "$SINGBOX_VERSION" ]]; then
    [[ "$SINGBOX_VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || \
      die "Invalid SINGBOX_VERSION format: $SINGBOX_VERSION"
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
  [[ "$sid" =~ $pattern ]] || {
    err "Invalid Reality short ID: $sid"
    err ""
    err "Requirements:"
    err "  - Length: ${REALITY_SHORT_ID_MIN_LENGTH}-${REALITY_SHORT_ID_MAX_LENGTH} hexadecimal characters"
    err "  - Format: Only 0-9, a-f, A-F allowed"
    err "  - Example: a1b2c3d4"
    err ""
    err "Generate valid short ID:"
    err "  openssl rand -hex 4"
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
  [[ -n "$sni" ]] || {
    err "Invalid Reality SNI: Cannot be empty"
    err ""
    err "The SNI (Server Name Indication) is used for the Reality handshake."
    err "Choose a high-traffic domain that supports TLS 1.3."
    err ""
    err "Recommended SNI domains:"
    err "  - www.microsoft.com (default)"
    err "  - www.apple.com"
    err "  - www.amazon.com"
    err "  - www.cloudflare.com"
    err ""
    err "Avoid:"
    err "  - Government websites"
    err "  - Censored domains"
    err "  - Low-traffic sites"
    err ""
    err "See: docs/REALITY_BEST_PRACTICES.md for SNI selection guide"
    return 1
  }

  # Allow wildcard domains for Reality (e.g., *.example.com)
  local cleaned_sni="${sni#\*.}"

  # Check basic domain format (alphanumeric, dots, hyphens)
  [[ "$cleaned_sni" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?$ ]] || {
    err "Invalid Reality SNI format: $sni"
    err ""
    err "Requirements:"
    err "  - Valid domain name (RFC 1035)"
    err "  - Max length: 253 characters"
    err "  - Format: letters, numbers, dots, hyphens only"
    err "  - Must start and end with alphanumeric character"
    err ""
    err "Examples:"
    err "  ✓ www.microsoft.com"
    err "  ✓ *.cloudflare.com (wildcard)"
    err "  ✗ microsoft.com- (ends with hyphen)"
    err "  ✗ -microsoft.com (starts with hyphen)"
    err ""
    err "Current value: $sni"
    return 1
  }

  # Validate domain doesn't contain invalid patterns
  if [[ "$cleaned_sni" =~ \.\. ]]; then
    err "Invalid Reality SNI: Contains consecutive dots: $sni"
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
  [[ -n "$priv" ]] || {
    err "Invalid Reality keypair: Private key cannot be empty"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    err ""
    err "Example output:"
    err "  PrivateKey: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
    err "  PublicKey:  jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
    return 1
  }
  [[ -n "$pub" ]] || {
    err "Invalid Reality keypair: Public key cannot be empty"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    return 1
  }

  # Validate format: base64url characters (A-Za-z0-9_-)
  # Reality keys are base64url-encoded without padding
  [[ "$priv" =~ ^[A-Za-z0-9_-]+$ ]] || {
    err "Invalid Reality private key format"
    err ""
    err "Requirements:"
    err "  - Base64url encoding (A-Za-z0-9_-)"
    err "  - No padding (=) characters"
    err "  - Length: 42-44 characters"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    return 1
  }
  [[ "$pub" =~ ^[A-Za-z0-9_-]+$ ]] || {
    err "Invalid Reality public key format"
    err ""
    err "Requirements:"
    err "  - Base64url encoding (A-Za-z0-9_-)"
    err "  - No padding (=) characters"
    err "  - Length: 42-44 characters"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    return 1
  }

  # X25519 keys are 32 bytes, base64url-encoded = 43 chars
  # Allow some flexibility (42-44 chars)
  local priv_len="${#priv}"
  local pub_len="${#pub}"

  if [[ $priv_len -lt 42 || $priv_len -gt 44 ]]; then
    err "Private key has invalid length: $priv_len"
    err "Expected: 42-44 characters (X25519 key = 32 bytes base64url-encoded)"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    return 1
  fi
  if [[ $pub_len -lt 42 || $pub_len -gt 44 ]]; then
    err "Public key has invalid length: $pub_len"
    err "Expected: 42-44 characters (X25519 key = 32 bytes base64url-encoded)"
    err ""
    err "Generate valid keypair:"
    err "  sing-box generate reality-keypair"
    return 1
  fi

  return 0
}

# Validate transport+security+flow pairing for VLESS
# Vision flow requires TCP transport with Reality security
validate_transport_security_pairing() {
  local transport="${1:-tcp}"  # Default to TCP
  local security="${2:-}"      # TLS, Reality, or none
  local flow="${3:-}"          # xtls-rprx-vision or empty

  # Validate Vision flow requirements
  if [[ "$flow" == "xtls-rprx-vision" ]]; then
    # Vision REQUIRES TCP transport
    if [[ "$transport" != "tcp" ]]; then
      err "Vision flow (xtls-rprx-vision) requires TCP transport, got: $transport"
      err "Valid combinations:"
      err "  - Transport: tcp, Security: reality, Flow: xtls-rprx-vision"
      return 1
    fi

    # Vision REQUIRES Reality security
    if [[ "$security" != "reality" ]]; then
      err "Vision flow (xtls-rprx-vision) requires Reality security, got: $security"
      err "For TLS security, use flow=\"\" (empty flow field)"
      return 1
    fi
  fi

  # Validate Reality security requirements
  if [[ "$security" == "reality" ]]; then
    # Reality works with TCP (and theoretically others, but Vision requires TCP)
    if [[ -n "$flow" && "$flow" != "xtls-rprx-vision" ]]; then
      warn "Reality security with non-Vision flow: $flow"
      warn "Common configuration uses flow=\"xtls-rprx-vision\" with Reality"
    fi
  fi

  # Validate incompatible combinations
  case "$transport:$security" in
    "ws:reality")
      err "WebSocket transport is incompatible with Reality security"
      err "Use: ws+tls or tcp+reality"
      return 1
      ;;
    "grpc:reality")
      err "gRPC transport is incompatible with Reality security"
      err "Use: grpc+tls or tcp+reality"
      return 1
      ;;
    "http:reality")
      err "HTTP transport is incompatible with Reality security"
      err "Use: tcp+reality for Vision protocol"
      return 1
      ;;
  esac

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

  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  [[ "$choice" -ge "$min" && "$choice" -le "$max" ]] || return 1

  return 0
}

# Validate Yes/No input
validate_yes_no() {
  local input="$1"
  [[ "$input" =~ ^[YyNn]$ ]] || return 1
  return 0
}

#==============================================================================
# Configuration File Validation
#==============================================================================

# Validate sing-box configuration JSON syntax
validate_singbox_config() {
  local config_file="${1:-$SB_CONF}"

  [[ -f "$config_file" ]] || {
    err "Configuration file not found: $config_file"
    return 1
  }

  # Check if sing-box binary exists
  [[ -f "$SB_BIN" ]] || {
    err "sing-box binary not found: $SB_BIN"
    return 1
  }

  # Use sing-box built-in validation
  if ! "$SB_BIN" check -c "$config_file" 2>&1; then
    err "Configuration validation failed"
    return 1
  fi

  return 0
}

# Validate JSON syntax using jq
validate_json_syntax() {
  local json_file="$1"

  [[ -f "$json_file" ]] || return 1

  if have jq; then
    jq empty < "$json_file" 2>/dev/null || return 1
  else
    # Fallback: basic JSON validation with python
    if have python3; then
      python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null || return 1
    elif have python; then
      python -c "import json; json.load(open('$json_file'))" 2>/dev/null || return 1
    else
      warn "Neither jq nor python available for JSON validation"
      return 0
    fi
  fi

  return 0
}

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
  local transport="${1:-tcp}"  # Default to TCP
  local security="${2:-}"      # TLS, Reality, or none
  local flow="${3:-}"          # xtls-rprx-vision or empty

  # Validate Vision flow requirements
  if [[ "$flow" == "xtls-rprx-vision" ]]; then
    # Vision REQUIRES TCP transport
    if [[ "$transport" != "tcp" ]]; then
      err "Invalid configuration: Vision flow requires TCP transport"
      err ""
      err "Current settings:"
      err "  Transport: $transport"
      err "  Security:  $security"
      err "  Flow:      $flow"
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
    if [[ "$security" != "reality" ]]; then
      err "Invalid configuration: Vision flow requires Reality security"
      err ""
      err "Current settings:"
      err "  Transport: $transport"
      err "  Security:  $security"
      err "  Flow:      $flow"
      err ""
      err "Valid Vision configuration:"
      err "  Transport: tcp"
      err "  Security:  reality"
      err "  Flow:      xtls-rprx-vision"
      err ""
      err "For TLS security, use flow=\"\" (empty flow field)"
      return 1
    fi
  fi

  # Validate Reality security requirements
  if [[ "$security" == "reality" ]]; then
    # Reality works best with TCP (and Vision flow)
    if [[ -n "$flow" && "$flow" != "xtls-rprx-vision" ]]; then
      warn "Unusual configuration: Reality security with non-Vision flow: $flow"
      warn "Common Reality configuration uses flow=\"xtls-rprx-vision\""
    fi
  fi

  # Validate incompatible transport+security combinations
  case "$transport:$security" in
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
  esac

  # If we reach here, pairing is valid
  msg "Transport+security+flow pairing validated: $transport+$security${flow:++$flow}"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f sanitize_input validate_port validate_domain validate_cert_files validate_env_vars
export -f validate_short_id validate_reality_sni validate_menu_choice validate_yes_no
export -f validate_singbox_config validate_json_syntax validate_transport_security_pairing
