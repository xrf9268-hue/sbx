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

# Emit structured configuration failures when available.
_config_die() {
  local code="$1"
  local reason="$2"
  local resolution="${3:-}"
  local example="${4:-}"

  if declare -f die_with_code >/dev/null 2>&1; then
    die_with_code "${code}" "${reason}" "${resolution}" "${example}"
  fi

  die "${reason}"
}

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
    }' 2>/dev/null); then
    err "Failed to create base configuration with jq"
    return 1
  fi

  echo "${base_config}"
}

#==============================================================================
# Inbound Configuration Generation
#==============================================================================

# Create Reality inbound configuration
#
# Args:
#   users_json  JSON array of user objects [{uuid, ...}, ...]. A plain UUID
#               string is also accepted for backward compatibility and will be
#               wrapped in a single-element array automatically.
#   port        TCP port number
#   listen_addr Listen address
#   sni         SNI / handshake server
#   priv_key    X25519 private key
#   short_id    Reality short ID (1-8 hex chars)
create_reality_inbound() {
  local users_json="$1"
  local port="$2"
  local listen_addr="$3"
  local sni="$4"
  local priv_key="$5"
  local short_id="$6"

  # Backward compat: if a plain UUID string is passed, wrap it in an array
  if [[ "${users_json}" != "["* ]]; then
    local _plain_uuid="${users_json}"
    [[ -n "${_plain_uuid}" ]] || {
      format_validation_error_with_example "UUID" "(empty)" \
        "a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
        "UUID cannot be empty" \
        "Generate: sing-box generate uuid OR uuidgen"
      return 1
    }
    users_json=$(jq -n --arg uuid "${_plain_uuid}" '[{uuid: $uuid}]')
  fi

  # Validate users array is non-empty
  local users_count=0
  users_count=$(echo "${users_json}" | jq 'length' 2>/dev/null || echo 0)
  if [[ "${users_count}" -eq 0 ]]; then
    err "users_json must contain at least one user"
    return 1
  fi

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
  if ! validate_port "${port}" 2>/dev/null; then
    err "Invalid port: ${port} (must be 1-65535)"
    return 1
  fi

  # Validate transport+security+flow pairing
  if ! validate_transport_security_pairing "tcp" "reality" "${REALITY_FLOW_VISION}" 2>/dev/null; then
    err "Invalid transport+security+flow combination for Reality"
    return 1
  fi

  # Build sing-box users array: keep only uuid + flow fields
  local sb_users=''
  sb_users=$(echo "${users_json}" | jq --arg flow "${REALITY_FLOW_VISION}" \
    '[.[] | {uuid: .uuid, flow: $flow}]') || {
    err "Failed to build Reality users array from input"
    return 1
  }

  local reality_config=''

  msg "  - Creating Reality inbound configuration..."

  if ! reality_config=$(jq -n \
    --argjson users "${sb_users}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --arg sni "${sni}" \
    --arg priv "${priv_key}" \
    --arg sid "${short_id}" \
    --arg max_time_diff "${REALITY_MAX_TIME_DIFF}" \
    --arg alpn_h2 "${REALITY_ALPN_H2}" \
    --arg alpn_http11 "${REALITY_ALPN_HTTP11}" \
    --argjson handshake_port "${REALITY_DEFAULT_HANDSHAKE_PORT}" \
    '{
      type: "vless",
      tag: "in-reality",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: $users,
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
      }' 2>/dev/null); then
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
        }' 2>/dev/null); then
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
        }' 2>/dev/null); then
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
      acme: $acme
    }' 2>/dev/null); then
    err "Failed to build ACME TLS block"
    return 1
  fi

  echo "${tls_block}"
}

# Create WS-TLS inbound configuration
#
# Args:
#   users_json  JSON array of user objects [{uuid, ...}, ...]. A plain UUID
#               string is also accepted for backward compatibility.
#   port        TCP port number
#   listen_addr Listen address
#   domain      Server domain (unused in config body but kept for signature compat)
#   tls_json    TLS configuration JSON object
create_ws_inbound() {
  local users_json="$1"
  local port="$2"
  local listen_addr="$3"
  local domain="$4"
  local tls_json="$5"

  # Backward compat: if a plain UUID string is passed, wrap it in an array
  if [[ "${users_json}" != "["* ]]; then
    local _plain_uuid="${users_json}"
    users_json=$(jq -n --arg uuid "${_plain_uuid}" '[{uuid: $uuid}]')
  fi

  # Build sing-box users array (uuid only, no flow for WS-TLS)
  local sb_users=''
  sb_users=$(echo "${users_json}" | jq '[.[] | {uuid: .uuid}]') || {
    err "Failed to build WS-TLS users array from input"
    return 1
  }

  local ws_config=''

  if ! ws_config=$(jq -n \
    --argjson users "${sb_users}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --argjson tls "${tls_json}" \
    '{
      type: "vless",
      tag: "in-ws",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: $users,
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
    }' 2>/dev/null); then
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
    }' 2>/dev/null); then
    err "Failed to create Hysteria2 configuration with jq"
    return 1
  fi

  echo "${hy2_config}"
}

# Create TUIC V5 inbound configuration
# Args: uuid password port listen_addr tls_json
create_tuic_inbound() {
  local uuid="$1"
  local password="$2"
  local port="$3"
  local listen_addr="$4"
  local tls_json="$5"

  local tuic_config=''

  if ! tuic_config=$(jq -n \
    --arg uuid "${uuid}" \
    --arg password "${password}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --argjson tls "${tls_json}" \
    '{
      type: "tuic",
      tag: "in-tuic",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid, password: $password }],
      congestion_control: "bbr",
      zero_rtt_handshake: false,
      heartbeat: "10s",
      tls: $tls
    }' 2>/dev/null); then
    err "Failed to create TUIC V5 configuration with jq"
    return 1
  fi

  echo "${tuic_config}"
}

# Create Trojan inbound configuration
# Args: password port listen_addr tls_json
create_trojan_inbound() {
  local password="$1"
  local port="$2"
  local listen_addr="$3"
  local tls_json="$4"

  local trojan_config=''

  if ! trojan_config=$(jq -n \
    --arg password "${password}" \
    --arg port "${port}" \
    --arg listen_addr "${listen_addr}" \
    --argjson tls "${tls_json}" \
    '{
      type: "trojan",
      tag: "in-trojan",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ password: $password }],
      tls: $tls
    }' 2>/dev/null); then
    err "Failed to create Trojan configuration with jq"
    return 1
  fi

  echo "${trojan_config}"
}

#==============================================================================
# Route Configuration
#==============================================================================

# Add route configuration for sing-box 1.13.0+ compatibility
# Args: config inbounds_json
#   inbounds_json: JSON array of inbound tags to include in sniff rule
add_route_config() {
  local config="$1"
  local route_inbounds="${2:-[\"in-reality\"]}"

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
  }' 2>/dev/null); then
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

  msg "  - Configuring outbound connection parameters"

  local updated_config=''
  if ! updated_config=$(echo "${config}" | jq \
    --arg tcp_keep_alive "${OUTBOUND_TCP_KEEP_ALIVE}" \
    '.outbounds[0] += {
      "connect_timeout": "5s",
      "tcp_fast_open": true,
      "udp_fragment": true,
      "bind_address_no_port": true,
      "tcp_keep_alive": $tcp_keep_alive
    }' \
    2>/dev/null); then
    warn "Failed to add outbound parameters, continuing with default configuration"
    echo "${config}"
    return 0
  fi

  success "  ✓ Outbound configuration applied"
  echo "${updated_config}"
}

# Inject the experimental.clash_api block into the generated config based on
# the top-level .stats object in state.json. No-op when stats are disabled,
# state.json is unavailable, or no secret has been provisioned. The Clash API
# exposes traffic/connection metrics consumed by `sbx stats` and third-party
# Web UIs; the listener is bound to loopback with a Bearer token.
add_experimental_config() {
  local config="$1"
  local state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"

  # Stats require jq; silently skip when unavailable.
  if ! command -v jq >/dev/null 2>&1; then
    echo "${config}"
    return 0
  fi

  # state.json might not exist yet on very first config write — leave it alone.
  if [[ ! -f "${state_file}" ]]; then
    echo "${config}"
    return 0
  fi

  local enabled='false' bind='127.0.0.1' port='9090' secret=''
  {
    IFS=$'\t' read -r enabled bind port secret
  } < <(jq -r '[
      (.stats.enabled // false),
      (.stats.bind    // "127.0.0.1"),
      (.stats.port    // 9090),
      (.stats.secret  // "")
    ] | @tsv' "${state_file}" 2>/dev/null || echo $'false\t127.0.0.1\t9090\t')

  if [[ "${enabled}" != "true" || -z "${secret}" ]]; then
    echo "${config}"
    return 0
  fi

  msg "  - Enabling Clash API for traffic statistics"

  local updated_config=''
  if ! updated_config=$(echo "${config}" | jq \
    --arg ec "${bind}:${port}" \
    --arg secret "${secret}" \
    '.experimental = ((.experimental // {}) + {
        clash_api: {
          external_controller: $ec,
          secret: $secret,
          default_mode: "rule"
        }
      })' 2>/dev/null); then
    warn "Failed to inject experimental.clash_api; continuing without stats API"
    echo "${config}"
    return 0
  fi

  success "  ✓ Clash API bound to ${bind}:${port} (loopback only)"
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
    validate_cert_files "${cert_fullchain}" "${cert_key}" ||
      die_with_code "SBX-CERT-002" "Certificate file validation failed." \
        "Ensure fullchain/key paths are correct, readable, and matching." \
        "openssl x509 -in ${cert_fullchain} -noout -text | head"
  fi

  # Check ACME mode
  if [[ -n "${cert_mode}" && -n "${DOMAIN:-}" ]]; then
    has_acme="true"
    # Validate CF_API_TOKEN for DNS-01 mode
    if [[ "${cert_mode}" == "cf_dns" ]]; then
      [[ -n "${CF_API_TOKEN:-}" ]] ||
        die_with_code "SBX-CERT-001" "CF_API_TOKEN is required for CERT_MODE=cf_dns." \
          "Provide a valid Cloudflare API token with DNS edit permission." \
          "CERT_MODE=cf_dns CF_API_TOKEN=xxxx DOMAIN=example.com bash install.sh"
    fi
  fi

  # Skip if neither manual certs nor ACME
  if [[ "${has_manual_certs}" != "true" && "${has_acme}" != "true" ]]; then
    return 0
  fi

  # Validate domain is set
  [[ -n "${DOMAIN:-}" ]] ||
    die_with_code "SBX-CERT-003" "Domain is not set for certificate/ACME configuration." \
      "Set DOMAIN when using manual certificates or ACME certificate mode." \
      "DOMAIN=example.com bash install.sh"

  # Validate required variables based on enabled protocols
  local enable_ws="${ENABLE_WS:-1}"
  local enable_hy2="${ENABLE_HY2:-1}"
  local enable_tuic="${ENABLE_TUIC:-0}"
  local enable_trojan="${ENABLE_TROJAN:-0}"

  if [[ "${enable_ws}" == "1" ]]; then
    [[ -n "${WS_PORT_CHOSEN:-}" ]] ||
      die_with_code "SBX-CONFIG-010" "WS port is missing while ENABLE_WS=1." \
        "Set WS_PORT or keep automatic port allocation enabled." \
        "WS_PORT=8444 bash install.sh"
  fi

  if [[ "${enable_hy2}" == "1" ]]; then
    [[ -n "${HY2_PORT_CHOSEN:-}" ]] ||
      die_with_code "SBX-CONFIG-011" "Hysteria2 port is missing while ENABLE_HY2=1." \
        "Set HY2_PORT or keep automatic port allocation enabled." \
        "HY2_PORT=8443 bash install.sh"
    [[ -n "${HY2_PASS:-}" ]] ||
      die_with_code "SBX-CONFIG-012" "Hysteria2 password is missing while ENABLE_HY2=1." \
        "Ensure HY2_PASS is generated or provided before config generation." \
        "HY2_PASS=$(openssl rand -hex 16) bash install.sh"
  fi

  if [[ "${enable_tuic}" == "1" ]]; then
    [[ -n "${TUIC_PORT_CHOSEN:-}" ]] ||
      die_with_code "SBX-CONFIG-013" "TUIC port is missing while ENABLE_TUIC=1." \
        "Set TUIC_PORT or keep automatic port allocation enabled." \
        "TUIC_PORT=8445 bash install.sh"
    [[ -n "${TUIC_PASS:-}" ]] ||
      die_with_code "SBX-CONFIG-014" "TUIC password is missing while ENABLE_TUIC=1." \
        "Ensure TUIC_PASS is generated or provided before config generation." \
        "TUIC_PASS=\$(openssl rand -hex 16) bash install.sh"
  fi

  if [[ "${enable_trojan}" == "1" ]]; then
    [[ -n "${TROJAN_PORT_CHOSEN:-}" ]] ||
      die_with_code "SBX-CONFIG-015" "Trojan port is missing while ENABLE_TROJAN=1." \
        "Set TROJAN_PORT or keep automatic port allocation enabled." \
        "TROJAN_PORT=8446 bash install.sh"
    [[ -n "${TROJAN_PASS:-}" ]] ||
      die_with_code "SBX-CONFIG-016" "Trojan password is missing while ENABLE_TROJAN=1." \
        "Ensure TROJAN_PASS is generated or provided before config generation." \
        "TROJAN_PASS=\$(openssl rand -hex 16) bash install.sh"
  fi

  return 0
}

# Create all inbound configurations
# Respects ENABLE_REALITY, ENABLE_WS, ENABLE_HY2, ENABLE_TUIC, ENABLE_TROJAN environment variables
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

  # Check which protocols are enabled
  local enable_reality="${ENABLE_REALITY:-1}"
  local enable_ws="${ENABLE_WS:-1}"
  local enable_hy2="${ENABLE_HY2:-1}"
  local enable_tuic="${ENABLE_TUIC:-0}"
  local enable_trojan="${ENABLE_TROJAN:-0}"

  # When Cloudflare Tunnel is active, the WebSocket VLESS inbound must bind
  # only to localhost so cloudflared is the only path reaching it from the
  # Internet. Reality / Hy2 / TUIC / Trojan(TCP) are NOT tunnel-compatible
  # (cloudflared only proxies HTTP/WS) and continue to bind dual-stack.
  local ws_listen_addr="${listen_addr}"
  if [[ "${TUNNEL_ENABLED:-0}" == "1" ]]; then
    ws_listen_addr="127.0.0.1"
  fi

  # Resolve users JSON: prefer USERS_JSON env var (multi-user), fall back to
  # wrapping the positional uuid argument in a single-element array.
  local users_json="${USERS_JSON:-}"
  if [[ -z "${users_json}" ]]; then
    users_json=$(jq -n --arg uuid "${uuid}" '[{uuid: $uuid}]')
  fi

  # Add Reality inbound (if enabled and port is set)
  if [[ "${enable_reality}" == "1" && -n "${reality_port}" ]]; then
    local reality_config=''
    reality_config=$(create_reality_inbound "${users_json}" "${reality_port}" "${listen_addr}" \
      "${sni}" "${priv_key}" "${short_id}") ||
      _config_die "SBX-CONFIG-030" "Failed to create Reality inbound" \
        "Check Reality parameters (UUID/ports/keys/SNI) and retry."

    base_config=$(echo "${base_config}" | jq --argjson reality "${reality_config}" \
      '.inbounds += [$reality]' 2>/dev/null) ||
      _config_die "SBX-CONFIG-031" "Failed to add Reality configuration to base config" \
        "Verify generated Reality JSON is valid."
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
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") ||
        _config_die "SBX-CONFIG-032" "Failed to build WS TLS configuration" \
          "Check certificate mode and TLS inputs."

      local ws_config=''
      ws_config=$(create_ws_inbound "${users_json}" "${WS_PORT_CHOSEN}" "${ws_listen_addr}" \
        "${DOMAIN}" "${ws_tls}") ||
        _config_die "SBX-CONFIG-033" "Failed to create WS-TLS inbound" \
          "Verify WS port/domain/TLS settings."

      base_config=$(echo "${base_config}" | jq --argjson ws "${ws_config}" \
        '.inbounds += [$ws]' 2>/dev/null) ||
        _config_die "SBX-CONFIG-034" "Failed to add WS-TLS configuration" \
          "Verify WS inbound JSON generation."
    fi

    # Add Hysteria2 inbound (if enabled and port is set)
    if [[ "${enable_hy2}" == "1" && -n "${HY2_PORT_CHOSEN:-}" ]]; then
      local hy2_tls=''
      hy2_tls=$(_build_tls_block "${DOMAIN}" '["h3"]' \
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") ||
        _config_die "SBX-CONFIG-035" "Failed to build Hysteria2 TLS configuration" \
          "Check certificate mode and TLS inputs."

      local hy2_config=''
      hy2_config=$(create_hysteria2_inbound "${HY2_PASS}" "${HY2_PORT_CHOSEN}" "${listen_addr}" \
        "${hy2_tls}") ||
        _config_die "SBX-CONFIG-036" "Failed to create Hysteria2 inbound" \
          "Verify Hysteria2 password/port/TLS settings."

      base_config=$(echo "${base_config}" | jq --argjson hy2 "${hy2_config}" \
        '.inbounds += [$hy2]' 2>/dev/null) ||
        _config_die "SBX-CONFIG-037" "Failed to add Hysteria2 configuration" \
          "Verify Hysteria2 inbound JSON generation."
    fi

    # Add TUIC V5 inbound (if enabled and port is set)
    if [[ "${enable_tuic}" == "1" && -n "${TUIC_PORT_CHOSEN:-}" ]]; then
      local tuic_tls=''
      tuic_tls=$(_build_tls_block "${DOMAIN}" '["h3"]' \
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") ||
        _config_die "SBX-CONFIG-050" "Failed to build TUIC TLS configuration" \
          "Check certificate mode and TLS inputs."

      local tuic_config=''
      tuic_config=$(create_tuic_inbound "${uuid}" "${TUIC_PASS}" "${TUIC_PORT_CHOSEN}" \
        "${listen_addr}" "${tuic_tls}") ||
        _config_die "SBX-CONFIG-051" "Failed to create TUIC inbound" \
          "Verify TUIC uuid/password/port/TLS settings."

      base_config=$(echo "${base_config}" | jq --argjson tuic "${tuic_config}" \
        '.inbounds += [$tuic]' 2>/dev/null) ||
        _config_die "SBX-CONFIG-052" "Failed to add TUIC configuration" \
          "Verify TUIC inbound JSON generation."
    fi

    # Add Trojan inbound (if enabled and port is set)
    if [[ "${enable_trojan}" == "1" && -n "${TROJAN_PORT_CHOSEN:-}" ]]; then
      local trojan_tls=''
      trojan_tls=$(_build_tls_block "${DOMAIN}" '["h2","http/1.1"]' \
        "${cert_fullchain}" "${cert_key}" "${cert_mode}" "${CF_API_TOKEN:-}") ||
        _config_die "SBX-CONFIG-053" "Failed to build Trojan TLS configuration" \
          "Check certificate mode and TLS inputs."

      local trojan_config=''
      trojan_config=$(create_trojan_inbound "${TROJAN_PASS}" "${TROJAN_PORT_CHOSEN}" \
        "${listen_addr}" "${trojan_tls}") ||
        _config_die "SBX-CONFIG-054" "Failed to create Trojan inbound" \
          "Verify Trojan password/port/TLS settings."

      base_config=$(echo "${base_config}" | jq --argjson trojan "${trojan_config}" \
        '.inbounds += [$trojan]' 2>/dev/null) ||
        _config_die "SBX-CONFIG-055" "Failed to add Trojan configuration" \
          "Verify Trojan inbound JSON generation."
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
  with_flock "${SBX_LOCK_TIMEOUT_SEC:-30}" _write_config_impl
}

_write_config_impl() {
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
  validate_config_vars || _config_die "SBX-CONFIG-038" "Configuration validation failed. Please check the errors above." \
    "Fix reported validation errors, then retry."

  # Validate certificate configuration if provided
  _validate_certificate_config "${CERT_FULLCHAIN:-}" "${CERT_KEY:-}"

  # Create temporary file for atomic write with secure permissions (600 automatic)
  local temp_conf=''
  temp_conf=$(create_temp_file "config") || _config_die "SBX-CONFIG-039" "Failed to create secure temporary file" \
    "Check filesystem permissions and free disk space."

  # Setup automatic cleanup on function exit/error
  cleanup_write_config() {
    [[ -f "${temp_conf}" ]] && rm -f "${temp_conf}" 2>/dev/null || true
  }
  trap cleanup_write_config RETURN ERR EXIT INT TERM

  # Create base configuration
  local base_config=''
  base_config=$(create_base_config "${ipv6_supported}" "${LOG_LEVEL:-warn}") ||
    _config_die "SBX-CONFIG-040" "Failed to create base configuration" \
      "Check jq availability and base config template logic."

  # Create all inbounds (Reality + optional WS-TLS and Hysteria2)
  local inbound_result='' has_certs=''
  # shellcheck disable=SC2154  # UUID, REALITY_PORT_CHOSEN, PRIV, SID set by caller
  inbound_result=$(_create_all_inbounds "${base_config}" "${UUID}" "${REALITY_PORT_CHOSEN}" \
    "${listen_addr}" "${SNI:-${SNI_DEFAULT:-www.microsoft.com}}" "${PRIV}" "${SID}" \
    "${CERT_FULLCHAIN:-}" "${CERT_KEY:-}")
  has_certs="${inbound_result%%|*}"
  base_config="${inbound_result#*|}"

  # Build route inbound tag list from actually-enabled inbound configurations
  local route_inbound_tags=()
  [[ "${ENABLE_REALITY:-1}" == "1" && -n "${REALITY_PORT_CHOSEN:-}" ]] &&
    route_inbound_tags+=("in-reality")
  if [[ "${has_certs}" == "true" ]]; then
    [[ "${ENABLE_WS:-1}" == "1" && -n "${WS_PORT_CHOSEN:-}" ]] &&
      route_inbound_tags+=("in-ws")
    [[ "${ENABLE_HY2:-1}" == "1" && -n "${HY2_PORT_CHOSEN:-}" ]] &&
      route_inbound_tags+=("in-hy2")
    [[ "${ENABLE_TUIC:-0}" == "1" && -n "${TUIC_PORT_CHOSEN:-}" ]] &&
      route_inbound_tags+=("in-tuic")
    [[ "${ENABLE_TROJAN:-0}" == "1" && -n "${TROJAN_PORT_CHOSEN:-}" ]] &&
      route_inbound_tags+=("in-trojan")
  fi
  local route_inbounds_json=''
  if [[ ${#route_inbound_tags[@]} -eq 0 ]]; then
    route_inbounds_json='[]'
  else
    route_inbounds_json=$(printf '%s\n' "${route_inbound_tags[@]}" | jq -R . | jq -sc .)
  fi

  # Add route and outbound configurations
  base_config=$(add_route_config "${base_config}" "${route_inbounds_json}") ||
    _config_die "SBX-CONFIG-041" "Failed to add route configuration" \
      "Verify route generation inputs and JSON integrity."
  base_config=$(add_outbound_config "${base_config}")

  # Inject experimental.clash_api (for `sbx stats`) if enabled in state.json
  base_config=$(add_experimental_config "${base_config}")

  # Write configuration to temporary file
  echo "${base_config}" >"${temp_conf}" ||
    _config_die "SBX-CONFIG-042" "Failed to write configuration to temporary file" \
      "Check filesystem writability for temporary directory."

  # Run comprehensive validation pipeline before applying
  if ! validate_config_pipeline "${temp_conf}"; then
    err "Configuration validation failed. See errors above."
    _config_die "SBX-CONFIG-043" "Generated configuration is invalid. This is a bug in the script." \
      "Collect logs and open an issue with your install parameters."
  fi

  # Disable trap before successful move (we want to keep the file)
  trap - RETURN ERR EXIT INT TERM

  # Atomic move to final location
  if ! mv "${temp_conf}" "${SB_CONF}"; then
    # Re-enable trap for cleanup on failure
    trap cleanup_write_config RETURN
    _config_die "SBX-CONFIG-044" "Failed to move configuration to ${SB_CONF}" \
      "Check permissions for ${SB_CONF_DIR} and filesystem health."
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
export -f create_tuic_inbound create_trojan_inbound
export -f add_outbound_config add_experimental_config write_config
# Note: _validate_certificate_config and _create_all_inbounds are private helpers (not exported)
