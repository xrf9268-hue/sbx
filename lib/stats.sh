#!/usr/bin/env bash
# lib/stats.sh - Traffic statistics via sing-box Clash API
# Part of sbx-lite modular architecture
#
# Clash API listens on 127.0.0.1 only; every call carries a Bearer token
# stored in state.json (mode 600). Secret is generated once per install.
# State shape: .stats = {enabled, bind, port, secret}.

set -euo pipefail

[[ -n "${_SBX_STATS_LOADED:-}" ]] && return 0
readonly _SBX_STATS_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/generators.sh"

#==============================================================================
# Defaults & helpers
#==============================================================================

: "${SBX_STATS_BIND_DEFAULT:=127.0.0.1}"
: "${SBX_STATS_PORT_DEFAULT:=9090}"
: "${SBX_STATS_CURL_TIMEOUT:=3}"

_stats_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"
}

_stats_state_get() {
  local key="$1"
  local state_file=''
  state_file=$(_stats_state_file)
  [[ -f "${state_file}" ]] || {
    echo ""
    return 0
  }
  have jq || {
    echo ""
    return 0
  }
  jq -r --arg k "${key}" '.stats[$k] // empty' "${state_file}" 2>/dev/null || echo ""
}

_stats_enabled() {
  local v=''
  v=$(_stats_state_get enabled)
  [[ "${v}" == "true" ]]
}

# Emit the standard "stats disabled" notice and return 0. Used by every
# *_pretty command so operators get a consistent hint.
_stats_disabled_notice() {
  echo -e "${Y:-}[!]${N:-} Traffic stats are disabled."
  [[ "${1:-}" == "with_hint" ]] && echo "Enable with: sudo sbx stats enable"
  return 0
}

_stats_bind() {
  local v=''
  v=$(_stats_state_get bind)
  echo "${v:-${SBX_STATS_BIND_DEFAULT}}"
}

_stats_port() {
  local v=''
  v=$(_stats_state_get port)
  echo "${v:-${SBX_STATS_PORT_DEFAULT}}"
}

_stats_secret() {
  _stats_state_get secret
}

stats_api_base() {
  local bind='' port=''
  bind=$(_stats_bind)
  port=$(_stats_port)
  echo "http://${bind}:${port}"
}

#==============================================================================
# State-block management
#==============================================================================

# Merge a default .stats block into state.json if it's missing or incomplete.
# Idempotent; generates a new secret only the first time.
stats_ensure_state_block() {
  local state_file=''
  state_file=$(_stats_state_file)
  [[ -f "${state_file}" ]] || return 0
  have jq || return 0

  # Respect install-time opt-out without clobbering an existing block.
  local default_enabled='true'
  if [[ "${SBX_STATS_ENABLE:-1}" == "0" ]]; then
    default_enabled='false'
  fi

  # If block already fully populated, nothing to do.
  if jq -e '.stats | type == "object" and has("enabled") and has("secret") and (.secret | length) == 64' \
    "${state_file}" >/dev/null 2>&1; then
    return 0
  fi

  local secret=''
  secret=$(jq -r '.stats.secret // empty' "${state_file}" 2>/dev/null || true)
  if [[ -z "${secret}" || "${#secret}" -ne 64 ]]; then
    secret=$(generate_hex_string 32) || return 1
  fi

  state_json_apply "${state_file}" \
    '.stats = {
        enabled: (if (.stats.enabled // null) != null then .stats.enabled else ($default_enabled == "true") end),
        bind:    (.stats.bind // $bind),
        port:    (.stats.port // ($port | tonumber)),
        secret:  $secret
      }' \
    --arg default_enabled "${default_enabled}" \
    --arg bind "${SBX_STATS_BIND_DEFAULT}" \
    --arg port "${SBX_STATS_PORT_DEFAULT}" \
    --arg secret "${secret}"
}

#==============================================================================
# HTTP client
#==============================================================================

# stats_curl <path> [curl-extra-args...]
# Calls the Clash API with Bearer auth. Returns 0 + response body on 2xx;
# non-zero + empty stdout on error. Never logs the secret.
stats_curl() {
  local path="$1"
  shift || true
  local base='' secret=''
  base=$(stats_api_base)
  secret=$(_stats_secret)

  if [[ -z "${secret}" ]]; then
    err "Stats secret missing from state.json"
    return 1
  fi
  have curl || {
    err "curl not installed"
    return 1
  }

  curl -fsS --max-time "${SBX_STATS_CURL_TIMEOUT}" \
    -H "Authorization: Bearer ${secret}" \
    "$@" \
    "${base}${path}"
}

#==============================================================================
# Data collection
#==============================================================================

# Service uptime in seconds from systemd. Prints 0 if service isn't active.
_stats_service_uptime_seconds() {
  local since='' now=0 then=0
  if ! have systemctl; then
    echo 0
    return 0
  fi
  since=$(systemctl show -p ActiveEnterTimestamp --value sing-box 2>/dev/null || true)
  if [[ -z "${since}" || "${since}" == "n/a" || "${since}" == "0" ]]; then
    echo 0
    return 0
  fi
  then=$(date -d "${since}" +%s 2>/dev/null || echo 0)
  now=$(date +%s)
  if [[ "${then}" -gt 0 && "${now}" -gt "${then}" ]]; then
    echo $((now - then))
  else
    echo 0
  fi
}

# Pull one line (one sample) from /traffic streaming endpoint.
# Returns JSON like {"up": 123, "down": 456}.
_stats_traffic_sample() {
  local body=''
  # Clash API streams one JSON object per second; -N disables buffering,
  # --max-time caps us at ~1 sample.
  body=$(stats_curl /traffic -N --max-time 2 2>/dev/null | head -n 1 || true)
  if [[ -z "${body}" ]]; then
    echo '{"up":0,"down":0}'
  else
    echo "${body}"
  fi
}

_stats_memory_sample() {
  local body=''
  body=$(stats_curl /memory -N --max-time 2 2>/dev/null | head -n 1 || true)
  if [[ -z "${body}" ]]; then
    echo '{"inuse":0,"oslimit":0}'
  else
    echo "${body}"
  fi
}

_stats_connections_snapshot() {
  local body=''
  body=$(stats_curl /connections 2>/dev/null || true)
  if [[ -z "${body}" ]]; then
    echo '{"connections":[],"downloadTotal":0,"uploadTotal":0}'
  else
    echo "${body}"
  fi
}

#==============================================================================
# Formatters
#==============================================================================

_stats_human_bytes() {
  local bytes="${1:-0}"
  awk -v b="${bytes}" 'BEGIN{
    split("B KB MB GB TB PB", u);
    i=1; while (b >= 1024 && i < 6) { b /= 1024; i++ }
    printf (i == 1) ? "%d %s" : "%.2f %s", b, u[i]
  }'
}

_stats_human_duration() {
  local s="${1:-0}"
  local d=$((s / 86400))
  local h=$(((s % 86400) / 3600))
  local m=$(((s % 3600) / 60))
  local sec=$((s % 60))
  if ((d > 0)); then
    printf '%dd %dh %dm' "${d}" "${h}" "${m}"
  elif ((h > 0)); then
    printf '%dh %dm %ds' "${h}" "${m}" "${sec}"
  elif ((m > 0)); then
    printf '%dm %ds' "${m}" "${sec}"
  else
    printf '%ds' "${sec}"
  fi
}

# Group connections by matched user. sing-box records the VLESS/TLS user
# in metadata.user for Reality/WS inbounds.
_stats_group_by_user_json() {
  local conns_json="$1"
  echo "${conns_json}" | jq '
    (.connections // [])
    | group_by(.metadata.user // "")
    | map({
        user: (.[0].metadata.user // "unknown"),
        count: length,
        upload: (map(.upload // 0) | add // 0),
        download: (map(.download // 0) | add // 0)
      })
    | sort_by(-(.upload + .download))
  '
}

#==============================================================================
# Public: overview
#==============================================================================

# Pretty-printed overview for humans.
stats_overview_pretty() {
  _stats_enabled || {
    _stats_disabled_notice with_hint
    return 0
  }

  local base='' uptime_s=0 traffic='' mem='' conns=''
  base=$(stats_api_base)
  uptime_s=$(_stats_service_uptime_seconds)
  traffic=$(_stats_traffic_sample)
  mem=$(_stats_memory_sample)
  conns=$(_stats_connections_snapshot)

  local up='' down='' inuse='' oslimit='' conn_count=0 total_up=0 total_down=0
  up=$(echo "${traffic}" | jq -r '.up // 0')
  down=$(echo "${traffic}" | jq -r '.down // 0')
  inuse=$(echo "${mem}" | jq -r '.inuse // 0')
  oslimit=$(echo "${mem}" | jq -r '.oslimit // 0')
  conn_count=$(echo "${conns}" | jq -r '(.connections // []) | length')
  total_up=$(echo "${conns}" | jq -r '.uploadTotal // 0')
  total_down=$(echo "${conns}" | jq -r '.downloadTotal // 0')

  echo -e "${B:-}=== sbx Traffic Statistics ===${N:-}"
  echo "Endpoint:         ${base}"
  echo "Service uptime:   $(_stats_human_duration "${uptime_s}")"
  echo
  echo -e "${B:-}Current throughput${N:-}"
  printf '  %-12s %s/s\n' "Upload:" "$(_stats_human_bytes "${up}")"
  printf '  %-12s %s/s\n' "Download:" "$(_stats_human_bytes "${down}")"
  echo
  echo -e "${B:-}Cumulative (since service start)${N:-}"
  printf '  %-12s %s\n' "Upload:" "$(_stats_human_bytes "${total_up}")"
  printf '  %-12s %s\n' "Download:" "$(_stats_human_bytes "${total_down}")"
  printf '  %-12s %s\n' "Connections:" "${conn_count}"
  echo
  echo -e "${B:-}Memory${N:-}"
  printf '  %-12s %s\n' "In use:" "$(_stats_human_bytes "${inuse}")"
  if [[ "${oslimit}" -gt 0 ]]; then
    printf '  %-12s %s\n' "OS limit:" "$(_stats_human_bytes "${oslimit}")"
  fi
}

# JSON overview. Single object, no secret leakage.
stats_overview_json() {
  have jq || {
    err "jq is required for --json output"
    return 1
  }

  if ! _stats_enabled; then
    jq -n '{enabled:false}'
    return 0
  fi

  local uptime_s=0 traffic='{}' mem='{}' conns='{}'
  uptime_s=$(_stats_service_uptime_seconds)
  traffic=$(_stats_traffic_sample)
  mem=$(_stats_memory_sample)
  conns=$(_stats_connections_snapshot)

  local by_user=''
  by_user=$(_stats_group_by_user_json "${conns}")

  jq -n \
    --argjson uptime "${uptime_s}" \
    --argjson traffic "${traffic}" \
    --argjson mem "${mem}" \
    --argjson conns "${conns}" \
    --argjson by_user "${by_user}" \
    '{
       enabled: true,
       uptime_seconds: $uptime,
       traffic: {
         up_bps:       ($traffic.up   // 0),
         down_bps:     ($traffic.down // 0),
         upload_total: ($conns.uploadTotal   // 0),
         download_total: ($conns.downloadTotal // 0)
       },
       connections: {
         count:   (($conns.connections // []) | length),
         by_user: $by_user
       },
       memory: {
         inuse:   ($mem.inuse   // 0),
         oslimit: ($mem.oslimit // 0)
       }
     }'
}

#==============================================================================
# Public: connections
#==============================================================================

stats_connections_pretty() {
  _stats_enabled || {
    _stats_disabled_notice
    return 0
  }
  local conns=''
  conns=$(_stats_connections_snapshot)

  local count=0
  count=$(echo "${conns}" | jq -r '(.connections // []) | length')
  if [[ "${count}" -eq 0 ]]; then
    echo "No active connections."
    return 0
  fi

  printf '%-22s %-14s %-10s %-12s %-12s %s\n' \
    "REMOTE" "INBOUND" "USER" "UP" "DOWN" "AGE"
  printf '%-22s %-14s %-10s %-12s %-12s %s\n' \
    "----------------------" "--------------" "----------" "------------" "------------" "---------"

  local now_s=0
  now_s=$(date +%s)

  while IFS=$'\t' read -r host rule inbound user up down start; do
    local age_s=0 start_s=0
    start_s=$(date -d "${start}" +%s 2>/dev/null || echo 0)
    if [[ "${start_s}" -gt 0 && "${now_s}" -gt "${start_s}" ]]; then
      age_s=$((now_s - start_s))
    fi
    local dest="${host:-?}"
    [[ "${rule}" != "" && "${rule}" != "null" ]] && dest="${dest} (${rule})"
    printf '%-22s %-14s %-10s %-12s %-12s %s\n' \
      "${dest:0:22}" "${inbound:-?}" "${user:-?}" \
      "$(_stats_human_bytes "${up}")" \
      "$(_stats_human_bytes "${down}")" \
      "$(_stats_human_duration "${age_s}")"
  done < <(echo "${conns}" | jq -r '
    (.connections // [])[]
    | [
        ((.metadata.host // .metadata.destinationIP // "") + ":" + (.metadata.destinationPort // "")),
        (.rule // ""),
        (.metadata.inboundName // .metadata.inboundTag // .metadata.type // ""),
        (.metadata.user // ""),
        (.upload // 0),
        (.download // 0),
        (.start // "")
      ] | @tsv
  ')
}

stats_connections_json() {
  have jq || {
    err "jq is required for --json output"
    return 1
  }
  if ! _stats_enabled; then
    jq -n '{enabled:false,connections:[]}'
    return 0
  fi
  local conns=''
  conns=$(_stats_connections_snapshot)
  echo "${conns}" | jq '{
    enabled: true,
    count: ((.connections // []) | length),
    upload_total:   (.uploadTotal   // 0),
    download_total: (.downloadTotal // 0),
    connections: (.connections // [])
  }'
}

#==============================================================================
# Public: per-user
#==============================================================================

stats_users_pretty() {
  _stats_enabled || {
    _stats_disabled_notice
    return 0
  }
  local conns='' grouped=''
  conns=$(_stats_connections_snapshot)
  grouped=$(_stats_group_by_user_json "${conns}")

  local count=0
  count=$(echo "${grouped}" | jq 'length')
  if [[ "${count}" -eq 0 ]]; then
    echo "No active per-user traffic to report."
    return 0
  fi

  printf '%-20s %-8s %-14s %s\n' "USER" "CONNS" "UP (live)" "DOWN (live)"
  printf '%-20s %-8s %-14s %s\n' "--------------------" "--------" "--------------" "--------------"
  while IFS=$'\t' read -r user count up down; do
    printf '%-20s %-8s %-14s %s\n' "${user:-unknown}" "${count}" \
      "$(_stats_human_bytes "${up}")" "$(_stats_human_bytes "${down}")"
  done < <(echo "${grouped}" | jq -r '.[] | [.user, .count, .upload, .download] | @tsv')
}

stats_users_json() {
  have jq || {
    err "jq is required for --json output"
    return 1
  }
  if ! _stats_enabled; then
    jq -n '{enabled:false,users:[]}'
    return 0
  fi
  local conns='' grouped=''
  conns=$(_stats_connections_snapshot)
  grouped=$(_stats_group_by_user_json "${conns}")
  jq -n --argjson users "${grouped}" '{enabled:true, users:$users}'
}

#==============================================================================
# Public: enable / disable
#==============================================================================

# Flip .stats.enabled and, if the value actually changed, regenerate the
# sing-box config and restart the service. Arg: "true" or "false".
_stats_set_enabled() {
  local target="$1" restart_msg="$2"
  local state_file=''
  state_file=$(_stats_state_file)
  [[ -f "${state_file}" ]] || {
    err "state.json not found"
    return 1
  }

  if [[ "$(_stats_state_get enabled)" == "${target}" ]]; then
    msg "Stats already $([[ "${target}" == "true" ]] && echo enabled || echo disabled); no changes."
    return 0
  fi

  state_json_apply "${state_file}" ".stats.enabled = ${target}" || return 1

  if declare -f write_config >/dev/null 2>&1; then
    write_config || {
      err "Config regeneration failed"
      return 1
    }
  fi

  if have systemctl; then
    systemctl restart sing-box 2>/dev/null &&
      success "${restart_msg}" ||
      warn "Failed to restart sing-box; run: systemctl restart sing-box"
  fi
}

stats_enable() {
  stats_ensure_state_block || return 1
  _stats_set_enabled true "sing-box restarted with Clash API enabled" || return 1
  msg "Endpoint: $(stats_api_base)"
  msg "Stats enabled. Use 'sbx stats' to view."
}

stats_disable() {
  _stats_set_enabled false "sing-box restarted without Clash API" || return 1
  msg "Stats disabled."
}

#==============================================================================
# Exports
#==============================================================================

export -f stats_ensure_state_block stats_api_base stats_curl
export -f stats_overview_pretty stats_overview_json
export -f stats_connections_pretty stats_connections_json
export -f stats_users_pretty stats_users_json
export -f stats_enable stats_disable
