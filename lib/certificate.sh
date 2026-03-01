#!/usr/bin/env bash
# lib/certificate.sh - Certificate and ACME management
# Part of sbx-lite modular architecture
#
# sing-box 1.13.0+ handles ACME natively via TLS inbound config.
# This module resolves CERT_MODE and validates parameters.
# Actual ACME configuration is built by _build_tls_block() in config.sh.

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
source "${_LIB_DIR}/validation.sh"

#==============================================================================
# Certificate / ACME Management
#==============================================================================

# Resolve certificate mode and validate parameters
# Sets CERT_MODE for downstream use by _build_tls_block() in config.sh
maybe_issue_cert() {
  # Case 1: Manual certificate files provided — validate and return
  if [[ -n "${CERT_FULLCHAIN}" && -n "${CERT_KEY}" && -f "${CERT_FULLCHAIN}" && -f "${CERT_KEY}" ]]; then
    msg "Using provided certificate paths."
    validate_cert_files "${CERT_FULLCHAIN}" "${CERT_KEY}" || die "Certificate validation failed"
    return 0
  fi

  # Case 2: Auto-resolve CERT_MODE when domain is provided
  if [[ -z "${CERT_MODE}" ]]; then
    if [[ -n "${DOMAIN}" && "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      info "No CERT_MODE specified — using sing-box native ACME (HTTP-01)"
      info "  ℹ sing-box will automatically obtain and renew certificates via Let's Encrypt"
      export CERT_MODE="acme"
      debug "Auto-enabled certificate mode: acme (domain: ${DOMAIN})"
    else
      # No domain or Reality-only mode — skip certificate issuance
      debug "Skipping certificate setup (Reality-only mode or no domain)"
      return 0
    fi
  else
    msg "Certificate mode: ${CERT_MODE}"
  fi

  # Case 3: Resolve and validate CERT_MODE
  case "${CERT_MODE}" in
    acme)
      # HTTP-01 challenge via sing-box native ACME
      info "Using sing-box native ACME (HTTP-01 challenge)"
      info "  ℹ Port 80 required for HTTP-01 — ensure it is accessible"
      # Ensure ACME data directory exists
      mkdir -p /var/lib/sing-box/acme 2>/dev/null || true
      ;;

    caddy)
      # Backward compatibility: map 'caddy' to 'acme' with migration warning
      warn "CERT_MODE=caddy is deprecated — sing-box 1.13.0+ handles ACME natively"
      warn "  ℹ Automatically mapped to CERT_MODE=acme"
      warn "  ℹ Run 'sbx caddy-cleanup' to remove old Caddy installation"
      export CERT_MODE="acme"
      mkdir -p /var/lib/sing-box/acme 2>/dev/null || true
      ;;

    cf_dns)
      # DNS-01 challenge via sing-box native ACME with Cloudflare
      info "Using sing-box native ACME (DNS-01 via Cloudflare)"
      info "  ℹ No port 80 required for DNS-01 challenge"

      # Validate CF_API_TOKEN
      [[ -n "${CF_API_TOKEN:-}" ]] || die "CF_API_TOKEN required for CERT_MODE=cf_dns"
      validate_cf_api_token "${CF_API_TOKEN}" || die "Invalid CF_API_TOKEN format"

      # Ensure ACME data directory exists
      mkdir -p /var/lib/sing-box/acme 2>/dev/null || true
      ;;

    *)
      die "Unknown CERT_MODE: ${CERT_MODE} (supported: acme, cf_dns)"
      ;;
  esac

  success "ACME configuration ready (mode: ${CERT_MODE}, domain: ${DOMAIN})"
  return 0
}

# Check certificate expiration (for manual cert mode)
check_cert_expiry() {
  local cert_file="${1:-${CERT_FULLCHAIN}}"
  local expiry_date='' expiry_epoch='' now_epoch='' days_left=0
  [[ -f "${cert_file}" ]] || return 1

  expiry_date=$(openssl x509 -in "${cert_file}" -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -n "${expiry_date}" ]]; then
    expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${expiry_date}" +%s 2>/dev/null)
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
