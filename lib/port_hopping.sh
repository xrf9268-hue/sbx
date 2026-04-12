#!/usr/bin/env bash
# lib/port_hopping.sh - Hysteria2 port hopping via DNAT rules
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_PORT_HOPPING_LOADED:-}" ]] && return 0
readonly _SBX_PORT_HOPPING_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
[[ -z "${_SBX_LOGGING_LOADED:-}" ]] && source "${_LIB_DIR}/logging.sh"

# Constants
readonly PORT_HOP_MIN_PORT=1024
readonly PORT_HOP_MAX_PORT=65535
readonly PORT_HOP_MAX_RANGE_SIZE=20000
readonly PORT_HOP_NFTABLES_TABLE="sbx_port_hop"
readonly PORT_HOP_NFTABLES_CONF="/etc/nftables.d/sbx-port-hop.conf"
readonly PORT_HOP_IPTABLES_COMMENT="sbx-port-hop"
readonly PORT_HOP_SYSTEMD_UNIT="sbx-port-hop.service"

#==============================================================================
# Internal Helpers
#==============================================================================

_create_nftables_rules() {
  local target_port="$1"
  local range_start="$2"
  local range_end="$3"

  nft delete table inet "${PORT_HOP_NFTABLES_TABLE}" 2>/dev/null || true

  nft add table inet "${PORT_HOP_NFTABLES_TABLE}"
  nft add chain inet "${PORT_HOP_NFTABLES_TABLE}" prerouting \
    '{ type nat hook prerouting priority dstnat; policy accept; }'
  nft add rule inet "${PORT_HOP_NFTABLES_TABLE}" prerouting \
    udp dport "${range_start}-${range_end}" redirect to :"${target_port}"
}

_create_iptables_rules() {
  local target_port="$1"
  local range_start="$2"
  local range_end="$3"

  _remove_iptables_rules 2>/dev/null || true

  iptables -t nat -A PREROUTING -p udp --dport "${range_start}:${range_end}" \
    -j REDIRECT --to-ports "${target_port}" \
    -m comment --comment "${PORT_HOP_IPTABLES_COMMENT}"

  if have ip6tables; then
    ip6tables -t nat -A PREROUTING -p udp --dport "${range_start}:${range_end}" \
      -j REDIRECT --to-ports "${target_port}" \
      -m comment --comment "${PORT_HOP_IPTABLES_COMMENT}"
  fi
}

_remove_nftables_rules() {
  nft delete table inet "${PORT_HOP_NFTABLES_TABLE}" 2>/dev/null || true
}

# Remove all sbx-port-hop iptables rules by comment match
_remove_rules_for_cmd() {
  local cmd="$1"
  local rule_num=""
  while rule_num=$("${cmd}" -t nat -L PREROUTING --line-numbers -n 2>/dev/null |
    grep "${PORT_HOP_IPTABLES_COMMENT}" | head -1 | awk '{print $1}'); do
    [[ -z "${rule_num}" ]] && break
    "${cmd}" -t nat -D PREROUTING "${rule_num}" 2>/dev/null || break
  done
}

_remove_iptables_rules() {
  _remove_rules_for_cmd iptables
  have ip6tables && _remove_rules_for_cmd ip6tables
}

_persist_nftables_rules() {
  local target_port="$1"
  local range_start="$2"
  local range_end="$3"

  mkdir -p "$(dirname "${PORT_HOP_NFTABLES_CONF}")"

  cat >"${PORT_HOP_NFTABLES_CONF}" <<EOF
#!/usr/sbin/nft -f
# Port hopping rules for Hysteria2 (managed by sbx)
table inet ${PORT_HOP_NFTABLES_TABLE} {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    udp dport ${range_start}-${range_end} redirect to :${target_port}
  }
}
EOF

  if [[ -f /etc/nftables.conf ]] && ! grep -q 'nftables.d' /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/*.conf"' >>/etc/nftables.conf
  fi
}

_persist_iptables_rules() {
  local target_port="$1"
  local range_start="$2"
  local range_end="$3"

  if have netfilter-persistent; then
    netfilter-persistent save 2>/dev/null || true
    return 0
  fi

  cat >"/etc/systemd/system/${PORT_HOP_SYSTEMD_UNIT}" <<EOF
[Unit]
Description=sbx Hysteria2 port hopping DNAT rules
Before=sing-box.service
After=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables -t nat -A PREROUTING -p udp --dport ${range_start}:${range_end} -j REDIRECT --to-ports ${target_port} -m comment --comment ${PORT_HOP_IPTABLES_COMMENT}
ExecStop=/sbin/iptables -t nat -D PREROUTING -p udp --dport ${range_start}:${range_end} -j REDIRECT --to-ports ${target_port} -m comment --comment ${PORT_HOP_IPTABLES_COMMENT}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${PORT_HOP_SYSTEMD_UNIT}" 2>/dev/null || true
}

_remove_persisted_rules() {
  rm -f "${PORT_HOP_NFTABLES_CONF}"

  if [[ -f "/etc/systemd/system/${PORT_HOP_SYSTEMD_UNIT}" ]]; then
    systemctl disable "${PORT_HOP_SYSTEMD_UNIT}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${PORT_HOP_SYSTEMD_UNIT}"
    systemctl daemon-reload
  fi

  if have netfilter-persistent; then
    netfilter-persistent save 2>/dev/null || true
  fi
}

#==============================================================================
# Public API
#==============================================================================

# Returns 0 on success, 1 on failure with error message
validate_port_range() {
  local range_str="${1:-}"

  [[ -z "${range_str}" ]] && {
    err "[SBX-PORTHOP-001] Port range cannot be empty"
    return 1
  }

  if ! echo "${range_str}" | grep -qE '^[0-9]+-[0-9]+$'; then
    err "[SBX-PORTHOP-002] Invalid port range format: ${range_str} (expected: START-END, e.g., 20000-40000)"
    return 1
  fi

  local range_start="${range_str%%-*}"
  local range_end="${range_str##*-}"

  if [[ "${range_start}" -lt "${PORT_HOP_MIN_PORT}" ]]; then
    err "[SBX-PORTHOP-003] Port range start ${range_start} is below minimum ${PORT_HOP_MIN_PORT}"
    return 1
  fi

  if [[ "${range_end}" -gt "${PORT_HOP_MAX_PORT}" ]]; then
    err "[SBX-PORTHOP-004] Port range end ${range_end} exceeds maximum ${PORT_HOP_MAX_PORT}"
    return 1
  fi

  if [[ "${range_start}" -ge "${range_end}" ]]; then
    err "[SBX-PORTHOP-005] Port range start ${range_start} must be less than end ${range_end}"
    return 1
  fi

  local range_size=$((range_end - range_start))
  if [[ "${range_size}" -gt "${PORT_HOP_MAX_RANGE_SIZE}" ]]; then
    err "[SBX-PORTHOP-006] Port range size ${range_size} exceeds maximum ${PORT_HOP_MAX_RANGE_SIZE}"
    return 1
  fi

  return 0
}

# Prints "nftables" or "iptables"
detect_nat_backend() {
  if have nft; then
    echo "nftables"
  elif have iptables; then
    echo "iptables"
  else
    err "[SBX-PORTHOP-010] Neither nftables (nft) nor iptables found. Install one to enable port hopping."
    return 1
  fi
}

apply_port_hopping_rules() {
  local target_port="${1:?target_port required}"
  local range_start="${2:?range_start required}"
  local range_end="${3:?range_end required}"

  local backend=""
  backend=$(detect_nat_backend) || return 1

  msg "Applying port hopping rules (${backend}): UDP ${range_start}-${range_end} → ${target_port}..."

  case "${backend}" in
    nftables)
      _create_nftables_rules "${target_port}" "${range_start}" "${range_end}"
      ;;
    iptables)
      _create_iptables_rules "${target_port}" "${range_start}" "${range_end}"
      ;;
  esac

  success "  ✓ Port hopping rules applied (${backend})"
}

remove_port_hopping_rules() {
  local target_port="${1:-}"
  local range_start="${2:-}"
  local range_end="${3:-}"

  _remove_nftables_rules 2>/dev/null || true

  if [[ -n "${target_port}" && -n "${range_start}" && -n "${range_end}" ]]; then
    _remove_iptables_rules 2>/dev/null || true
  fi

  _remove_persisted_rules

  msg "  Port hopping rules removed"
}

persist_port_hopping_rules() {
  local target_port="${1:?target_port required}"
  local range_start="${2:?range_start required}"
  local range_end="${3:?range_end required}"

  local backend=""
  backend=$(detect_nat_backend) || return 1

  case "${backend}" in
    nftables)
      _persist_nftables_rules "${target_port}" "${range_start}" "${range_end}"
      ;;
    iptables)
      _persist_iptables_rules "${target_port}" "${range_start}" "${range_end}"
      ;;
  esac

  success "  ✓ Port hopping rules persisted (${backend})"
}

show_port_hopping_status() {
  local state_file="${TEST_STATE_FILE:-${STATE_FILE:-/etc/sing-box/state.json}}"
  local port_range=""
  local hy2_port=""
  local hy2_enabled=""

  if [[ -f "${state_file}" ]]; then
    port_range=$(jq -r '.protocols.hysteria2.port_range // empty' "${state_file}" 2>/dev/null) || true
    hy2_port=$(jq -r '.protocols.hysteria2.port // empty' "${state_file}" 2>/dev/null) || true
    hy2_enabled=$(jq -r '.protocols.hysteria2.enabled // empty' "${state_file}" 2>/dev/null) || true
  fi

  echo "=== Hysteria2 Port Hopping Status ==="
  echo

  if [[ "${hy2_enabled}" != "true" ]]; then
    echo "Hysteria2: not enabled"
    return 0
  fi

  echo "Hysteria2 port: ${hy2_port:-N/A}"

  if [[ -z "${port_range}" ]]; then
    echo "Port hopping:   disabled"
  else
    echo "Port hopping:   enabled"
    echo "Port range:     ${port_range}"
  fi

  echo

  local backend=""
  backend=$(detect_nat_backend 2>/dev/null) || true

  if [[ "${backend}" == "nftables" ]]; then
    echo "Active nftables rules:"
    if nft list table inet "${PORT_HOP_NFTABLES_TABLE}" 2>/dev/null; then
      :
    else
      echo "  (no rules found)"
    fi
  elif [[ "${backend}" == "iptables" ]]; then
    echo "Active iptables NAT rules:"
    local rules=""
    rules=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep "${PORT_HOP_IPTABLES_COMMENT}" || true)
    if [[ -n "${rules}" ]]; then
      echo "${rules}" | sed 's/^/  /'
    else
      echo "  (no rules found)"
    fi
  else
    echo "NAT backend: not available"
  fi
}
