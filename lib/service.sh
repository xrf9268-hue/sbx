#!/usr/bin/env bash
# lib/service.sh - systemd service management
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_SERVICE_LOADED:-}" ]] && return 0
readonly _SBX_SERVICE_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/network.sh"

# Declare external variables from common.sh
# shellcheck disable=SC2154
: "${SB_SVC:?}" "${SB_BIN:?}" "${SB_CONF:?}" "${LOG_VIEW_DEFAULT_HISTORY:?}"

#==============================================================================
# Service File Creation
#==============================================================================

# Create systemd service unit file
create_service_file() {
  msg "Creating systemd service ..."

  cat > "${SB_SVC}" << 'EOF'
[Unit]
Description=sing-box
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  success "  ✓ Service file created"
  return 0
}

#==============================================================================
# Service Management
#==============================================================================

# Start service with retry logic for port binding failures
start_service_with_retry() {
  local max_retries=3
  local retry_count=0
  local wait_time=2

  msg "Starting sing-box service..."

  while [[ ${retry_count} -lt ${max_retries} ]]; do
    # Attempt to start the service
    if systemctl start sing-box 2>&1; then
      sleep "${SERVICE_WAIT_MEDIUM_SEC:-2}"
      # Check if service is actually active
      if systemctl is-active sing-box > /dev/null 2>&1; then
        success "  ✓ sing-box service started successfully"
        return 0
      fi
    fi

    # Service failed to start - check if it's a port binding issue
    local error_log=''
    error_log=$(journalctl -u sing-box -n 20 --no-pager 2> /dev/null \
      | grep -iE "bind|address.*in use|listen.*failed" | head -3 || true)

    if [[ -n "${error_log}" ]]; then
      retry_count=$((retry_count + 1))
      if [[ ${retry_count} -lt ${max_retries} ]]; then
        warn "Port binding failed, retrying (${retry_count}/${max_retries}) in ${wait_time}s..."
        warn "Error: $(echo "${error_log}" | head -1)"
        systemctl stop sing-box 2> /dev/null || true
        sleep "${wait_time}"
        wait_time=$((wait_time * 2)) # Exponential backoff
      else
        err "Failed to start sing-box after ${max_retries} attempts"
        err "Last error:"
        echo "${error_log}" | head -5 >&2
        return 1
      fi
    else
      # Non-port-related failure - don't retry
      err "sing-box service failed to start (non-port issue)"
      journalctl -u sing-box -n 30 --no-pager >&2
      return 1
    fi
  done

  err "Failed to start sing-box service after ${max_retries} retries"
  return 1
}

# Setup and start sing-box service
setup_service() {
  local ws_port='' hy2_port=''
  create_service_file || die_with_code "SBX-SERVICE-001" \
    "Failed to create systemd service file." \
    "Check write permissions for /etc/systemd/system." \
    "ls -ld /etc/systemd/system"

  # Reload systemd daemon
  systemctl daemon-reload || die_with_code "SBX-SERVICE-002" \
    "Failed to reload systemd daemon." \
    "Check systemd state and journal for details." \
    "systemctl status --no-pager"

  # Validate configuration before starting service
  msg "Validating configuration before starting service..."
  "${SB_BIN}" check -c "${SB_CONF}" 2>&1 || die_with_code "SBX-SERVICE-003" \
    "Configuration validation failed. Service not started." \
    "Fix config syntax/fields and re-run service setup." \
    "${SB_BIN} check -c ${SB_CONF}"
  success "  ✓ Configuration validated"

  # Enable service for auto-start on boot
  msg "Enabling sing-box service..."
  systemctl enable sing-box || warn "Failed to enable service (continuing anyway)"

  # Start the service with retry logic
  start_service_with_retry || die_with_code "SBX-SERVICE-004" \
    "Failed to start sing-box service." \
    "Inspect bind conflicts and service logs, then retry." \
    "journalctl -u sing-box -n 80 --no-pager"

  # Wait for service to become active (intelligent polling with timeout)
  msg "  - Waiting for service to become active..."
  local waited=0
  local max_wait="${SERVICE_STARTUP_MAX_WAIT_SEC:-10}"
  while [[ ${waited} -lt "${max_wait}" ]]; do
    if systemctl is-active sing-box > /dev/null 2>&1; then
      break
    fi
    sleep "${SERVICE_WAIT_SHORT_SEC:-1}"
    waited=$((waited + 1))
  done

  # Verify service is running
  if systemctl is-active sing-box > /dev/null 2>&1; then
    success "  ✓ sing-box service is active (${waited}s)"
  else
    err "sing-box service failed to become active within ${max_wait}s"
    msg "Checking service status and logs..."
    systemctl status sing-box --no-pager || true
    journalctl -u sing-box -n 50 --no-pager || true
    die_with_code "SBX-SERVICE-005" \
      "Service startup timed out before reaching active state." \
      "Review systemd status and journal logs to identify runtime failures." \
      "systemctl status sing-box --no-pager"
  fi

  # Validate port listening (Reality-only mode check)
  local reality_port="${REALITY_PORT_CHOSEN:-${REALITY_PORT}}"
  if validate_port_listening "${reality_port}" "Reality"; then
    success "  ✓ Reality service listening on port ${reality_port}"
  fi

  # Check WS and Hysteria2 ports if certificates are configured
  if [[ -n "${CERT_FULLCHAIN:-}" && -f "${CERT_FULLCHAIN:-}" ]]; then
    ws_port="${WS_PORT_CHOSEN:-${WS_PORT}}"
    hy2_port="${HY2_PORT_CHOSEN:-${HY2_PORT}}"

    validate_port_listening "${ws_port}" "WS-TLS" "tcp" || warn "WS-TLS may not be listening properly"
    validate_port_listening "${hy2_port}" "Hysteria2" "udp" || warn "Hysteria2 may not be listening properly"
  fi

  return 0
}

# Validate that service is listening on specified port
# Supports both TCP and UDP protocols
validate_port_listening() {
  local port="$1"
  local service_name="${2:-Service}"
  local protocol="${3:-tcp}" # Default to TCP, can be "udp" for Hysteria2
  local max_attempts=5
  local attempt=0

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if [[ "${protocol}" == "udp" ]]; then
      # Check UDP ports
      if ss -lnup 2> /dev/null | grep -q ":${port} "; then
        return 0
      fi
    else
      # Check TCP ports
      if ss -lntp 2> /dev/null | grep -q ":${port} " \
        || lsof -iTCP -sTCP:LISTEN -P -n 2> /dev/null | grep -q ":${port}"; then
        return 0
      fi
    fi

    attempt=$((attempt + 1))
    if [[ ${attempt} -lt ${max_attempts} ]]; then
      sleep "${SERVICE_WAIT_SHORT_SEC:-1}"
    fi
  done

  warn "${service_name} port ${port} not listening after ${max_attempts} attempts"
  return 1
}

#==============================================================================
# Service Status Checking
#==============================================================================

# Check if sing-box service is running
check_service_status() {
  systemctl is-active sing-box > /dev/null 2>&1
}

# Stop sing-box service
stop_service() {
  if check_service_status; then
    msg "Stopping sing-box service..."
    systemctl stop sing-box || warn "Failed to stop service gracefully"

    # Wait for service to fully stop
    local max_wait="${SERVICE_STARTUP_MAX_WAIT_SEC:-10}"
    local waited=0
    while systemctl is-active sing-box > /dev/null 2>&1 && [[ ${waited} -lt ${max_wait} ]]; do
      sleep "${SERVICE_WAIT_SHORT_SEC:-1}"
      waited=$((waited + 1))
    done

    if systemctl is-active sing-box > /dev/null 2>&1; then
      warn "Service did not stop within ${max_wait}s"
      return 1
    fi

    success "  ✓ Service stopped"
  fi
  return 0
}

# Restart sing-box service
restart_service() {
  with_flock "${SBX_LOCK_TIMEOUT_SEC:-30}" _restart_service_impl "$@"
}

_restart_service_impl() {
  msg "Restarting sing-box service..."

  # Validate configuration before restart
  if [[ -f "${SB_CONF}" ]]; then
    if ! "${SB_BIN}" check -c "${SB_CONF}" 2>&1; then
      die_with_code "SBX-SERVICE-006" \
        "Configuration validation failed. Service not restarted." \
        "Fix configuration errors before restart." \
        "${SB_BIN} check -c ${SB_CONF}"
    fi
  fi

  systemctl restart sing-box || die_with_code "SBX-SERVICE-007" \
    "Failed to restart sing-box service." \
    "Inspect journal and unit file, then retry restart." \
    "journalctl -u sing-box -n 80 --no-pager"
  sleep "${SERVICE_WAIT_MEDIUM_SEC:-2}"

  if check_service_status; then
    success "  ✓ Service restarted successfully"
    return 0
  else
    err "Service failed to restart"
    systemctl status sing-box --no-pager || true
    return 1
  fi
}

# Reload sing-box service configuration
reload_service() {
  if check_service_status; then
    msg "Reloading sing-box service configuration..."
    systemctl reload sing-box 2> /dev/null || restart_service
  else
    msg "Service not running, starting instead..."
    systemctl start sing-box || die_with_code "SBX-SERVICE-008" \
      "Failed to start service." \
      "Inspect systemd logs and service unit configuration." \
      "journalctl -u sing-box -n 80 --no-pager"
  fi
}

#==============================================================================
# Service Uninstallation
#==============================================================================

# Remove sing-box service
remove_service() {
  msg "Removing sing-box service..."

  # Stop service if running
  if systemctl is-active sing-box > /dev/null 2>&1; then
    systemctl stop sing-box || warn "Failed to stop service"
  fi

  # Disable service
  if systemctl is-enabled sing-box > /dev/null 2>&1; then
    systemctl disable sing-box || warn "Failed to disable service"
  fi

  # Remove service file
  if [[ -f "${SB_SVC}" ]]; then
    rm -f "${SB_SVC}"
    success "  ✓ Service file removed"
  fi

  # Reload systemd daemon
  systemctl daemon-reload

  success "Service removed successfully"
  return 0
}

#==============================================================================
# Service Logs
#==============================================================================

# Show service logs with resource limits
show_service_logs() {
  local lines="${1:-50}"
  local follow="${2:-false}"
  local max_lines="${3:-${LOG_VIEW_MAX_LINES}}" # Maximum lines to follow

  # Validate line count
  if ! [[ "${lines}" =~ ^[0-9]+$ ]] || [[ "${lines}" -gt "${LOG_VIEW_MAX_LINES}" ]]; then
    err "Invalid line count (must be 1-${LOG_VIEW_MAX_LINES}): ${lines}"
    return 1
  fi

  if [[ "${follow}" == "true" ]]; then
    # Limit output with head to prevent resource exhaustion
    warn "Following logs (Ctrl+C to exit, limited to ${max_lines} lines)..."
    journalctl -u sing-box -f --since "${LOG_VIEW_DEFAULT_HISTORY}" | head -n "${max_lines}"
  else
    journalctl -u sing-box -n "${lines}" --no-pager
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f create_service_file start_service_with_retry setup_service validate_port_listening
export -f check_service_status stop_service restart_service reload_service
export -f remove_service show_service_logs
