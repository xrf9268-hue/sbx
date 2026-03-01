#!/usr/bin/env bash
# lib/config.sh - sing-box configuration generation
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CONFIG_LOADED:-}" ]] && return 0
readonly _SBX_CONFIG_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/network.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/validation.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/config_validator.sh"

# Declare external variables from common.sh
# shellcheck disable=SC2154
: "${REALITY_FLOW_VISION:?}" "${REALITY_MAX_TIME_DIFF:?}" "${REALITY_ALPN_H2:?}" "${REALITY_ALPN_HTTP11:?}"
# shellcheck disable=SC2154
: "${SB_CONF:?}" "${SB_CONF_DIR:?}" "${SB_SVC:?}" "${REALITY_DEFAULT_HANDSHAKE_PORT:?}"
# shellcheck disable=SC2154
: "${OUTBOUND_TCP_KEEP_ALIVE:?}" "${ACME_DATA_DIRECTORY:?}"
# Note: UUID, PRIV, SID, REALITY_PORT_CHOSEN are set dynamically during runtime

#==============================================================================
# Configuration Variables Validation
#==============================================================================

# Validate all required configuration variables are set
validate_config_vars() {
  msg "Validating configuration parameters..."

  # Required variables for all installations
  # Using require_all helper for cleaner validation
  if ! require_all UUID; then
    err "Configuration validation failed - see errors above"
    return 1
  fi

  # Reality is optional (e.g. CF_MODE WS-only), so only validate Reality vars when enabled.
  local enable_reality="${ENABLE_REALITY:-1}"
  if [[ "${enable_reality}" == "1" ]]; then
    if ! require_all REALITY_PORT_CHOSEN PRIV SID; then
      err "Configuration validation failed - see errors above"
      return 1
    fi
  fi

  success "  ✓ All required configuration parameters validated"
  return 0
}

#==============================================================================
# Base Configuration Generation
#==============================================================================

# Create base sing-box configuration
create_base_config() {
  local ipv6_supported="${1:-false}"
  local log_level="${2:-warn}"

  # Determine DNS strategy
  local dns_strategy=""
  if [[ "${ipv6_supported}" == "false" ]]; then
    msg "  - Applying IPv4-only DNS configuration for network compatibility"
    dns_strategy="ipv4_only"
  else
    msg "  - Using default DNS configuration for dual-stack network"
  fi

  # Build configuration with conditional DNS strategy injection
  local base_config=''
  if ! base_config=$(jq -n \
    --arg log_level "${log_level}" \
    --arg dns_strategy "${dns_strategy}" \
    '{
      log: { level: $log_level, timestamp: true },
      dns: ({
        servers: [{
          type: "local",
          tag: "dns-local"
        }]
      } + if $dns_strategy != "" then {strategy: $dns_strategy} else {} end),
      inbounds: [],
      outbounds: [
        { type: "direct", tag: "direct" }
      ]
    }' 2> /dev/null); then
    err "Failed to create base configuration with jq"
    return 1
  fi

  echo "${base_config}"
}

#==============================================================================
# Inbound Configuration Generation
#==============================================================================

# Create Reality inbound configuration
create_reality_inbound() {
  local uuid="$1"
  local port="$2"
  local listen_addr="$3"
  local sni="$4"
  local priv_key="$5"
  local short_id="$6"

  # Input validation with helpful guidance
  [[ -n "${uuid}" ]] || {
    format_validation_error_with_example "UUID" "(empty)" \
      "a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
      "UUID cannot be empty" \
      "Generate: sing-box generate uuid OR uuidgen"
    return 1
  }

  [[ -n "${priv_key}" ]] || {
    format_validation_error_with_command "Reality private key" "(empty)" \
      "sing-box generate reality-keypair" \
      "Private key cannot be empty" \
      "Example: PrivateKey: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc" \
      "Use PrivateKey on server, PublicKey on client"
    return 1
  }

  [[ -n "${short_id}" ]] || {
    format_validation_error_with_command "Reality short ID" "(empty)" \
      "openssl rand -hex 4" \
      "Short ID cannot be empty" \
      "Example: a1b2c3d4" \
      "Note: sing-box uses 8-char short IDs (different from Xray's 16-char)"
    return 1
  }

  # Validate port range
  if ! validate_port "${port}" 2> /dev/null; then
    err "Invalid port: ${port} (must be 1-65535)"
    return 1
  fi

  # Validate transport+security+flow pairing
  if ! validate_transport_security_pairing "tcp" "reality" "${REALITY_FLOW_VISION}" 2> /dev/null; then
    err "Invalid transport+security+flow combination for Reality"
    return 1
  fi

  local reality_config=''

  msg "  - Creating Reality inbound configuration..."

  if ! reality_config=$(jq -n \
    --arg uuid "${uuid}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --arg sni "${sni}" \
    --arg priv "${priv_key}" \
    --arg sid "${short_id}" \
    --arg flow "${REALITY_FLOW_VISION}" \
    --arg max_time_diff "${REALITY_MAX_TIME_DIFF}" \
    --arg alpn_h2 "${REALITY_ALPN_H2}" \
    --arg alpn_http11 "${REALITY_ALPN_HTTP11}" \
    --argjson handshake_port "${REALITY_DEFAULT_HANDSHAKE_PORT}" \
    '{
      type: "vless",
      tag: "in-reality",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid, flow: $flow }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: {
        enabled: true,
        server_name: $sni,
        reality: {
          enabled: true,
          private_key: $priv,
          short_id: [$sid],
          handshake: { server: $sni, server_port: $handshake_port },
          max_time_difference: $max_time_diff
        },
        alpn: [$alpn_h2, $alpn_http11]
      }
    }' 2>&1); then
    err "Failed to create Reality configuration. jq output:"
    err "${reality_config}"
    return 1
  fi

  success "  ✓ Reality inbound configured"
  echo "${reality_config}"
}

# Build TLS configuration block based on cert mode
# Returns a JSON TLS object for use in inbound configurations
# Args: domain alpn_json [cert_path key_path] OR [cert_mode cf_api_token]
_build_tls_block() {
  local domain="$1"
  local alpn_json="$2"
  local cert_path="${3:-}"
  local key_path="${4:-}"
  local cert_mode="${5:-}"
  local cf_api_token="${6:-}"

  local tls_block=''

  # Manual certificate mode: use certificate_path + key_path
  if [[ -n "${cert_path}" && -n "${key_path}" ]]; then
    if ! tls_block=$(jq -n \
      --arg domain "${domain}" \
      --argjson alpn "${alpn_json}" \
      --arg cert_path "${cert_path}" \
      --arg key_path "${key_path}" \
      '{
        enabled: true,
        server_name: $domain,
        certificate_path: $cert_path,
        key_path: $key_path,
        alpn: $alpn
      }' 2> /dev/null); then
      err "Failed to build manual TLS block"
      return 1
    fi
    echo "${tls_block}"
    return 0
  fi

  # ACME mode: build acme block based on cert_mode
  local acme_block=''
  case "${cert_mode}" in
    acme | caddy)
      # HTTP-01 challenge (disable TLS-ALPN to avoid port conflict)
      if ! acme_block=$(jq -n \
        --arg domain "${domain}" \
        '{
          domain: [$domain],
          data_directory: "/var/lib/sing-box/acme",
          email: "",
          provider: "letsencrypt",
          disable_tls_alpn_challenge: true
        }' 2> /dev/null); then
        err "Failed to build ACME HTTP-01 block"
        return 1
      fi
      ;;
    cf_dns)
      # DNS-01 challenge via Cloudflare (disable HTTP + TLS-ALPN challenges)
      if ! acme_block=$(jq -n \
        --arg domain "${domain}" \
        --arg api_token "${cf_api_token}" \
        '{
          domain: [$domain],
          data_directory: "/var/lib/sing-box/acme",
          email: "",
          provider: "letsencrypt",
          disable_http_challenge: true,
          disable_tls_alpn_challenge: true,
          dns01_challenge: {
            provider: "cloudflare",
            api_token: $api_token
          }
        }' 2> /dev/null); then
        err "Failed to build ACME DNS-01 block"
        return 1
      fi
      ;;
    *)
      err "Unknown cert_mode for ACME: ${cert_mode}"
      return 1
      ;;
  esac

  if ! tls_block=$(jq -n \
    --arg domain "${domain}" \
    --argjson alpn "${alpn_json}" \
    --argjson acme "${acme_block}" \
    '{
      enabled: true,
      server_name: $domain,
      alpn: $alpn,
      acme: $acme,
      certificate: { store: "chrome" }
    }' 2> /dev/null); then
    err "Failed to build ACME TLS block"
    return 1
  fi

  echo "${tls_block}"
}

# Create WS-TLS inbound configuration
# Args: uuid port listen_addr domain tls_json
create_ws_inbound() {
  local uuid="$1"
  local port="$2"
  local listen_addr="$3"
  local domain="$4"
  local tls_json="$5"

  local ws_config=''

  if ! ws_config=$(jq -n \
    --arg uuid "${uuid}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --argjson tls "${tls_json}" \
    '{
      type: "vless",
      tag: "in-ws",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: $tls,
      transport: { type: "ws", path: "/ws" }
    }' 2> /dev/null); then
    err "Failed to create WS-TLS configuration with jq"
    return 1
  fi

  echo "${ws_config}"
}

# Create Hysteria2 inbound configuration
# Args: password port listen_addr tls_json
create_hysteria2_inbound() {
  local password="$1"
  local port="$2"
  local listen_addr="$3"
  local tls_json="$4"

  local hy2_config=''

  if ! hy2_config=$(jq -n \
    --arg password "${password}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --argjson tls "${tls_json}" \
    '{
      type: "hysteria2",
      tag: "in-hy2",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ password: $password }],
      up_mbps: 100,
      down_mbps: 100,
      tls: $tls
    }' 2> /dev/null); then
    err "Failed to create Hysteria2 configuration with jq"
    return 1
  fi

  echo "${hy2_config}"
}

#==============================================================================
# Route Configuration
#==============================================================================

# Add route configuration for sing-box 1.13.0+ compatibility
add_route_config() {
  local config="$1"
  local has_certs="${2:-false}"

  local route_inbounds='["in-reality"]'
  if [[ "${has_certs}" == "true" ]]; then
    route_inbounds='["in-reality", "in-ws", "in-hy2"]'
  fi

  local updated_config=''
  if ! updated_config=$(echo "${config}" | jq --argjson inbounds "${route_inbounds}" '.route = {
    "rules": [
      {
        "inbound": $inbounds,
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ],
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-local"
    }
  }' 2> /dev/null); then
    err "Failed to add route configuration"
    return 1
  fi

  echo "${updated_config}"
}

#==============================================================================
# Outbound Configuration
#==============================================================================

# Add outbound configuration parameters
add_outbound_config() {
  local config="$1"

  # Detect kernel TLS offload support (Linux 5.1+ with TLS 1.3)
  local kernel_tls="false"
  local kernel_major="" kernel_minor=""
  kernel_major=$(uname -r | cut -d. -f1)
  kernel_minor=$(uname -r | cut -d. -f2)
  if [[ "${kernel_major}" -gt 5 ]] || [[ "${kernel_major}" -eq 5 && "${kernel_minor}" -ge 1 ]]; then
    kernel_tls="true"
  fi

  msg "  - Configuring outbound connection parameters"
  [[ "${kernel_tls}" == "true" ]] && msg "  - Kernel TLS offload enabled (kernel $(uname -r))"

  local updated_config=''
  if ! updated_config=$(echo "${config}" | jq \
    --arg tcp_keep_alive "${OUTBOUND_TCP_KEEP_ALIVE}" \
    --argjson kernel_tls "${kernel_tls}" \
    '.outbounds[0] += {
      "connect_timeout": "5s",
      "tcp_fast_open": true,
      "udp_fragment": true,
      "bind_address_no_port": true,
      "tcp_keep_alive": $tcp_keep_alive
    } + if $kernel_tls then {"kernel_tx": true} else {} end' \
    2> /dev/null); then
    warn "Failed to add outbound parameters, continuing with default configuration"
    echo "${config}"
    return 0
  fi

  success "  ✓ Outbound configuration applied"
  echo "${updated_config}"
}

#==============================================================================
# Configuration Generation Helpers
#==============================================================================

# Validate certificate/ACME configuration requirements
# Respects ENABLE_WS and ENABLE_HY2 environment variables
_validate_certificate_config() {
  local cert_fullchain="$1"
  local cert_key="$2"

  local cert_mode="${CERT_MODE:-}"
  local has_manual_certs="false"
  local has_acme="false"

  # Check manual certificate mode
  if [[ -n "${cert_fullchain}" && -n "${cert_key}" && -f "${cert_fullchain}" && -f "${cert_key}" ]]; then
    has_manual_certs="true"
    validate_cert_files "${cert_fullchain}" "${cert_key}" || die "Certificate validation failed"
  fi

  # Check ACME mode
  if [[ -n "${cert_mode}" && -n "${DOMAIN:-}" ]]; then
    has_acme="true"
    # Validate CF_API_TOKEN for DNS-01 mode
    if [[ "${cert_mode}" == "cf_dns" ]]; then
      [[ -n "${CF_API_TOKEN:-}" ]] || die "CF_API_TOKEN is required for CERT_MODE=cf_dns"
    fi
  fi

  # Skip if neither manual certs nor ACME
  if [[ "${has_manual_certs}" != "true" && "${has_acme}" != "true" ]]; then
    return 0
  fi

  # Validate domain is set
  [[ -n "${DOMAIN:-}" ]] || die "Domain is not set for certificate/ACME configuration."

  # Validate required variables based on enabled protocols
  local enable_ws="${ENABLE_WS:-1}"
  local enable_hy2="${ENABLE_HY2:-1}"

  if [[ "${enable_ws}" == "1" ]]; then
    [[ -n "${WS_PORT_CHOSEN:-}" ]] || die "WebSocket port is not set but ENABLE_WS=1."
  fi

  if [[ "${enable_hy2}" == "1" ]]; then
    [[ -n "${HY2_PORT_CHOSEN:-}" ]] || die "Hysteria2 port is not set but ENABLE_HY2=1."
    [[ -n "${HY2_PASS:-}" ]] || die "Hysteria2 password is not set but ENABLE_HY2=1."
  fi

  return 0
}

# Create all inbound configurations
# Respects ENABLE_REALITY, ENABLE_WS, ENABLE_HY2 environment variables
# Supports manual certificates (cert_fullchain/cert_key) and ACME modes
_create_all_inbounds() {
  local base_config="$1"
  local uuid="$2"
  local reality_port="$3"
  local listen_addr="$4"
  local sni="$5"
  local priv_key="$6"
  local short_id="$7"
  local cert_fullchain="${8:-}"
  local cert_key="${9:-}"

  # Check which protocols are enabled (default to 1 if not set)
  local enable_reality="${ENABLE_REALITY:-1}"
  local enable_ws="${ENABLE_WS:-1}"
  local enable_hy2="${ENABLE_HY2:-1}"

  # Add Reality inbound (if enabled and port is set)
  if [[ "${enable_reality}" == "1" && -n "${reality_port}" ]]; then
    local reality_config=''
    reality_config=$(create_reality_inbound "${uuid}" "${reality_port}" "${listen_addr}" \
      "${sni}" "${priv_key}" "${short_id}") \
      || die "Failed to create Reality inbound"

    base_config=$(echo "${base_config}" | jq --argjson reality "${reality_config}" \
      '.inbounds += [$reality]' 2> /dev/null) \
      || die "Failed to add Reality configuration to base config"
  fi

  # Determine TLS mode: manual certificates, ACME, or none
  local has_certs="false"
  local cert_mode="${CERT_MODE:-}"
  local tls_available="false"

  # Manual certificate mode: files provided and exist
  if [[ -n "${cert_fullchain}" && -n "${cert_key}" && -f "${cert_fullchain}" && -f "${cert_key}" ]]; then
    tls_available="true"
  # ACME mode: cert_mode is set and domain is available
  elif [[ -n "${cert_mode}" && -n "${DOMAIN:-}" ]]; then
    tls_available="true"
  fi

  if [[ "${tls_available}" == "true" ]]; then
    has_certs="true"

    # Add WS-TLS inbound (if enabled and port is set)
    if [[ "${enable_ws}" == "1" && -n "${WS_PORT_CHOSEN:-}" ]]; then
      local ws_tls=''
      ws_tls=$(_build_tls_block "${DOMAIN}" '["h2","http/1.1"]' \
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") \
        || die "Failed to build WS TLS configuration"

      local ws_config=''
      ws_config=$(create_ws_inbound "${uuid}" "${WS_PORT_CHOSEN}" "${listen_addr}" \
        "${DOMAIN}" "${ws_tls}") \
        || die "Failed to create WS-TLS inbound"

      base_config=$(echo "${base_config}" | jq --argjson ws "${ws_config}" \
        '.inbounds += [$ws]' 2> /dev/null) \
        || die "Failed to add WS-TLS configuration"
    fi

    # Add Hysteria2 inbound (if enabled and port is set)
    if [[ "${enable_hy2}" == "1" && -n "${HY2_PORT_CHOSEN:-}" ]]; then
      local hy2_tls=''
      hy2_tls=$(_build_tls_block "${DOMAIN}" '["h3"]' \
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") \
        || die "Failed to build Hysteria2 TLS configuration"

      local hy2_config=''
      hy2_config=$(create_hysteria2_inbound "${HY2_PASS}" "${HY2_PORT_CHOSEN}" "${listen_addr}" \
        "${hy2_tls}") \
        || die "Failed to create Hysteria2 inbound"

      base_config=$(echo "${base_config}" | jq --argjson hy2 "${hy2_config}" \
        '.inbounds += [$hy2]' 2> /dev/null) \
        || die "Failed to add Hysteria2 configuration"
    fi
  fi

  # Return updated config and has_certs flag
  echo "${has_certs}|${base_config}"
}

#==============================================================================
# Main Configuration Generation
#==============================================================================

# Generate complete sing-box configuration
write_config() {
  msg "Writing ${SB_CONF} ..."
  mkdir -p "${SB_CONF_DIR}"

  # Detect network stack support
  msg "Detecting network stack support..."
  local ipv6_supported=''
  ipv6_supported=$(detect_ipv6_support)

  local listen_addr=''
  listen_addr=$(choose_listen_address "${ipv6_supported}")

  if [[ "${ipv6_supported}" == "true" ]]; then
    success "  ✓ IPv6 support detected - using dual-stack listen with default DNS strategy"
  else
    warn "  ⚠ IPv6 not available - using dual-stack listen with IPv4-only DNS strategy"
  fi

  # Validate all required variables
  validate_config_vars || die "Configuration validation failed. Please check the errors above."

  # Validate certificate configuration if provided
  _validate_certificate_config "${CERT_FULLCHAIN:-}" "${CERT_KEY:-}"

  # Create temporary file for atomic write with secure permissions (600 automatic)
  local temp_conf=''
  temp_conf=$(create_temp_file "config") || die "Failed to create secure temporary file"

  # Setup automatic cleanup on function exit/error
  cleanup_write_config() {
    [[ -f "${temp_conf}" ]] && rm -f "${temp_conf}" 2> /dev/null || true
  }
  trap cleanup_write_config RETURN ERR EXIT INT TERM

  # Create base configuration
  local base_config=''
  base_config=$(create_base_config "${ipv6_supported}" "${LOG_LEVEL:-warn}") \
    || die "Failed to create base configuration"

  # Create all inbounds (Reality + optional WS-TLS and Hysteria2)
  local inbound_result='' has_certs=''
  # shellcheck disable=SC2154  # UUID, REALITY_PORT_CHOSEN, PRIV, SID set by caller
  inbound_result=$(_create_all_inbounds "${base_config}" "${UUID}" "${REALITY_PORT_CHOSEN}" \
    "${listen_addr}" "${SNI_DEFAULT:-www.microsoft.com}" "${PRIV}" "${SID}" \
    "${CERT_FULLCHAIN:-}" "${CERT_KEY:-}")
  has_certs="${inbound_result%%|*}"
  base_config="${inbound_result#*|}"

  # Add route and outbound configurations
  base_config=$(add_route_config "${base_config}" "${has_certs}") \
    || die "Failed to add route configuration"
  base_config=$(add_outbound_config "${base_config}")

  # Write configuration to temporary file
  echo "${base_config}" > "${temp_conf}" \
    || die "Failed to write configuration to temporary file"

  # Run comprehensive validation pipeline before applying
  if ! validate_config_pipeline "${temp_conf}"; then
    err "Configuration validation failed. See errors above."
    die "Generated configuration is invalid. This is a bug in the script."
  fi

  # Disable trap before successful move (we want to keep the file)
  trap - RETURN ERR EXIT INT TERM

  # Atomic move to final location
  if ! mv "${temp_conf}" "${SB_CONF}"; then
    # Re-enable trap for cleanup on failure
    trap cleanup_write_config RETURN
    die "Failed to move configuration to ${SB_CONF}"
  fi

  chmod 600 "${SB_CONF}"

  success "Configuration written and validated: ${SB_CONF}"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f validate_config_vars create_base_config create_reality_inbound
export -f create_ws_inbound create_hysteria2_inbound add_route_config
export -f add_outbound_config write_config
# Note: _validate_certificate_config and _create_all_inbounds are private helpers (not exported)
