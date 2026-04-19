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

  if declare -f die_with_code >/dev/null 2>&1; then
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
  local reality_enabled_raw='' ws_enabled_raw='' hy2_enabled_raw='' tuic_enabled_raw='' trojan_enabled_raw=''
  local -a state_fields=()
  local allowed_keys_regex="^(DOMAIN|UUID|PUBLIC_KEY|SHORT_ID|SNI|REALITY_PORT|WS_PORT|HY2_PORT|HY2_PASS|TUIC_PORT|TUIC_PASS|TROJAN_PORT|TROJAN_PASS|CERT_FULLCHAIN|CERT_KEY|TUNNEL_ENABLED|TUNNEL_HOSTNAME|TUNNEL_MODE)$"

  # Prefer structured state file when available, with compatibility fallback.
  state_file="${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR}/state.json}}"
  if [[ -f "${state_file}" ]]; then
    [[ ! -L "${state_file}" ]] || _export_die "SBX-EXPORT-001" "Refusing to load state from symlink: ${state_file}" \
      "Replace symlink with a real file owned by root and mode 600." \
      "install -m 600 /dev/null /etc/sing-box/state.json"
    resolved=$(readlink -f "${state_file}") || _export_die "SBX-EXPORT-002" "Failed to resolve state path: ${state_file}" \
      "Ensure state path exists and is readable."
    perm=$(stat -c '%a' "${resolved}" 2>/dev/null || stat -f '%Lp' "${resolved}" 2>/dev/null) || _export_die "SBX-EXPORT-003" "Unable to read state file permissions" \
      "Check file permissions and stat command availability."
    case "${perm}" in
      600 | 640) ;;
      *)
        _export_die "SBX-EXPORT-004" "State file permissions must be 600 or 640 (found ${perm})" \
          "Restrict state file permissions to owner read/write, with optional group-read for subscription." \
          "chmod 600 /etc/sing-box/state.json"
        ;;
    esac
    [[ -s "${resolved}" ]] || _export_die "SBX-EXPORT-005" "State file is empty" \
      "Re-run install or restore state.json from backup."

    if [[ -z "${TEST_STATE_FILE:-}" ]]; then
      owner=$(stat -c '%u' "${resolved}" 2>/dev/null || stat -f '%u' "${resolved}" 2>/dev/null) || _export_die "SBX-EXPORT-006" "Unable to read state file ownership" \
        "Ensure stat command works and file metadata is accessible."
      [[ "${owner}" -eq 0 ]] || _export_die "SBX-EXPORT-007" "State file must be owned by root (uid 0)" \
        "Fix ownership to root:root." \
        "chown root:root /etc/sing-box/state.json"
    fi

    command -v jq >/dev/null 2>&1 || _export_die "SBX-EXPORT-008" "jq is required to parse state file" \
      "Install jq, then retry export commands." \
      "apt install -y jq"
    jq empty <"${resolved}" 2>/dev/null || _export_die "SBX-EXPORT-009" "State file is not valid JSON: ${resolved}" \
      "Repair or regenerate state.json."

    mapfile -d '' -t state_fields < <(
      jq -j '
        [
          (.server.domain // .server.ip // ""),
          (.protocols.reality.uuid // ""),
          (.protocols.reality.public_key // ""),
          (.protocols.reality.short_id // ""),
          (.protocols.reality.sni // ""),
          (.protocols.reality.port // "" | tostring),
          (.protocols.ws_tls.port // "" | tostring),
          (.protocols.hysteria2.port // "" | tostring),
          (.protocols.hysteria2.password // ""),
          (.protocols.hysteria2.port_range // ""),
          (.protocols.tuic.port // "" | tostring),
          (.protocols.tuic.password // ""),
          (.protocols.trojan.port // "" | tostring),
          (.protocols.trojan.password // ""),
          (.protocols.ws_tls.certificate // ""),
          (.protocols.ws_tls.key // ""),
          (.subscription.enabled // false | tostring),
          (.subscription.port // "" | tostring),
          (.subscription.bind // ""),
          (.subscription.token // ""),
          (.subscription.path // ""),
          (.tunnel.enabled // false | tostring),
          (.tunnel.hostname // ""),
          (.tunnel.mode // ""),
          (.protocols.reality.enabled | if . == null then "" else tostring end),
          (.protocols.ws_tls.enabled | if . == null then "" else tostring end),
          (.protocols.hysteria2.enabled | if . == null then "" else tostring end),
          (.protocols.tuic.enabled | if . == null then "" else tostring end),
          (.protocols.trojan.enabled | if . == null then "" else tostring end)
        ][]
        | tostring, "\u0000"
      ' "${resolved}"
    ) || _export_die "SBX-EXPORT-010" "Failed to extract client info from state file" \
      "Repair or regenerate state.json."

    [[ "${#state_fields[@]}" -eq 29 ]] || _export_die "SBX-EXPORT-011" "Unexpected state data shape while loading client info" \
      "Repair or regenerate state.json."

    DOMAIN="${state_fields[0]}"
    UUID="${state_fields[1]}"
    PUBLIC_KEY="${state_fields[2]}"
    SHORT_ID="${state_fields[3]}"
    SNI="${state_fields[4]}"
    REALITY_PORT="${state_fields[5]}"
    WS_PORT="${state_fields[6]}"
    HY2_PORT="${state_fields[7]}"
    HY2_PASS="${state_fields[8]}"
    HY2_PORT_RANGE="${state_fields[9]}"
    TUIC_PORT="${state_fields[10]}"
    TUIC_PASS="${state_fields[11]}"
    TROJAN_PORT="${state_fields[12]}"
    TROJAN_PASS="${state_fields[13]}"
    CERT_FULLCHAIN="${state_fields[14]}"
    CERT_KEY="${state_fields[15]}"
    SUB_ENABLED="${state_fields[16]}"
    SUB_PORT="${state_fields[17]}"
    SUB_BIND="${state_fields[18]}"
    SUB_TOKEN="${state_fields[19]}"
    SUB_PATH="${state_fields[20]}"
    TUNNEL_ENABLED="${state_fields[21]}"
    TUNNEL_HOSTNAME="${state_fields[22]}"
    TUNNEL_MODE="${state_fields[23]}"
    reality_enabled_raw="${state_fields[24]}"
    ws_enabled_raw="${state_fields[25]}"
    hy2_enabled_raw="${state_fields[26]}"
    tuic_enabled_raw="${state_fields[27]}"
    trojan_enabled_raw="${state_fields[28]}"

    case "${reality_enabled_raw}" in
      true | 1 | yes | on) REALITY_ENABLED="true" ;;
      false | 0 | no | off) REALITY_ENABLED="false" ;;
      *)
        [[ -n "${REALITY_PORT:-}" ]] && REALITY_ENABLED="true" || REALITY_ENABLED="false"
        ;;
    esac

    case "${ws_enabled_raw}" in
      true | 1 | yes | on) WS_ENABLED="true" ;;
      false | 0 | no | off) WS_ENABLED="false" ;;
      *)
        [[ -n "${WS_PORT:-}" ]] && WS_ENABLED="true" || WS_ENABLED="false"
        ;;
    esac

    case "${hy2_enabled_raw}" in
      true | 1 | yes | on) HY2_ENABLED="true" ;;
      false | 0 | no | off) HY2_ENABLED="false" ;;
      *)
        [[ -n "${HY2_PORT:-}" || -n "${HY2_PASS:-}" ]] && HY2_ENABLED="true" || HY2_ENABLED="false"
        ;;
    esac

    case "${tuic_enabled_raw}" in
      true | 1 | yes | on) TUIC_ENABLED="true" ;;
      false | 0 | no | off) TUIC_ENABLED="false" ;;
      *)
        [[ -n "${TUIC_PORT:-}" || -n "${TUIC_PASS:-}" ]] && TUIC_ENABLED="true" || TUIC_ENABLED="false"
        ;;
    esac

    case "${trojan_enabled_raw}" in
      true | 1 | yes | on) TROJAN_ENABLED="true" ;;
      false | 0 | no | off) TROJAN_ENABLED="false" ;;
      *)
        [[ -n "${TROJAN_PORT:-}" || -n "${TROJAN_PASS:-}" ]] && TROJAN_ENABLED="true" || TROJAN_ENABLED="false"
        ;;
    esac

    if [[ "${REALITY_ENABLED}" == "true" ]]; then
      REALITY_PORT="${REALITY_PORT:-${REALITY_PORT_DEFAULT:-443}}"
      SNI="${SNI:-${SNI_DEFAULT:-www.microsoft.com}}"
    else
      REALITY_PORT=''
    fi

    if [[ "${WS_ENABLED}" == "true" ]]; then
      WS_PORT="${WS_PORT:-${WS_PORT_DEFAULT:-8444}}"
    else
      WS_PORT=''
    fi

    if [[ "${HY2_ENABLED}" == "true" ]]; then
      HY2_PORT="${HY2_PORT:-${HY2_PORT_DEFAULT:-8443}}"
    else
      HY2_PORT=''
      HY2_PASS=''
      HY2_PORT_RANGE=''
    fi

    if [[ "${TUIC_ENABLED}" == "true" ]]; then
      TUIC_PORT="${TUIC_PORT:-${TUIC_PORT_DEFAULT:-8445}}"
    else
      TUIC_PORT=''
      TUIC_PASS=''
    fi

    if [[ "${TROJAN_ENABLED}" == "true" ]]; then
      TROJAN_PORT="${TROJAN_PORT:-${TROJAN_PORT_DEFAULT:-8446}}"
    else
      TROJAN_PORT=''
      TROJAN_PASS=''
    fi
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
  perm=$(stat -c '%a' "${resolved}" 2>/dev/null || stat -f '%Lp' "${resolved}" 2>/dev/null) || _export_die "SBX-EXPORT-024" "Unable to read client info permissions" \
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
    owner=$(stat -c '%u' "${resolved}" 2>/dev/null || stat -f '%u' "${resolved}" 2>/dev/null) || _export_die "SBX-EXPORT-027" "Unable to read client info ownership" \
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
  done <"${resolved}"

  # Export parsed values into the environment
  for key in "${!client_info_map[@]}"; do
    printf -v "${key}" '%s' "${client_info_map[${key}]}"
  done

  if [[ -n "${REALITY_PORT:-}" ]]; then
    REALITY_ENABLED="true"
  else
    REALITY_ENABLED="false"
  fi

  if [[ -n "${WS_PORT:-}" ]]; then
    WS_ENABLED="true"
  else
    WS_ENABLED="false"
  fi

  if [[ -n "${HY2_PORT:-}" || -n "${HY2_PASS:-}" ]]; then
    HY2_ENABLED="true"
  else
    HY2_ENABLED="false"
  fi

  if [[ -n "${TUIC_PORT:-}" || -n "${TUIC_PASS:-}" ]]; then
    TUIC_ENABLED="true"
  else
    TUIC_ENABLED="false"
  fi

  if [[ -n "${TROJAN_PORT:-}" || -n "${TROJAN_PASS:-}" ]]; then
    TROJAN_ENABLED="true"
  else
    TROJAN_ENABLED="false"
  fi

  if [[ "${REALITY_ENABLED}" == "true" ]]; then
    REALITY_PORT="${REALITY_PORT:-${REALITY_PORT_DEFAULT:-443}}"
    SNI="${SNI:-${SNI_DEFAULT:-www.microsoft.com}}"
  else
    REALITY_PORT=''
  fi

  if [[ "${WS_ENABLED}" == "true" ]]; then
    WS_PORT="${WS_PORT:-${WS_PORT_DEFAULT:-8444}}"
  else
    WS_PORT=''
  fi

  if [[ "${HY2_ENABLED}" == "true" ]]; then
    HY2_PORT="${HY2_PORT:-${HY2_PORT_DEFAULT:-8443}}"
  else
    HY2_PORT=''
    HY2_PASS=''
    HY2_PORT_RANGE=''
  fi

  if [[ "${TUIC_ENABLED}" == "true" ]]; then
    TUIC_PORT="${TUIC_PORT:-${TUIC_PORT_DEFAULT:-8445}}"
  else
    TUIC_PORT=''
    TUIC_PASS=''
  fi

  if [[ "${TROJAN_ENABLED}" == "true" ]]; then
    TROJAN_PORT="${TROJAN_PORT:-${TROJAN_PORT_DEFAULT:-8446}}"
  else
    TROJAN_PORT=''
    TROJAN_PASS=''
  fi
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
      [[ "${REALITY_ENABLED:-false}" == "true" && -n "${REALITY_PORT:-}" ]] || _export_die "SBX-EXPORT-039" "Reality not configured" \
        "Enable Reality during install or export another protocol."
      config=$(
        cat <<EOF
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
      [[ "${WS_ENABLED:-false}" == "true" && -n "${WS_PORT:-}" ]] || _export_die "SBX-EXPORT-040" "WS-TLS not configured" \
        "Enable WS during install or export Reality only."
      local ws_host="" ws_port=""
      ws_host=$(_effective_ws_host)
      ws_port=$(_effective_ws_port)
      config=$(
        cat <<EOF
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
        "address": "${ws_host}",
        "port": ${ws_port},
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
        "headers": { "Host": "${ws_host}" }
      },
      "tlsSettings": {
        "serverName": "${ws_host}",
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
  local ws_host='' ws_port='' proxy_name=''
  local -a proxy_names=()

  echo "proxies:"

  if [[ "${REALITY_ENABLED:-false}" == "true" && -n "${REALITY_PORT:-}" ]]; then
    cat <<EOF
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
    proxy_names+=("\"sbx-reality-${DOMAIN}\"")
  fi

  if [[ "${WS_ENABLED:-false}" == "true" && -n "${WS_PORT:-}" ]]; then
    ws_host=$(_effective_ws_host)
    ws_port=$(_effective_ws_port)
    cat <<EOF

  - name: "sbx-ws-${DOMAIN}"
    type: vless
    server: ${ws_host}
    port: ${ws_port}
    uuid: ${UUID}
    tls: true
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: ${ws_host}
    servername: ${ws_host}
    client-fingerprint: ${REALITY_FINGERPRINT_DEFAULT}
EOF
    proxy_names+=("\"sbx-ws-${DOMAIN}\"")
  fi

  if [[ "${HY2_ENABLED:-false}" == "true" && -n "${HY2_PORT:-}" && -n "${HY2_PASS:-}" ]]; then
    cat <<EOF

  - name: "sbx-hysteria2-${DOMAIN}"
    type: hysteria2
    server: ${DOMAIN}
    port: ${HY2_PORT}
    password: ${HY2_PASS}
    sni: ${DOMAIN}
    skip-cert-verify: false
EOF
    if [[ -n "${HY2_PORT_RANGE:-}" ]]; then
      cat <<EOF
    ports: ${HY2_PORT_RANGE}
EOF
    fi
    proxy_names+=("\"sbx-hysteria2-${DOMAIN}\"")
  fi

  if [[ "${TUIC_ENABLED:-false}" == "true" && -n "${TUIC_PORT:-}" && -n "${TUIC_PASS:-}" ]]; then
    cat <<EOF

  - name: "sbx-tuic-${DOMAIN}"
    type: tuic
    server: ${DOMAIN}
    port: ${TUIC_PORT}
    uuid: ${UUID}
    password: ${TUIC_PASS}
    congestion-controller: bbr
    alpn:
      - h3
    sni: ${DOMAIN}
    skip-cert-verify: false
EOF
    proxy_names+=("\"sbx-tuic-${DOMAIN}\"")
  fi

  if [[ "${TROJAN_ENABLED:-false}" == "true" && -n "${TROJAN_PORT:-}" && -n "${TROJAN_PASS:-}" ]]; then
    cat <<EOF

  - name: "sbx-trojan-${DOMAIN}"
    type: trojan
    server: ${DOMAIN}
    port: ${TROJAN_PORT}
    password: ${TROJAN_PASS}
    sni: ${DOMAIN}
    skip-cert-verify: false
    client-fingerprint: ${REALITY_FINGERPRINT_DEFAULT}
EOF
    proxy_names+=("\"sbx-trojan-${DOMAIN}\"")
  fi

  cat <<EOF

proxy-groups:
  - name: "sbx-lite"
    type: select
    proxies:
EOF

  for proxy_name in "${proxy_names[@]}"; do
    echo "      - ${proxy_name}"
  done
}

#==============================================================================
# URI Export
#==============================================================================

# Resolve the public host that WS/Trojan-WS clients should connect to.
# When Cloudflare Tunnel is active, traffic must hit the tunnel hostname on
# port 443 instead of the local WS_PORT.
_effective_ws_host() {
  if [[ "${TUNNEL_ENABLED:-false}" == "true" && -n "${TUNNEL_HOSTNAME:-}" ]]; then
    echo "${TUNNEL_HOSTNAME}"
  else
    echo "${DOMAIN}"
  fi
}

_effective_ws_port() {
  if [[ "${TUNNEL_ENABLED:-false}" == "true" && -n "${TUNNEL_HOSTNAME:-}" ]]; then
    echo "443"
  else
    echo "${WS_PORT}"
  fi
}

# Export configuration as share URIs
export_uri() {
  local protocol="${1:-all}"
  load_client_info

  local ws_host="" ws_port=""
  ws_host=$(_effective_ws_host)
  ws_port=$(_effective_ws_port)

  case "${protocol}" in
    reality)
      [[ "${REALITY_ENABLED:-false}" == "true" && -n "${REALITY_PORT:-}" ]] || _export_die "SBX-EXPORT-039" "Reality not configured" \
        "Enable Reality during install or export another protocol."
      echo "vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=${REALITY_FLOW_VISION}&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&fp=${REALITY_FINGERPRINT_DEFAULT}#Reality-${DOMAIN}"
      ;;
    ws)
      [[ "${WS_ENABLED:-false}" == "true" && -n "${WS_PORT:-}" ]] || _export_die "SBX-EXPORT-040" "WS-TLS not configured" \
        "Enable WS during install or export Reality only."
      echo "vless://${UUID}@${ws_host}:${ws_port}?encryption=none&security=tls&type=ws&host=${ws_host}&path=/ws&sni=${ws_host}&fp=${REALITY_FINGERPRINT_DEFAULT}#WS-TLS-${ws_host}"
      ;;
    hysteria2 | hy2)
      [[ "${HY2_ENABLED:-false}" == "true" && -n "${HY2_PORT:-}" && -n "${HY2_PASS:-}" ]] || _export_die "SBX-EXPORT-042" "Hysteria2 not configured" \
        "Enable Hysteria2 during install or export Reality only."
      local hy2_uri="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0"
      [[ -n "${HY2_PORT_RANGE:-}" ]] && hy2_uri+="&mport=${HY2_PORT_RANGE}"
      hy2_uri+="#Hysteria2-${DOMAIN}"
      echo "${hy2_uri}"
      ;;
    tuic)
      [[ -n "${TUIC_PORT:-}" && -n "${TUIC_PASS:-}" ]] || _export_die "SBX-EXPORT-046" "TUIC not configured" \
        "Enable TUIC during install or export another protocol."
      echo "tuic://${UUID}:${TUIC_PASS}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&alpn=h3&sni=${DOMAIN}&udp_relay_mode=native#TUIC-${DOMAIN}"
      ;;
    trojan)
      [[ -n "${TROJAN_PORT:-}" && -n "${TROJAN_PASS:-}" ]] || _export_die "SBX-EXPORT-047" "Trojan not configured" \
        "Enable Trojan during install or export another protocol."
      echo "trojan://${TROJAN_PASS}@${DOMAIN}:${TROJAN_PORT}?sni=${DOMAIN}&security=tls&type=tcp&fp=${REALITY_FINGERPRINT_DEFAULT}#Trojan-${DOMAIN}"
      ;;
    all)
      if [[ "${REALITY_ENABLED:-false}" == "true" ]]; then
        export_uri reality
      fi
      if [[ "${WS_ENABLED:-false}" == "true" ]]; then
        export_uri ws
      fi
      if [[ "${HY2_ENABLED:-false}" == "true" ]]; then
        export_uri hy2
      fi
      if [[ "${TUIC_ENABLED:-false}" == "true" ]]; then
        export_uri tuic
      fi
      if [[ "${TROJAN_ENABLED:-false}" == "true" ]]; then
        export_uri trojan
      fi
      ;;
    *)
      _export_die "SBX-EXPORT-043" "Invalid protocol: ${protocol} (use: reality, ws, hy2, tuic, trojan, all)" \
        "Use one of: reality, ws, hy2, tuic, trojan, all."
      ;;
  esac
}

#==============================================================================
# QR Code Export
#==============================================================================

# Generate QR codes for configuration
export_qr_codes() {
  local output_dir="${1:-./qr-codes}"
  local reality_uri='' ws_uri='' hy2_uri='' tuic_uri='' trojan_uri=''
  load_client_info

  command -v qrencode >/dev/null || _export_die "SBX-EXPORT-044" "qrencode not installed." \
    "Install qrencode then retry QR export." \
    "apt install -y qrencode"

  mkdir -p "${output_dir}"

  if [[ "${REALITY_ENABLED:-false}" == "true" ]]; then
    reality_uri=$(export_uri reality)
    qrencode -t PNG -o "${output_dir}/reality-qr.png" "${reality_uri}"
    qrencode -t UTF8 -o "${output_dir}/reality-qr.txt" "${reality_uri}"
    success "  ✓ Reality QR code: ${output_dir}/reality-qr.png"
  fi

  if [[ "${WS_ENABLED:-false}" == "true" ]]; then
    ws_uri=$(export_uri ws)
    qrencode -t PNG -o "${output_dir}/ws-qr.png" "${ws_uri}"
    success "  ✓ WS-TLS QR code: ${output_dir}/ws-qr.png"
  fi

  if [[ "${HY2_ENABLED:-false}" == "true" ]]; then
    hy2_uri=$(export_uri hy2)
    qrencode -t PNG -o "${output_dir}/hy2-qr.png" "${hy2_uri}"
    success "  ✓ Hysteria2 QR code: ${output_dir}/hy2-qr.png"
  fi

  if [[ "${TUIC_ENABLED:-false}" == "true" ]]; then
    tuic_uri=$(export_uri tuic)
    qrencode -t PNG -o "${output_dir}/tuic-qr.png" "${tuic_uri}"
    success "  ✓ TUIC QR code: ${output_dir}/tuic-qr.png"
  fi

  if [[ "${TROJAN_ENABLED:-false}" == "true" ]]; then
    trojan_uri=$(export_uri trojan)
    qrencode -t PNG -o "${output_dir}/trojan-qr.png" "${trojan_uri}"
    success "  ✓ Trojan QR code: ${output_dir}/trojan-qr.png"
  fi

  info "QR codes saved to: ${output_dir}"
}

#==============================================================================
# Subscription Link Export
#==============================================================================

# Generate subscription link (Base64 encoded URIs)
export_subscription() {
  local output_file="${1:-/var/www/html/sub.txt}"
  local subscription='' sub_url='' uris=''
  load_client_info

  uris=$(export_uri all)

  # Base64 encode
  subscription=$(echo -n "${uris}" | base64 -w 0)

  # Save to file
  mkdir -p "$(dirname "${output_file}")"
  echo "${subscription}" >"${output_file}"
  chmod 644 "${output_file}"

  success "Subscription link generated: ${output_file}"

  # Display access URL if web server detected
  if systemctl is-active nginx >/dev/null 2>&1 || systemctl is-active apache2 >/dev/null 2>&1; then
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
    echo "${config}" >"${output_file}"
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
