#!/usr/bin/env bash
# lib/certificate.sh - Caddy-based certificate management
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CERTIFICATE_LOADED:-}" ]] && return 0
readonly _SBX_CERTIFICATE_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/network.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/validation.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/caddy.sh"

#==============================================================================
# Certificate Management
#==============================================================================

# Issue certificate based on CERT_MODE or use existing
maybe_issue_cert() {
  # Check if certificate files already provided
  if [[ -n "${CERT_FULLCHAIN}" && -n "${CERT_KEY}" && -f "${CERT_FULLCHAIN}" && -f "${CERT_KEY}" ]]; then
    msg "Using provided certificate paths."
    validate_cert_files "${CERT_FULLCHAIN}" "${CERT_KEY}" || die "Certificate validation failed"
    return 0
  fi

  # Auto-enable certificate issuance if domain is provided but CERT_MODE is not set
  if [[ -z "${CERT_MODE}" ]]; then
    if [[ -n "${DOMAIN}" && "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      info "No CERT_MODE specified - using Caddy for automatic certificate management"
      info "  ℹ Caddy will automatically obtain and renew certificates via Let's Encrypt"
      export CERT_MODE="caddy"
      debug "Auto-enabled certificate mode: caddy (domain: ${DOMAIN})"
    else
      # No domain or Reality-only mode - skip certificate issuance
      debug "Skipping certificate issuance (Reality-only mode or no domain)"
      return 0
    fi
  else
    msg "Certificate mode: ${CERT_MODE}"
  fi

  # Issue certificate based on mode
  case "${CERT_MODE}" in
    caddy)
      # HTTP-01 challenge - requires port 80
      # Check port 80 availability first
      if ! check_port_80_for_acme; then
        warn "Port 80 is not available for HTTP-01 challenge"
        show_port_80_guidance
        warn "Consider using CERT_MODE=cf_dns if port 80 cannot be opened"
      fi

      # Install Caddy
      caddy_install || die "Failed to install Caddy"

      # Setup Caddy with automatic TLS
      caddy_setup_auto_tls "${DOMAIN}" "${REALITY_PORT_CHOSEN:-443}" || die "Failed to setup Caddy auto TLS"

      # Setup certificate synchronization
      caddy_setup_cert_sync "${DOMAIN}" || die "Failed to setup certificate sync"
      ;;

    cf_dns)
      # DNS-01 challenge via Cloudflare API - no port 80 required
      info "Using DNS-01 challenge via Cloudflare API"
      info "  ℹ No port 80 required for DNS-01 challenge"

      # Install Caddy with CF DNS plugin
      caddy_install_with_cf_dns || die "Failed to install Caddy with CF DNS plugin"

      # Setup DNS challenge
      caddy_setup_dns_challenge "${DOMAIN}" || die "Failed to setup DNS-01 challenge"

      # Wait for certificate and sync to sing-box
      caddy_setup_cert_sync "${DOMAIN}" || die "Failed to setup certificate sync"
      ;;

    *)
      die "Unknown CERT_MODE: ${CERT_MODE} (supported: caddy, cf_dns)"
      ;;
  esac

  success "Certificate installed: ${CERT_FULLCHAIN}"
  return 0
}

# Check certificate expiration
check_cert_expiry() {
  local cert_file="${1:-${CERT_FULLCHAIN}}"
  local expiry_date='' expiry_epoch='' now_epoch='' days_left=0
  [[ -f "${cert_file}" ]] || return 1

  expiry_date=$(openssl x509 -in "${cert_file}" -noout -enddate 2> /dev/null | cut -d= -f2)

  if [[ -n "${expiry_date}" ]]; then
    expiry_epoch=$(date -d "${expiry_date}" +%s 2> /dev/null || date -j -f "%b %d %T %Y %Z" "${expiry_date}" +%s 2> /dev/null)
    now_epoch=$(date +%s)
    days_left=$(((expiry_epoch - now_epoch) / 86400))

    if [[ ${days_left} -lt 30 ]]; then
      warn "Certificate expires in ${days_left} days: ${cert_file}"
      return 2
    elif [[ ${days_left} -lt 0 ]]; then
      err "Certificate has expired: ${cert_file}"
      return 1
    else
      info "Certificate valid for ${days_left} days"
      return 0
    fi
  fi

  return 1
}

#==============================================================================
# Export Functions
#==============================================================================

export -f maybe_issue_cert check_cert_expiry
