#!/usr/bin/env bash
# lib/export.sh - Client configuration export functionality
# Part of sbx-lite modular architecture
#
# shellcheck disable=SC2154
# Reason: Variables (DOMAIN, UUID, PUBLIC_KEY, SHORT_ID, SNI, HY2_PASS, etc.)
# are loaded dynamically by load_client_info() at runtime

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_EXPORT_LOADED:-}" ]] && return 0
readonly _SBX_EXPORT_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"

# Emit structured export-domain failures when available, with die() fallback.
_export_die() {
  local code="$1"
  local reason="$2"
  local resolution="${3:-}"
  local example="${4:-}"

  if declare -f die_with_code > /dev/null 2>&1; then
    die_with_code "${code}" "${reason}" "${resolution}" "${example}"
  fi

  die "${reason}"
}

#==============================================================================
# Configuration Loading
#==============================================================================

# Load client info from saved configuration with strict validation
load_client_info() {
  local client_info_file='' state_file='' resolved='' owner='' perm='' invalid_line=''
  local allowed_keys_regex="^(DOMAIN|UUID|PUBLIC_KEY|SHORT_ID|SNI|REALITY_PORT|WS_PORT|HY2_PORT|HY2_PASS|CERT_FULLCHAIN|CERT_KEY)$"

  # Prefer structured state file when available, with compatibility fallback.
  state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR}/state.json}}"
  if [[ -f "${state_file}" ]]; then
    [[ ! -L "${state_file}" ]] || _export_die "SBX-EXPORT-001" "Refusing to load state from symlink: ${state_file}" \
      "Replace symlink with a real file owned by root and mode 600." \
      "install -m 600 /dev/null /etc/sing-box/state.json"
    resolved=$(readlink -f "${state_file}") || _export_die "SBX-EXPORT-002" "Failed to resolve state path: ${state_file}" \
      "Ensure state path exists and is readable."
    perm=$(stat -c '%a' "${resolved}" 2> /dev/null || stat -f '%Lp' "${resolved}" 2> /dev/null) || _export_die "SBX-EXPORT-003" "Unable to read state file permissions" \
      "Check file permissions and stat command availability."
    [[ "${perm}" == "600" ]] || _export_die "SBX-EXPORT-004" "State file permissions must be 600 (found ${perm})" \
      "Restrict state file permissions to owner read/write only." \
      "chmod 600 /etc/sing-box/state.json"
    [[ -s "${resolved}" ]] || _export_die "SBX-EXPORT-005" "State file is empty" \
      "Re-run install or restore state.json from backup."

    if [[ -z "${TEST_STATE_FILE:-}" ]]; then
      owner=$(stat -c '%u' "${resolved}" 2> /dev/null || stat -f '%u' "${resolved}" 2> /dev/null) || _export_die "SBX-EXPORT-006" "Unable to read state file ownership" \
        "Ensure stat command works and file metadata is accessible."
      [[ "${owner}" -eq 0 ]] || _export_die "SBX-EXPORT-007" "State file must be owned by root (uid 0)" \
        "Fix ownership to root:root." \
        "chown root:root /etc/sing-box/state.json"
    fi

    command -v jq > /dev/null 2>&1 || _export_die "SBX-EXPORT-008" "jq is required to parse state file" \
      "Install jq, then retry export commands." \
      "apt install -y jq"
    jq empty < "${resolved}" 2> /dev/null || _export_die "SBX-EXPORT-009" "State file is not valid JSON: ${resolved}" \
      "Repair or regenerate state.json."

    DOMAIN=$(jq -r '.server.domain // .server.ip // empty' "${resolved}")
    UUID=$(jq -r '.protocols.reality.uuid // empty' "${resolved}")
    PUBLIC_KEY=$(jq -r '.protocols.reality.public_key // empty' "${resolved}")
    SHORT_ID=$(jq -r '.protocols.reality.short_id // empty' "${resolved}")
    SNI=$(jq -r '.protocols.reality.sni // empty' "${resolved}")
    REALITY_PORT=$(jq -r '.protocols.reality.port // empty' "${resolved}")
    WS_PORT=$(jq -r '.protocols.ws_tls.port // empty' "${resolved}")
    HY2_PORT=$(jq -r '.protocols.hysteria2.port // empty' "${resolved}")
    HY2_PASS=$(jq -r '.protocols.hysteria2.password // empty' "${resolved}")
    CERT_FULLCHAIN=$(jq -r '.protocols.ws_tls.certificate // empty' "${resolved}")
    CERT_KEY=$(jq -r '.protocols.ws_tls.key // empty' "${resolved}")

    REALITY_PORT="${REALITY_PORT:-${REALITY_PORT_DEFAULT:-443}}"
    SNI="${SNI:-${SNI_DEFAULT:-www.microsoft.com}}"
    WS_PORT="${WS_PORT:-${WS_PORT_DEFAULT:-8444}}"
    HY2_PORT="${HY2_PORT:-${HY2_PORT_DEFAULT:-8443}}"
    return 0
  fi

  # Support test mode with alternative client info path
  client_info_file="${TEST_CLIENT_INFO:-${CLIENT_INFO}}"

  [[ -n "${client_info_file}" ]] || _export_die "SBX-EXPORT-020" "Client info path is empty" \
    "Set CLIENT_INFO correctly or regenerate install artifacts."
  [[ -f "${client_info_file}" ]] || _export_die "SBX-EXPORT-021" "Client info not found. Run: sbx info" \
    "Run install flow or regenerate client-info.txt."
  [[ ! -L "${client_info_file}" ]] || _export_die "SBX-EXPORT-022" "Refusing to load client info from symlink: ${client_info_file}" \
    "Replace symlink with a real file owned by root and mode 600."

  resolved=$(readlink -f "${client_info_file}") || _export_die "SBX-EXPORT-023" "Failed to resolve client info path: ${client_info_file}" \
    "Ensure path exists and is readable."
  # Cross-platform stat: Linux uses -c, BSD/macOS uses -f
  perm=$(stat -c '%a' "${resolved}" 2> /dev/null || stat -f '%Lp' "${resolved}" 2> /dev/null) || _export_die "SBX-EXPORT-024" "Unable to read client info permissions" \
    "Ensure stat command works and file metadata is accessible."
  [[ "${perm}" == "600" ]] || _export_die "SBX-EXPORT-025" "Client info permissions must be 600 (found ${perm})" \
    "Restrict client-info.txt to owner read/write only." \
    "chmod 600 /etc/sing-box/client-info.txt"
  [[ -s "${resolved}" ]] || _export_die "SBX-EXPORT-026" "Client info is empty" \
    "Re-run installer to regenerate client-info.txt."

  # In production mode, require root ownership for security
  # Skip this check in test mode (TEST_CLIENT_INFO set) to allow non-root CI
  if [[ -z "${TEST_CLIENT_INFO:-}" ]]; then
    # Cross-platform stat: Linux uses -c, BSD/macOS uses -f
    owner=$(stat -c '%u' "${resolved}" 2> /dev/null || stat -f '%u' "${resolved}" 2> /dev/null) || _export_die "SBX-EXPORT-027" "Unable to read client info ownership" \
      "Ensure stat command works and file metadata is accessible."
    [[ "${owner}" -eq 0 ]] || _export_die "SBX-EXPORT-028" "Client info must be owned by root (uid 0)" \
      "Fix ownership to root:root." \
      "chown root:root /etc/sing-box/client-info.txt"
  fi

  # Quick format validation before parsing
  # Accept both KEY="value" (quoted) and KEY=value (unquoted) formats
  invalid_line=$(grep -nEv '^[[:space:]]*(#.*)?$|^[A-Z0-9_]+=(\"[^\"]*\"|[^[:space:]]*)[[:space:]]*$' "${resolved}" | head -n1 || true)
  if [[ -n "${invalid_line}" ]]; then
    _export_die "SBX-EXPORT-029" "Invalid client info format at ${invalid_line%%:*}: ${invalid_line#*:}" \
      "Use KEY=value or KEY=\"value\" format only."
  fi

  # Parse key-value pairs safely
  local line='' key='' value=''
  declare -A client_info_map=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    # Match quoted format: KEY="value"
    if [[ "${line}" =~ ^([A-Z0-9_]+)=\"([^\"]*)\"[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
    # Match unquoted format: KEY=value
    elif [[ "${line}" =~ ^([A-Z0-9_]+)=([^[:space:]]*)[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
    else
      _export_die "SBX-EXPORT-030" "Invalid client info entry: ${line}" \
        "Use KEY=value or KEY=\"value\" format."
    fi

    [[ "${key}" =~ ${allowed_keys_regex} ]] || _export_die "SBX-EXPORT-031" "Unexpected key '${key}' in client info" \
      "Remove unsupported keys and keep only documented fields."
    { [[ "${value}" == *'$('* ]] || [[ "${value}" == *\`* ]]; } && _export_die "SBX-EXPORT-032" "Suspicious characters in value for ${key}" \
      "Remove command substitutions/backticks from values."

    client_info_map["${key}"]="${value}"
  done < "${resolved}"

  # Export parsed values into the environment
  for key in "${!client_info_map[@]}"; do
    printf -v "${key}" '%s' "${client_info_map[${key}]}"
  done

  # Set defaults for missing variables to ensure valid URIs
  REALITY_PORT="${REALITY_PORT:-${REALITY_PORT_DEFAULT:-443}}"
  SNI="${SNI:-${SNI_DEFAULT:-www.microsoft.com}}"
  WS_PORT="${WS_PORT:-${WS_PORT_DEFAULT:-8444}}"
  HY2_PORT="${HY2_PORT:-${HY2_PORT_DEFAULT:-8443}}"
}

#==============================================================================
# v2rayN/v2rayNG Configuration Export
#==============================================================================

# Generate v2rayN/v2rayNG JSON configuration
export_v2rayn_json() {
  local protocol="${1:-reality}"
  load_client_info

  local config=""
  case "${protocol}" in
    reality)
      config=$(
               cat << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 10808,
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${DOMAIN}",
        "port": ${REALITY_PORT},
        "users": [{
          "id": "${UUID}",
          "encryption": "none",
          "flow": "xtls-rprx-vision"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${SNI}",
        "publicKey": "${PUBLIC_KEY}",
        "shortId": "${SHORT_ID}",
        "fingerprint": "${REALITY_FINGERPRINT_DEFAULT}"
      }
    }
  }]
}
EOF
      )
      ;;
    ws)
      [[ -n "${WS_PORT}" ]] || _export_die "SBX-EXPORT-040" "WS-TLS not configured" \
        "Enable WS during install or export Reality only."
      config=$(
               cat << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 10808,
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${DOMAIN}",
        "port": ${WS_PORT},
        "users": [{
          "id": "${UUID}",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "wsSettings": {
        "path": "/ws",
        "headers": { "Host": "${DOMAIN}" }
      },
      "tlsSettings": {
        "serverName": "${DOMAIN}",
        "fingerprint": "${REALITY_FINGERPRINT_DEFAULT}"
      }
    }
  }]
}
EOF
      )
      ;;
    *)
      _export_die "SBX-EXPORT-041" "Invalid protocol: ${protocol}" \
        "Use one of: reality, ws."
      ;;
  esac

  echo "${config}"
}

#==============================================================================
# Clash/Clash Meta Configuration Export
#==============================================================================

# Generate Clash/Clash Meta YAML configuration
export_clash_yaml() {
  load_client_info

  cat << EOF
proxies:
  - name: "sbx-reality-${DOMAIN}"
    type: vless
    server: ${DOMAIN}
    port: ${REALITY_PORT}
    uuid: ${UUID}
    flow: ${REALITY_FLOW_VISION}
    network: tcp
    tls: true
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    client-fingerprint: ${REALITY_FINGERPRINT_DEFAULT}
    servername: ${SNI}
EOF

  if [[ -n "${WS_PORT}" && -n "${CERT_FULLCHAIN}" ]]; then
    cat << EOF

  - name: "sbx-ws-${DOMAIN}"
    type: vless
    server: ${DOMAIN}
    port: ${WS_PORT}
    uuid: ${UUID}
    tls: true
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: ${DOMAIN}
    servername: ${DOMAIN}
    client-fingerprint: ${REALITY_FINGERPRINT_DEFAULT}

  - name: "sbx-hysteria2-${DOMAIN}"
    type: hysteria2
    server: ${DOMAIN}
    port: ${HY2_PORT}
    password: ${HY2_PASS}
    sni: ${DOMAIN}
    skip-cert-verify: false
EOF
  fi

  cat << EOF

proxy-groups:
  - name: "sbx-lite"
    type: select
    proxies:
      - "sbx-reality-${DOMAIN}"
EOF

  if [[ -n "${WS_PORT}" ]]; then
    cat << EOF
      - "sbx-ws-${DOMAIN}"
      - "sbx-hysteria2-${DOMAIN}"
EOF
  fi
}

#==============================================================================
# URI Export
#==============================================================================

# Export configuration as share URIs
export_uri() {
  local protocol="${1:-all}"
  load_client_info

  case "${protocol}" in
    reality)
      echo "vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=${REALITY_FLOW_VISION}&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&fp=${REALITY_FINGERPRINT_DEFAULT}#Reality-${DOMAIN}"
      ;;
    ws)
      [[ -n "${WS_PORT}" ]] || _export_die "SBX-EXPORT-040" "WS-TLS not configured" \
        "Enable WS during install or export Reality only."
      echo "vless://${UUID}@${DOMAIN}:${WS_PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=${REALITY_FINGERPRINT_DEFAULT}#WS-TLS-${DOMAIN}"
      ;;
    hysteria2 | hy2)
      [[ -n "${HY2_PORT}" ]] || _export_die "SBX-EXPORT-042" "Hysteria2 not configured" \
        "Enable Hysteria2 during install or export Reality only."
      echo "hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
      ;;
    all)
      export_uri reality
      [[ -n "${WS_PORT}" ]] && export_uri ws
      [[ -n "${HY2_PORT}" ]] && export_uri hy2
      ;;
    *)
      _export_die "SBX-EXPORT-043" "Invalid protocol: ${protocol} (use: reality, ws, hy2, all)" \
        "Use one of: reality, ws, hy2, all."
      ;;
  esac
}

#==============================================================================
# QR Code Export
#==============================================================================

# Generate QR codes for configuration
export_qr_codes() {
  local output_dir="${1:-./qr-codes}"
  local reality_uri='' ws_uri='' hy2_uri=''
  load_client_info

  command -v qrencode > /dev/null || _export_die "SBX-EXPORT-044" "qrencode not installed." \
    "Install qrencode then retry QR export." \
    "apt install -y qrencode"

  mkdir -p "${output_dir}"

  # Reality QR
  reality_uri=$(export_uri reality)
  qrencode -t PNG -o "${output_dir}/reality-qr.png" "${reality_uri}"
  qrencode -t UTF8 -o "${output_dir}/reality-qr.txt" "${reality_uri}"
  success "  ✓ Reality QR code: ${output_dir}/reality-qr.png"

  if [[ -n "${WS_PORT}" ]]; then
    # WS-TLS QR
    ws_uri=$(export_uri ws)
    qrencode -t PNG -o "${output_dir}/ws-qr.png" "${ws_uri}"
    success "  ✓ WS-TLS QR code: ${output_dir}/ws-qr.png"

    # Hysteria2 QR
    hy2_uri=$(export_uri hy2)
    qrencode -t PNG -o "${output_dir}/hy2-qr.png" "${hy2_uri}"
    success "  ✓ Hysteria2 QR code: ${output_dir}/hy2-qr.png"
  fi

  info "QR codes saved to: ${output_dir}"
}

#==============================================================================
# Subscription Link Export
#==============================================================================

# Generate subscription link (Base64 encoded URIs)
export_subscription() {
  local output_file="${1:-/var/www/html/sub.txt}"
  local subscription='' sub_url=''
  load_client_info

  local uris=""

  # Reality URI
  uris+=$(export_uri reality)

  if [[ -n "${WS_PORT}" ]]; then
    uris+=$'\n'$(export_uri ws)
    uris+=$'\n'$(export_uri hy2)
  fi

  # Base64 encode
  subscription=$(echo -n "${uris}" | base64 -w 0)

  # Save to file
  mkdir -p "$(dirname "${output_file}")"
  echo "${subscription}" > "${output_file}"
  chmod 644 "${output_file}"

  success "Subscription link generated: ${output_file}"

  # Display access URL if web server detected
  if systemctl is-active nginx > /dev/null 2>&1 || systemctl is-active apache2 > /dev/null 2>&1; then
    sub_url="http://${DOMAIN}/$(basename "${output_file}")"
    info "Subscription URL: ${sub_url}"
  fi
}

#==============================================================================
# Main Export Dispatcher
#==============================================================================

# Main export function
export_config() {
  local client="${1:-}"
  local protocol="${2:-reality}"
  local output_file="${3:-}"
  local config=''

  case "${client}" in
    v2rayn | v2rayng)
      config=$(export_v2rayn_json "${protocol}")
      ;;
    clash | clash-meta)
      config=$(export_clash_yaml)
      ;;
    uri)
      config=$(export_uri "${protocol}")
      ;;
    subscription | sub)
      export_subscription "${output_file}"
      return 0
      ;;
    qr)
      export_qr_codes "${output_file}"
      return 0
      ;;
    *)
      _export_die "SBX-EXPORT-045" "Unsupported client: ${client}. Use: v2rayn, clash, uri, subscription, qr" \
        "Use one of the supported export targets."
      ;;
  esac

  # Output to file or stdout
  if [[ -n "${output_file}" ]]; then
    echo "${config}" > "${output_file}"
    success "Configuration exported to: ${output_file}"
  else
    echo "${config}"
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f load_client_info export_v2rayn_json export_clash_yaml
export -f export_uri export_qr_codes export_subscription export_config
