#!/usr/bin/env bash
# lib/reality_rotation.sh - Reality short ID rotation

set -euo pipefail

[[ -n "${_SBX_REALITY_ROTATION_LOADED:-}" ]] && return 0
readonly _SBX_REALITY_ROTATION_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/validation.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/service.sh"

#------------------------------------------------------------------------------
# Rotation constants
#------------------------------------------------------------------------------

declare -gr ROTATION_SERVICE_NAME="sbx-shortid-rotate.service"
declare -gr ROTATION_TIMER_NAME="sbx-shortid-rotate.timer"
declare -gr ROTATION_HISTORY_LIMIT=20

#------------------------------------------------------------------------------
# Path helpers
#------------------------------------------------------------------------------

_reality_rotation_state_file() {
  echo "${TEST_STATE_FILE:-${STATE_FILE:-${SB_CONF_DIR:-/etc/sing-box}/state.json}}"
}

_reality_rotation_client_info_file() {
  echo "${TEST_CLIENT_INFO:-${CLIENT_INFO:-${SB_CONF_DIR:-/etc/sing-box}/client-info.txt}}"
}

_reality_rotation_config_file() {
  echo "${TEST_CONFIG_FILE:-${SB_CONF:-${SB_CONF_DIR:-/etc/sing-box}/config.json}}"
}

_rotation_unit_dir() {
  echo "${TEST_SYSTEMD_DIR:-${SBX_SYSTEMD_DIR:-/etc/systemd/system}}"
}

_rotation_service_unit_path() {
  printf '%s/%s\n' "$(_rotation_unit_dir)" "${ROTATION_SERVICE_NAME}"
}

_rotation_timer_unit_path() {
  printf '%s/%s\n' "$(_rotation_unit_dir)" "${ROTATION_TIMER_NAME}"
}

_rotation_schedule_to_oncalendar() {
  local schedule="$1"

  case "${schedule}" in
    daily|weekly|monthly)
      printf '%s\n' "${schedule}"
      return 0
      ;;
    off)
      printf '\n'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_rotation_append_history() {
  local history_json="${1:-[]}"
  local short_id="$2"
  local rotated_at="$3"
  local trigger="$4"
  local history_limit="${5:-${ROTATION_HISTORY_LIMIT}}"

  jq -c \
    --arg short_id "${short_id}" \
    --arg rotated_at "${rotated_at}" \
    --arg trigger "${trigger}" \
    --argjson history_limit "${history_limit}" \
    '
    ([{short_id: $short_id, rotated_at: $rotated_at, trigger: $trigger}] +
      (if type == "array" then . else [] end))[:$history_limit]
    ' <<<"${history_json}"
}

_rotation_schedule_backup_file() {
  local source_file="$1"
  local backup_file="$2"

  if [[ -f "${source_file}" ]]; then
    cp -a "${source_file}" "${backup_file}" || return 1
  else
    rm -f "${backup_file}" 2>/dev/null || true
  fi

  return 0
}

_rotation_schedule_restore_file() {
  local backup_file="$1"
  local target_file="$2"

  if [[ -f "${backup_file}" ]]; then
    cp -a "${backup_file}" "${target_file}" || return 1
  else
    rm -f "${target_file}" 2>/dev/null || true
  fi

  return 0
}

_rotation_schedule_restore_consistency() {
  local state_backup="$1"
  local state_file="$2"
  local service_backup="$3"
  local service_unit_path="$4"
  local timer_backup="$5"
  local timer_unit_path="$6"

  _rotation_schedule_restore_file "${state_backup}" "${state_file}" || return 1
  _rotation_schedule_restore_file "${service_backup}" "${service_unit_path}" || return 1
  _rotation_schedule_restore_file "${timer_backup}" "${timer_unit_path}" || return 1

  systemctl daemon-reload >/dev/null 2>&1 || return 1

  if [[ -f "${timer_backup}" ]]; then
    systemctl enable --now "${ROTATION_TIMER_NAME}" >/dev/null 2>&1 || return 1
  else
    remove_systemd_unit "${ROTATION_TIMER_NAME}" "${timer_unit_path}" "strict" || return 1
  fi

  return 0
}

_rotation_service_unit_content() {
  cat <<'EOF'
[Unit]
Description=sbx short ID rotation service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sbx rotate-shortid --scheduled-run
EOF
}

_rotation_timer_unit_content() {
  local on_calendar="$1"

  cat <<EOF
[Unit]
Description=sbx short ID rotation timer

[Timer]
OnCalendar=${on_calendar}
Persistent=true
Unit=${ROTATION_SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF
}

_rotation_install_units() {
  local on_calendar="$1"
  local service_unit_path=''
  local timer_unit_path=''
  local service_unit_content=''
  local timer_unit_content=''

  service_unit_path=$(_rotation_service_unit_path)
  timer_unit_path=$(_rotation_timer_unit_path)
  service_unit_content=$(_rotation_service_unit_content)
  timer_unit_content=$(_rotation_timer_unit_content "${on_calendar}")

  install_systemd_unit "${service_unit_path}" "${service_unit_content}"
  install_systemd_unit "${timer_unit_path}" "${timer_unit_content}"
  systemctl enable --now "${ROTATION_TIMER_NAME}" >/dev/null 2>&1
}

reality_rotation_remove_units() {
  local service_unit_path=''
  local timer_unit_path=''

  service_unit_path=$(_rotation_service_unit_path)
  timer_unit_path=$(_rotation_timer_unit_path)

  remove_systemd_unit "${ROTATION_TIMER_NAME}" "${timer_unit_path}" "strict" || return 1
  remove_systemd_unit "${ROTATION_SERVICE_NAME}" "${service_unit_path}" "strict" || return 1
}

_rotation_write_schedule_state() {
  local state_file="$1"
  local output_file="$2"
  local schedule="$3"
  local enabled="$4"
  local on_calendar="${5:-}"
  local on_calendar_json='null'

  if [[ -n "${on_calendar}" ]]; then
    on_calendar_json=$(jq -Rn --arg value "${on_calendar}" '$value')
  fi

  jq \
    --arg schedule "${schedule}" \
    --argjson enabled "${enabled}" \
    --argjson on_calendar "${on_calendar_json}" \
    '
    .protocols.reality.short_id_rotation = (
      (.protocols.reality.short_id_rotation // {})
      | .schedule = $schedule
      | .enabled = $enabled
      | .on_calendar = $on_calendar
    )
    ' "${state_file}" >"${output_file}"
}

_reality_rotation_usage() {
  cat <<'EOF'
Usage: reality_rotate_shortid [--dry-run] [--scheduled-run]
EOF
}

_reality_rotation_read_short_id() {
  local state_file="$1"

  jq -r '.protocols.reality.short_id // empty' "${state_file}" 2>/dev/null
}

_reality_rotation_generate_short_id() {
  local current_short_id="$1"
  local attempt=0
  local candidate=''

  while [[ ${attempt} -lt 5 ]]; do
    candidate=$(openssl rand -hex 4)
    [[ "${candidate}" =~ ^[0-9a-f]{8}$ ]] || {
      attempt=$((attempt + 1))
      continue
    }
    if [[ "${candidate}" != "${current_short_id}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

_reality_rotation_write_client_info() {
  local source_file="$1"
  local target_file="$2"
  local short_id="$3"

  awk -v short_id="${short_id}" '
    BEGIN { replaced = 0 }
    /^[[:space:]]*SHORT_ID=/ {
      print "SHORT_ID=\"" short_id "\""
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) {
        print "SHORT_ID=\"" short_id "\""
      }
    }
  ' "${source_file}" >"${target_file}"
}

_reality_rotation_validate_candidate_config() {
  local config_file="$1"
  local reality_count=''
  local sb_bin="${TEST_SB_BIN:-${SB_BIN}}"

  have jq || {
    err "jq is required to validate candidate Reality configs"
    return 1
  }

  reality_count=$(jq '[.inbounds[]? | select(.tls.reality? != null)] | length' "${config_file}" 2>/dev/null)
  if [[ "${reality_count}" -lt 1 ]]; then
    err "No Reality inbound found in configuration"
    return 1
  fi

  "${sb_bin}" check -c "${config_file}" >/dev/null
}

_reality_rotation_backup_file() {
  local source_file="$1"
  local target_file="$2"

  cp -a "${source_file}" "${target_file}"
}

_reality_rotation_restore_backups() {
  local backup_dir="$1"
  local config_file="$2"
  local client_info_file="$3"
  local state_file="$4"

  [[ -f "${backup_dir}/config.json" ]] && cp -a "${backup_dir}/config.json" "${config_file}"
  [[ -f "${backup_dir}/client-info.txt" ]] && cp -a "${backup_dir}/client-info.txt" "${client_info_file}"
  [[ -f "${backup_dir}/state.json" ]] && cp -a "${backup_dir}/state.json" "${state_file}"
}

_reality_rotation_restart_service_safely() {
  (
    restart_service
  )
}

_reality_rotation_update_state() {
  local state_file="$1"
  local output_file="$2"
  local current_short_id="$3"
  local new_short_id="$4"
  local trigger="$5"
  local rotated_at="$6"
  local history=''

  history=$(
    _rotation_append_history \
      "$(jq -c '.protocols.reality.short_id_rotation.history // []' "${state_file}" 2>/dev/null || echo '[]')" \
      "${current_short_id}" \
      "${rotated_at}" \
      "${trigger}" \
      "${ROTATION_HISTORY_LIMIT}"
  )
  jq \
    --arg sid "${new_short_id}" \
    --arg old "${current_short_id}" \
    --arg trigger "${trigger}" \
    --arg rotated_at "${rotated_at}" \
    --argjson history "${history}" \
    '
    .protocols.reality.short_id = $sid
    | .protocols.reality.short_id_rotation = (
        (.protocols.reality.short_id_rotation // {})
        | .current_short_id = $sid
        | .previous_short_id = $old
        | .rotated_at = $rotated_at
        | .trigger = $trigger
        | .history = $history
      )
    ' "${state_file}" >"${output_file}"
}

_reality_rotation_update_config() {
  local config_file="$1"
  local output_file="$2"
  local short_id="$3"

  jq \
    --arg sid "${short_id}" \
    '
    (.inbounds[]? | select(.tls.reality? != null) | .tls.reality.short_id) = [$sid]
    ' "${config_file}" >"${output_file}"
}

reality_rotation_schedule() {
  with_state_lock "${SBX_LOCK_TIMEOUT_SEC:-30}" _reality_rotation_schedule_locked "$@"
}

_reality_rotation_schedule_locked() {
  local schedule="${1:-}"
  local state_file=''
  local state_tmp=''
  local on_calendar=''
  local backup_dir=''
  local state_backup=''
  local service_unit_path=''
  local timer_unit_path=''
  local service_backup=''
  local timer_backup=''

  if [[ $# -ne 1 ]]; then
    err "Usage: reality_rotation_schedule <daily|weekly|monthly|off>"
    return 1
  fi

  case "${schedule}" in
    daily|weekly|monthly)
      on_calendar=$(_rotation_schedule_to_oncalendar "${schedule}") || {
        err "Invalid schedule value: ${schedule}"
        return 1
      }
      ;;
    off)
      on_calendar=''
      ;;
    *)
      err "Invalid schedule value: ${schedule}"
      return 1
      ;;
  esac

  state_file=$(_reality_rotation_state_file)
  service_unit_path=$(_rotation_service_unit_path)
  timer_unit_path=$(_rotation_timer_unit_path)
  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }

  backup_dir=$(create_temp_dir "reality-schedule") || return 1
  state_backup="${backup_dir}/state.json"
  service_backup="${backup_dir}/$(basename "${service_unit_path}")"
  timer_backup="${backup_dir}/$(basename "${timer_unit_path}")"

  _rotation_schedule_backup_file "${state_file}" "${state_backup}"
  _rotation_schedule_backup_file "${service_unit_path}" "${service_backup}"
  _rotation_schedule_backup_file "${timer_unit_path}" "${timer_backup}"

  state_tmp=$(create_temp_file_in_dir "$(dirname "${state_file}")" "state.json") || return 1

  if [[ "${schedule}" == "off" ]]; then
    reality_rotation_remove_units || {
      rm -f "${state_tmp}" 2>/dev/null || true
      _rotation_schedule_restore_consistency "${state_backup}" "${state_file}" "${service_backup}" "${service_unit_path}" "${timer_backup}" "${timer_unit_path}"
      rm -rf "${backup_dir}" 2>/dev/null || true
      return 1
    }
    _rotation_write_schedule_state "${state_file}" "${state_tmp}" "${schedule}" false "${on_calendar}" || {
      rm -f "${state_tmp}" 2>/dev/null || true
      _rotation_schedule_restore_consistency "${state_backup}" "${state_file}" "${service_backup}" "${service_unit_path}" "${timer_backup}" "${timer_unit_path}"
      rm -rf "${backup_dir}" 2>/dev/null || true
      return 1
    }
  else
    _rotation_install_units "${on_calendar}" || {
      rm -f "${state_tmp}" 2>/dev/null || true
      _rotation_schedule_restore_consistency "${state_backup}" "${state_file}" "${service_backup}" "${service_unit_path}" "${timer_backup}" "${timer_unit_path}"
      rm -rf "${backup_dir}" 2>/dev/null || true
      return 1
    }
    _rotation_write_schedule_state "${state_file}" "${state_tmp}" "${schedule}" true "${on_calendar}" || {
      rm -f "${state_tmp}" 2>/dev/null || true
      _rotation_schedule_restore_consistency "${state_backup}" "${state_file}" "${service_backup}" "${service_unit_path}" "${timer_backup}" "${timer_unit_path}"
      rm -rf "${backup_dir}" 2>/dev/null || true
      return 1
    }
  fi

  if ! mv -f "${state_tmp}" "${state_file}"; then
    rm -f "${state_tmp}" 2>/dev/null || true
    _rotation_schedule_restore_consistency "${state_backup}" "${state_file}" "${service_backup}" "${service_unit_path}" "${timer_backup}" "${timer_unit_path}"
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  fi

  rm -rf "${backup_dir}" 2>/dev/null || true
}

_reality_rotate_shortid_locked() {
  local dry_run=0
  local scheduled_run=0
  local arg=''
  local state_file=''
  local config_file=''
  local client_info_file=''
  local current_short_id=''
  local new_short_id=''
  local trigger='manual'
  local rotated_at=''
  local backup_dir=''
  local config_tmp=''
  local client_tmp=''
  local state_tmp=''
  local subscription_enabled='false'

  while [[ $# -gt 0 ]]; do
    arg="$1"
    shift
    case "${arg}" in
      --dry-run)
        dry_run=1
        ;;
      --scheduled-run)
        scheduled_run=1
        ;;
      --help|-h)
        _reality_rotation_usage
        return 0
        ;;
      *)
        err "Unknown argument: ${arg}"
        _reality_rotation_usage
        return 1
        ;;
    esac
  done

  if [[ "${scheduled_run}" -eq 1 ]]; then
    trigger='timer'
  fi

  state_file=$(_reality_rotation_state_file)
  config_file=$(_reality_rotation_config_file)
  client_info_file=$(_reality_rotation_client_info_file)

  [[ -f "${state_file}" ]] || {
    err "state.json not found: ${state_file}"
    return 1
  }
  [[ -f "${config_file}" ]] || {
    err "config.json not found: ${config_file}"
    return 1
  }
  [[ -f "${client_info_file}" ]] || {
    err "client-info.txt not found: ${client_info_file}"
    return 1
  }

  current_short_id=$(_reality_rotation_read_short_id "${state_file}")
  [[ -n "${current_short_id}" ]] || {
    err "Current Reality short ID is missing from state.json"
    return 1
  }
  [[ "${current_short_id}" =~ ^[0-9a-fA-F]{1,8}$ ]] || {
    err "Current Reality short ID is invalid: ${current_short_id}"
    return 1
  }

  new_short_id=$(_reality_rotation_generate_short_id "${current_short_id}") || {
    err "Failed to generate a new Reality short ID"
    return 1
  }

  rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  backup_dir=$(create_temp_dir "reality-rotate") || return 1
  config_tmp=$(create_temp_file_in_dir "$(dirname "${config_file}")" "config.json") || {
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }
  client_tmp=$(create_temp_file_in_dir "$(dirname "${client_info_file}")" "client-info.txt") || {
    rm -f "${config_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }
  state_tmp=$(create_temp_file_in_dir "$(dirname "${state_file}")" "state.json") || {
    rm -f "${config_tmp}" "${client_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }

  _reality_rotation_update_config "${config_file}" "${config_tmp}" "${new_short_id}" || {
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }
  _reality_rotation_write_client_info "${client_info_file}" "${client_tmp}" "${new_short_id}" || {
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }
  _reality_rotation_update_state "${state_file}" "${state_tmp}" "${current_short_id}" "${new_short_id}" "${trigger}" "${rotated_at}" || {
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }

  _reality_rotation_validate_candidate_config "${config_tmp}" || {
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  }

  if [[ "${dry_run}" -eq 1 ]]; then
    msg "Reality short ID rotation dry run"
    msg "  current: ${current_short_id}"
    msg "  new:     ${new_short_id}"
    msg "  trigger:  ${trigger}"
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 0
  fi

  _reality_rotation_backup_file "${config_file}" "${backup_dir}/config.json"
  _reality_rotation_backup_file "${client_info_file}" "${backup_dir}/client-info.txt"
  _reality_rotation_backup_file "${state_file}" "${backup_dir}/state.json"

  if ! {
    mv -f "${config_tmp}" "${config_file}" &&
      mv -f "${client_tmp}" "${client_info_file}" &&
      mv -f "${state_tmp}" "${state_file}"
  }; then
    warn "Failed to commit rotation changes, restoring previous files"
    _reality_rotation_restore_backups "${backup_dir}" "${config_file}" "${client_info_file}" "${state_file}"
    rm -f "${config_tmp}" "${client_tmp}" "${state_tmp}" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  fi

  if ! _reality_rotation_restart_service_safely; then
    warn "Service restart failed, restoring previous Reality short ID"
    _reality_rotation_restore_backups "${backup_dir}" "${config_file}" "${client_info_file}" "${state_file}"
    if ! _reality_rotation_restart_service_safely; then
      warn "Failed to restart sing-box after restoring previous files"
      rm -rf "${backup_dir}" 2>/dev/null || true
      return 1
    fi
    rm -rf "${backup_dir}" 2>/dev/null || true
    return 1
  fi

  if declare -f subscription_refresh_cache >/dev/null 2>&1; then
    subscription_enabled=$(jq -r '.subscription.enabled // false' "${state_file}" 2>/dev/null || echo false)
    if [[ "${subscription_enabled}" == "true" ]]; then
      subscription_refresh_cache >/dev/null 2>&1 || true
    fi
  fi

  rm -rf "${backup_dir}" 2>/dev/null || true
  success "Reality short ID rotated: ${current_short_id} -> ${new_short_id}"
  return 0
}

reality_rotate_shortid() {
  local arg=''

  with_state_lock "${SBX_LOCK_TIMEOUT_SEC:-30}" _reality_rotate_shortid_locked "$@"
}

export -f reality_rotate_shortid
export -f reality_rotation_schedule reality_rotation_remove_units
