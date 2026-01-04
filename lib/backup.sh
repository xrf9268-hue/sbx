#!/usr/bin/env bash
# lib/backup.sh - Backup and restore functionality
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_BACKUP_LOADED:-}" ]] && return 0
readonly _SBX_BACKUP_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"

# Declare external variables from common.sh
# shellcheck disable=SC2154
: "${SB_BIN:?}" "${SB_CONF:?}" "${SB_SVC:?}" "${SB_CONF_DIR:?}" "${CLIENT_INFO:?}" "${CERT_DIR_BASE:?}"
# shellcheck disable=SC2154
: "${BACKUP_PASSWORD_RANDOM_BYTES:?}" "${BACKUP_PASSWORD_LENGTH:?}" "${BACKUP_PASSWORD_MIN_LENGTH:?}"
# shellcheck disable=SC2154
: "${B:-}" "${G:-}" "${N:-}" "${Y:-}"

#==============================================================================
# Configuration
#==============================================================================

BACKUP_DIR="${BACKUP_DIR:-/var/backups/sbx}"
# BACKUP_RETENTION_DAYS is defined in lib/common.sh as readonly constant

#==============================================================================
# Backup Creation
#==============================================================================

# Create comprehensive backup of sing-box configuration
backup_create() {
  local encrypt="${1:-false}"
  local backup_name
  backup_name="sbx-backup-$(date +%Y%m%d-%H%M%S)"
  local temp_dir
  temp_dir=$(create_temp_dir "backup") || return 1
  local backup_root="${temp_dir}/${backup_name}"

  msg "Creating backup: ${backup_name}"

  # Create backup structure
  mkdir -p "${backup_root}"/{config,certificates,binary,service}

  # Backup metadata
  cat > "${backup_root}/metadata.json" <<EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "sing-box_version": "$(${SB_BIN} version 2>/dev/null | head -1 || echo 'unknown')",
  "backup_version": "1.0"
}
EOF

  # Backup configuration files
  if [[ -f "${SB_CONF}" ]]; then
    cp "${SB_CONF}" "${backup_root}/config/config.json"
    success "  ✓ Backed up configuration"
  else
    warn "  ⚠ No configuration file found"
  fi

  if [[ -f "${CLIENT_INFO}" ]]; then
    cp "${CLIENT_INFO}" "${backup_root}/config/client-info.txt"
    success "  ✓ Backed up client info"
  fi

  # Backup certificates
  local cert_found=false
  if [[ -d "${CERT_DIR_BASE}" ]]; then
    for domain_dir in "${CERT_DIR_BASE}"/*; do
      [[ -d "${domain_dir}" ]] || continue
      local domain_name
      domain_name=$(basename "${domain_dir}")

      if [[ -f "${domain_dir}/fullchain.pem" && -f "${domain_dir}/privkey.pem" ]]; then
        mkdir -p "${backup_root}/certificates/${domain_name}"
        cp "${domain_dir}/fullchain.pem" "${backup_root}/certificates/${domain_name}/"
        cp "${domain_dir}/privkey.pem" "${backup_root}/certificates/${domain_name}/"
        cert_found=true
        success "  ✓ Backed up certificates for ${domain_name}"
      fi
    done
  fi
  [[ "${cert_found}" == "false" ]] && info "  ℹ No certificates to backup"

  # Backup service file
  if [[ -f "${SB_SVC}" ]]; then
    cp "${SB_SVC}" "${backup_root}/service/sing-box.service"
    success "  ✓ Backed up systemd service"
  fi

  # Record binary version
  if [[ -f "${SB_BIN}" ]]; then
    ${SB_BIN} version > "${backup_root}/binary/sing-box-version.txt" 2>&1
    success "  ✓ Recorded binary version"
  fi

  # Create archive
  mkdir -p "${BACKUP_DIR}"
  local archive_path="${BACKUP_DIR}/${backup_name}.tar.gz"

  tar -czf "${archive_path}" -C "${temp_dir}" "${backup_name}" || die "Failed to create archive"

  # Encrypt if requested
  if [[ "${encrypt}" == "true" ]]; then
    msg "Encrypting backup..."

    local password="${BACKUP_PASSWORD:-}"
    local password_file=""

    if [[ -z "${password}" ]]; then
      # Generate cryptographically secure password with full 256-bit entropy
      # Uses constants: BACKUP_PASSWORD_RANDOM_BYTES=48, BACKUP_PASSWORD_LENGTH=64
      password=$(openssl rand -base64 "${BACKUP_PASSWORD_RANDOM_BYTES}" | tr -d '\n' | head -c "${BACKUP_PASSWORD_LENGTH}")

      # Validate password strength (minimum BACKUP_PASSWORD_MIN_LENGTH=32)
      if [[ ${#password} -lt "${BACKUP_PASSWORD_MIN_LENGTH}" ]]; then
        die "Failed to generate strong encryption password (insufficient entropy)"
      fi

      # Save password to secure key file
      local key_dir="${BACKUP_DIR}/backup-keys"
      mkdir -p "${key_dir}"
      chmod 700 "${key_dir}"

      password_file="${key_dir}/$(basename "${archive_path%.tar.gz}").key"
      echo "${password}" > "${password_file}"
      chmod 400 "${password_file}"  # Read-only for owner
      chown root:root "${password_file}" 2>/dev/null || true

      echo
      success "Backup password saved securely to:"
      echo -e "  ${B}${G}${password_file}${N}"
      warn "  Keep this file safe - you'll need it for restore!"
      echo
    else
      info "Using password from BACKUP_PASSWORD environment variable"
    fi

    openssl enc -aes-256-cbc -salt -pbkdf2 -in "${archive_path}" \
      -out "${archive_path}.enc" -k "${password}" || die "Encryption failed"

    rm "${archive_path}"
    archive_path="${archive_path}.enc"
    success "  ✓ Backup encrypted"

    if [[ -n "${password_file}" ]]; then
      info "  Password file: ${password_file}"
    fi
  fi

  # Cleanup temp directory
  rm -rf "${temp_dir}"

  # Set secure permissions
  chmod 600 "${archive_path}"

  success "Backup created: ${archive_path}"
  info "Size: $(du -h "${archive_path}" | cut -f1)"

  # Cleanup old backups
  backup_cleanup

  echo "${archive_path}"
}

#==============================================================================
# Backup Restoration
#==============================================================================

# Restore from backup
backup_restore() {
  local backup_file="$1"
  local password="${2:-}"

  [[ -f "${backup_file}" ]] || die "Backup file not found: ${backup_file}"

  msg "Restoring from backup: ${backup_file}"

  # Confirm action
  if [[ "${FORCE:-0}" != "1" ]]; then
    warn "This will OVERWRITE current configuration!"
    read -rp "Continue? [y/N]: " confirm
    [[ "${confirm}" =~ ^[Yy]$ ]] || die "Restore cancelled"
  fi

  local temp_dir
  temp_dir=$(create_temp_dir "restore") || return 1
  local rollback_dir
  rollback_dir=$(create_temp_dir "restore-rollback") || {
    rm -rf "${temp_dir}"
    return 1
  }
  local stage_dir="${temp_dir}/stage"
  mkdir -p "${stage_dir}"

  local systemctl_available=0
  local service_was_running=0
  local rollback_prepared=false
  # Track restore success explicitly to avoid rollback on unrelated exit codes
  # The EXIT trap receives the shell's final status, which may not reflect
  # restore outcome if other commands run after backup_restore() returns
  local restore_succeeded=false

  restore_cleanup() {
    # Disable errexit for cleanup operations
    set +e

    if [[ -d "${temp_dir}" ]]; then
      rm -rf "${temp_dir}"
    fi

    # Only rollback if restore was prepared but did NOT succeed
    # This prevents rolling back a successful restore when later commands fail
    if [[ "${rollback_prepared}" == "true" && "${restore_succeeded}" != "true" ]]; then
      warn "Restore failed, rolling back changes..."

      [[ -f "${rollback_dir}/config/config.json" ]] && cp -a "${rollback_dir}/config/config.json" "${SB_CONF}"
      [[ -f "${rollback_dir}/config/client-info.txt" ]] && cp -a "${rollback_dir}/config/client-info.txt" "${CLIENT_INFO}"

      if [[ -d "${rollback_dir}/certificates" ]]; then
        mkdir -p "${CERT_DIR_BASE}"
        for domain_dir in "${rollback_dir}/certificates"/*; do
          [[ -d "${domain_dir}" ]] || continue
          local domain_name
          domain_name=$(basename "${domain_dir}")
          rm -rf "${CERT_DIR_BASE:?}/${domain_name:?}"
          cp -a "${domain_dir}" "${CERT_DIR_BASE}/" 2>/dev/null || warn "Failed to restore certificates for ${domain_name}"
        done
      fi

      if [[ -f "${rollback_dir}/service/sing-box.service" ]]; then
        cp -a "${rollback_dir}/service/sing-box.service" "${SB_SVC}" 2>/dev/null || warn "Failed to restore systemd service file"
        if (( systemctl_available )); then
          systemctl daemon-reload >/dev/null 2>&1 || warn "Failed to reload systemd during rollback"
        fi
      fi

      warn "Restore failed"

      # Restart service after rollback if it was running before
      if (( systemctl_available )) && [[ ${service_was_running} -eq 1 ]]; then
        msg "Restarting sing-box service after rollback..."
        systemctl start sing-box >/dev/null 2>&1 && success "  ✓ Service restarted" || warn "  ✗ Failed to restart service"
      fi
    fi

    if [[ -d "${rollback_dir}" ]]; then
      rm -rf "${rollback_dir}"
    fi

    # Re-enable errexit
    set -e
  }
  trap 'restore_cleanup' EXIT

  # Decrypt if encrypted
  local archive_to_extract="${backup_file}"
  if [[ "${backup_file}" =~ \.enc$ ]]; then
    msg "Decrypting backup..."

    # Try to get password from various sources
    if [[ -z "${password}" ]]; then
      # Try to find corresponding key file
      local backup_basename
      backup_basename=$(basename "${backup_file}" .enc)
      local key_file="${BACKUP_DIR}/backup-keys/${backup_basename}.key"

      if [[ -f "${key_file}" ]]; then
        msg "  - Found password key file: ${key_file}"
        password=$(cat "${key_file}") || die "Failed to read password from key file"
      elif [[ -n "${BACKUP_PASSWORD:-}" ]]; then
        password="${BACKUP_PASSWORD}"
        msg "  - Using password from BACKUP_PASSWORD environment variable"
      else
        # Prompt user for password
        read -rsp "Enter backup password: " password
        echo
      fi
    fi

    [[ -n "${password}" ]] || die "No password provided for encrypted backup"

    openssl enc -aes-256-cbc -d -pbkdf2 -in "${backup_file}" \
      -out "${temp_dir}/decrypted.tar.gz" -k "${password}" || {
        rm -rf "${temp_dir}"
        die "Decryption failed (wrong password?)"
      }

    archive_to_extract="${temp_dir}/decrypted.tar.gz"
    success "  ✓ Backup decrypted"
  fi

  # Validate tar archive integrity before extraction
  msg "Validating backup archive integrity..."
  if ! tar -tzf "${archive_to_extract}" >/dev/null 2>&1; then
    rm -rf "${temp_dir}"
    die "Backup archive is corrupted or not a valid tar file"
  fi
  success "  ✓ Archive integrity validated"

  # Extract archive
  tar -xzf "${archive_to_extract}" -C "${temp_dir}" || die "Failed to extract archive"

  # Find backup root directory (securely)
  local backup_dirname
  # Use -printf %f to get only the basename, preventing path traversal
  backup_dirname=$(find "${temp_dir}" -maxdepth 1 -mindepth 1 -type d -name "sbx-backup-*" -printf "%f\n" | head -1)

  # Validate directory name exists
  if [[ -z "${backup_dirname}" ]]; then
    rm -rf "${temp_dir}"
    die "Invalid backup structure: no backup directory found"
  fi

  # Flexible validation: allow expected format with optional suffixes (prevents path traversal)
  # Expected format: sbx-backup-YYYYMMDD-HHMMSS[optional-suffix]
  # Allows timezone variations and system-generated suffixes
  if [[ ! "${backup_dirname}" =~ ^sbx-backup-[0-9]{8}-[0-9]{6}[a-zA-Z0-9._-]*$ ]]; then
    rm -rf "${temp_dir}"
    die "Invalid backup directory name: ${backup_dirname} (possible path traversal attempt)"
  fi

  # Reconstruct full path safely (no user-controlled path components)
  local backup_root="${temp_dir}/${backup_dirname}"

  # Final validation
  if [[ ! -d "${backup_root}" ]]; then
    rm -rf "${temp_dir}"
    die "Backup directory not found: ${backup_root}"
  fi

  local required_config="${backup_root}/config/config.json"
  [[ -f "${required_config}" ]] || die "Backup is missing required configuration file"

  local client_info_source="${backup_root}/config/client-info.txt"
  local service_source="${backup_root}/service/sing-box.service"

  local -a cert_domains=()
  if [[ -d "${backup_root}/certificates" ]]; then
    while IFS= read -r domain_dir; do
      [[ -d "${domain_dir}" ]] || continue
      local domain_name
      domain_name=$(basename "${domain_dir}")

      if [[ ! -f "${domain_dir}/fullchain.pem" || ! -f "${domain_dir}/privkey.pem" ]]; then
        die "Certificate set incomplete for domain: ${domain_name}"
      fi

      cert_domains+=("${domain_name}")
    done < <(find "${backup_root}/certificates" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  if [[ -n "${service_source}" && -f "${service_source}" && ! -s "${service_source}" ]]; then
    die "Service file in backup is empty"
  fi

  mkdir -p "${stage_dir}/config" "${stage_dir}/certificates" "${stage_dir}/service"
  cp "${required_config}" "${stage_dir}/config/config.json"
  [[ -f "${client_info_source}" ]] && cp "${client_info_source}" "${stage_dir}/config/client-info.txt"
  [[ -f "${service_source}" ]] && cp "${service_source}" "${stage_dir}/service/sing-box.service"

  for domain in "${cert_domains[@]}"; do
    mkdir -p "${stage_dir}/certificates/${domain}"
    cp "${backup_root}/certificates/${domain}"/*.pem "${stage_dir}/certificates/${domain}/"
  done

  if [[ -x "${SB_BIN}" ]]; then
    msg "Validating configuration..."
    ${SB_BIN} check -c "${stage_dir}/config/config.json" || die "Configuration validation failed"
  else
    warn "Cannot validate configuration: ${SB_BIN} not executable"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl_available=1
    if systemctl is-active sing-box >/dev/null 2>&1; then
      service_was_running=1
    fi
  fi

  rollback_prepared=true
  mkdir -p "${rollback_dir}/config" "${rollback_dir}/certificates" "${rollback_dir}/service"
  [[ -f "${SB_CONF}" ]] && cp -a "${SB_CONF}" "${rollback_dir}/config/config.json"
  [[ -f "${CLIENT_INFO}" ]] && cp -a "${CLIENT_INFO}" "${rollback_dir}/config/client-info.txt"
  [[ -f "${SB_SVC}" ]] && cp -a "${SB_SVC}" "${rollback_dir}/service/sing-box.service"

  for domain in "${cert_domains[@]}"; do
    local existing_cert_dir="${CERT_DIR_BASE}/${domain}"
    if [[ -d "${existing_cert_dir}" ]]; then
      mkdir -p "${rollback_dir}/certificates"
      cp -a "${existing_cert_dir}" "${rollback_dir}/certificates/"
    fi
  done

  if (( systemctl_available )) && [[ ${service_was_running} -eq 1 ]]; then
    msg "Stopping sing-box service..."
    systemctl stop sing-box >/dev/null 2>&1 || warn "  ✗ Failed to stop service"
  fi

  mkdir -p "${SB_CONF_DIR}"

  local config_tmp
  config_tmp=$(mktemp "${SB_CONF_DIR}/config.json.XXXX")
  cp "${stage_dir}/config/config.json" "${config_tmp}"
  chmod 600 "${config_tmp}"
  mv -f "${config_tmp}" "${SB_CONF}"
  success "  ✓ Restored configuration"

  if [[ -f "${stage_dir}/config/client-info.txt" ]]; then
    local client_tmp
    client_tmp=$(mktemp "${SB_CONF_DIR}/client-info.txt.XXXX")
    cp "${stage_dir}/config/client-info.txt" "${client_tmp}"
    chmod 600 "${client_tmp}"
    mv -f "${client_tmp}" "${CLIENT_INFO}"
    success "  ✓ Restored client info"
  fi

  if [[ ${#cert_domains[@]} -gt 0 ]]; then
    mkdir -p "${CERT_DIR_BASE}"
    for domain in "${cert_domains[@]}"; do
      local domain_target="${CERT_DIR_BASE}/${domain}"
      local domain_tmp
      domain_tmp=$(mktemp -d "${CERT_DIR_BASE}/${domain}.XXXX")
      cp "${stage_dir}/certificates/${domain}"/*.pem "${domain_tmp}/"
      chmod 600 "${domain_tmp}"/*.pem
      rm -rf "${domain_target}"
      mv -f "${domain_tmp}" "${domain_target}"
      success "  ✓ Restored certificates for ${domain}"
    done
  fi

  if [[ -f "${stage_dir}/service/sing-box.service" ]]; then
    local service_tmp
    service_tmp=$(mktemp "$(dirname "${SB_SVC}")/sing-box.service.XXXX")
    cp "${stage_dir}/service/sing-box.service" "${service_tmp}"
    chmod 644 "${service_tmp}"
    mv -f "${service_tmp}" "${SB_SVC}"
    if (( systemctl_available )); then
      systemctl daemon-reload >/dev/null 2>&1 || warn "  ✗ Failed to reload systemd"
    fi
    success "  ✓ Restored systemd service"
  fi

  # Mark restore as successful BEFORE clearing the trap
  # This ensures the cleanup handler knows the restore completed successfully
  restore_succeeded=true

  success "Restore completed successfully!"

  # Clear the EXIT trap now that we've succeeded - prevents rollback on
  # unrelated failures in commands that run after backup_restore() returns
  trap - EXIT

  # Perform cleanup manually for success case
  rm -rf "${temp_dir}" "${rollback_dir}"

  # Handle service start/restart for successful restore
  if (( systemctl_available )); then
    if [[ ${service_was_running} -eq 1 ]]; then
      msg "Restarting sing-box service..."
      systemctl start sing-box >/dev/null 2>&1 && success "  ✓ Service restarted" || warn "  ✗ Failed to restart service"
    elif [[ "${AUTO_START:-1}" == "1" ]]; then
      msg "Starting sing-box service..."
      systemctl start sing-box >/dev/null 2>&1 && success "  ✓ Service started" || err "  ✗ Service failed to start"
    fi
  fi
}

#==============================================================================
# Backup Management
#==============================================================================

# List available backups
backup_list() {
  [[ -d "${BACKUP_DIR}" ]] || { info "No backups found"; return 0; }

  echo -e "${B}Available Backups:${N}\n"

  local count=0
  while IFS= read -r backup_file; do
    local filename
    filename=$(basename "${backup_file}")
    local size
    size=$(du -h "${backup_file}" | cut -f1)
    local date
    date=$(get_file_mtime "${backup_file}")
    local encrypted=""
    [[ "${filename}" =~ \.enc$ ]] && encrypted=" ${Y}[encrypted]${N}"

    echo -e "  ${G}●${N} ${filename}"
    echo -e "    Size: ${size} | Date: ${date}${encrypted}"
    ((count++))
  done < <(find "${BACKUP_DIR}" -name "sbx-backup-*.tar.gz*" -type f 2>/dev/null | sort -r)

  [[ ${count} -eq 0 ]] && info "No backups found"
  echo
}

# Delete old backups based on retention policy
backup_cleanup() {
  [[ -d "${BACKUP_DIR}" ]] || return 0

  local retention_days="${BACKUP_RETENTION_DAYS:-30}"
  msg "Cleaning up old backups (retention: ${retention_days} days)..."

  local deleted=0
  while IFS= read -r old_backup; do
    rm -f "${old_backup}"
    ((deleted++))
  done < <(find "${BACKUP_DIR}" -name "sbx-backup-*.tar.gz*" -type f -mtime +"${retention_days}" 2>/dev/null)

  [[ ${deleted} -gt 0 ]] && success "  ✓ Deleted ${deleted} old backup(s)" || info "  ℹ No old backups to clean"
}

#==============================================================================
# Export Functions
#==============================================================================

export -f backup_create backup_restore backup_list backup_cleanup
