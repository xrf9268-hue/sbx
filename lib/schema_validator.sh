#!/usr/bin/env bash
# lib/schema_validator.sh - JSON Schema validation for sing-box configurations
#
# This module provides JSON schema validation for Reality configurations
# based on official sing-box 1.12.0+ standards.
#
# Functions:
#   - validate_config_schema: Validate configuration against JSON schema
#   - validate_reality_structure: Manual Reality structure validation
#   - check_schema_tool: Check for available schema validation tools

# Strict mode for error handling and safety
set -euo pipefail

[[ -n "${_SBX_SCHEMA_VALIDATOR_LOADED:-}" ]] && return 0
readonly _SBX_SCHEMA_VALIDATOR_LOADED=1

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load dependencies
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

#==============================================================================
# Schema Validation Constants
#==============================================================================

readonly REALITY_SCHEMA_FILE="${PROJECT_ROOT}/schema/reality-config.schema.json"

#==============================================================================
# Schema Tool Detection
#==============================================================================

# Check for available JSON schema validation tools
#
# Checks for: ajv-cli, jsonschema (Python), jq (manual validation)
#
# Returns:
#   0 if at least one tool available
#   1 if no validation tools found
#
# Outputs:
#   Name of available tool or "none"
#
check_schema_tool() {
  # Check for ajv-cli (Node.js based, most robust)
  if have ajv; then
    echo "ajv"
    return 0
  fi

  # Check for Python jsonschema
  if have jsonschema 2>/dev/null; then
    echo "jsonschema"
    return 0
  fi

  # Fallback to jq for manual validation
  if have jq; then
    echo "jq"
    return 0
  fi

  echo "none"
  return 1
}

#==============================================================================
# Schema Validation Functions
#==============================================================================

# Validate configuration file against JSON schema
#
# Args:
#   $1 - Path to configuration file
#
# Returns:
#   0 if validation passes
#   1 if validation fails
#
# Example:
#   validate_config_schema /etc/sing-box/config.json
#
validate_config_schema() {
  local config_file="${1:-}"

  # Validate arguments
  if [[ -z "$config_file" ]]; then
    err "validate_config_schema: config_file parameter required"
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    err "Configuration file not found: $config_file"
    return 1
  fi

  if [[ ! -f "$REALITY_SCHEMA_FILE" ]]; then
    warn "Schema file not found: $REALITY_SCHEMA_FILE"
    warn "Skipping schema validation"
    return 0
  fi

  msg "Validating configuration schema..."

  # Validate JSON syntax first
  if ! jq empty "$config_file" 2>/dev/null; then
    err "Invalid JSON syntax in configuration file"
    return 1
  fi

  # Detect available validation tool
  local tool
  tool=$(check_schema_tool)

  case "$tool" in
    ajv)
      # Use ajv-cli for validation
      debug "Using ajv-cli for schema validation"
      if ajv validate -s "$REALITY_SCHEMA_FILE" -d "$config_file" 2>&1; then
        success "Schema validation passed (ajv)"
        return 0
      else
        err "Schema validation failed (ajv)"
        return 1
      fi
      ;;

    jsonschema)
      # Use Python jsonschema
      debug "Using Python jsonschema for validation"
      if jsonschema -i "$config_file" "$REALITY_SCHEMA_FILE" 2>&1; then
        success "Schema validation passed (jsonschema)"
        return 0
      else
        err "Schema validation failed (jsonschema)"
        return 1
      fi
      ;;

    jq)
      # Fallback to manual jq-based validation
      debug "Using jq for manual schema validation"
      if validate_reality_structure "$config_file"; then
        success "Schema validation passed (jq manual)"
        return 0
      else
        err "Schema validation failed (jq manual)"
        return 1
      fi
      ;;

    none)
      warn "No schema validation tools available (ajv, jsonschema, or jq)"
      warn "Skipping schema validation"
      return 0
      ;;

    *)
      warn "Unknown schema validation tool: $tool"
      return 0
      ;;
  esac
}

#==============================================================================
# Reality Structure Validation Helpers
#==============================================================================

# Validate Reality and TLS enabled flags
_validate_reality_enabled() {
  local config_file="$1"
  local validation_failed=0

  # Check Reality enabled flag
  local reality_enabled
  reality_enabled=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.enabled' "$config_file" 2>/dev/null | head -1)
  if [[ "$reality_enabled" != "true" ]]; then
    err "  ✗ Reality enabled flag not set to true"
    validation_failed=1
  else
    msg "  ✓ Reality enabled flag set correctly"
  fi

  # Check TLS enabled when Reality is present
  local tls_enabled
  tls_enabled=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.enabled' "$config_file" 2>/dev/null | head -1)
  if [[ "$tls_enabled" != "true" ]]; then
    err "  ✗ TLS must be enabled when using Reality"
    validation_failed=1
  else
    msg "  ✓ TLS enabled for Reality"
  fi

  return $validation_failed
}

# Validate Reality required fields presence and proper nesting
_validate_reality_required_fields() {
  local config_file="$1"
  local validation_failed=0

  # Check Reality is nested under tls, not top-level
  if jq -e '.inbounds[].reality' "$config_file" >/dev/null 2>&1; then
    err "  ✗ Reality configuration is at top level (should be under tls.reality)"
    validation_failed=1
  else
    msg "  ✓ Reality properly nested under tls.reality"
  fi

  # Check required Reality fields present
  local required_fields=("private_key" "short_id" "handshake")
  local fields_ok=1
  for field in "${required_fields[@]}"; do
    if ! jq -e ".inbounds[] | select(.tls.reality) | .tls.reality.${field}" "$config_file" >/dev/null 2>&1; then
      err "  ✗ Missing required Reality field: $field"
      validation_failed=1
      fields_ok=0
    fi
  done
  if [[ $fields_ok -eq 1 ]]; then
    msg "  ✓ All required Reality fields present"
  fi

  return $validation_failed
}

# Validate Reality field types
_validate_reality_field_types() {
  local config_file="$1"
  local validation_failed=0

  # Check Short ID is array format
  local sid_type
  sid_type=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.short_id | type' "$config_file" 2>/dev/null | head -1)
  if [[ "$sid_type" != "array" ]]; then
    err "  ✗ Short ID must be array format, got: $sid_type"
    validation_failed=1
  else
    msg "  ✓ Short ID in correct array format"
  fi

  return $validation_failed
}

# Validate Reality field values
_validate_reality_field_values() {
  local config_file="$1"
  local validation_failed=0

  # Check Short ID length (1-8 hex characters)
  local short_ids
  short_ids=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.short_id[]?' "$config_file" 2>/dev/null)
  if [[ -n "$short_ids" ]]; then
    local sid_ok=1
    while IFS= read -r sid; do
      if [[ ! "$sid" =~ ^[0-9a-fA-F]{1,8}$ ]]; then
        err "  ✗ Invalid short ID format: $sid (must be 1-8 hex chars)"
        validation_failed=1
        sid_ok=0
      fi
    done <<< "$short_ids"
    if [[ $sid_ok -eq 1 ]]; then
      msg "  ✓ All short IDs valid (1-8 hex characters)"
    fi
  fi

  # Check Flow field in users array
  local flow
  flow=$(jq -r '.inbounds[] | select(.tls.reality) | .users[]?.flow?' "$config_file" 2>/dev/null | head -1)
  if [[ "$flow" == "xtls-rprx-vision" ]]; then
    msg "  ✓ Flow field set to xtls-rprx-vision"
  elif [[ -z "$flow" || "$flow" == "null" ]]; then
    warn "  ⚠ Flow field not set (Vision protocol requires xtls-rprx-vision)"
  else
    err "  ✗ Invalid flow value: $flow"
    validation_failed=1
  fi

  # Check Handshake configuration
  if jq -e '.inbounds[] | select(.tls.reality) | .tls.reality.handshake' "$config_file" >/dev/null 2>&1; then
    local handshake_server
    handshake_server=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.handshake.server' "$config_file" 2>/dev/null | head -1)
    if [[ -z "$handshake_server" || "$handshake_server" == "null" ]]; then
      err "  ✗ Handshake server not configured"
      validation_failed=1
    else
      msg "  ✓ Handshake server configured: $handshake_server"
    fi

    local handshake_port
    handshake_port=$(jq -r '.inbounds[] | select(.tls.reality) | .tls.reality.handshake.server_port' "$config_file" 2>/dev/null | head -1)
    if [[ -z "$handshake_port" || "$handshake_port" == "null" ]]; then
      err "  ✗ Handshake server_port not configured"
      validation_failed=1
    else
      msg "  ✓ Handshake server_port configured: $handshake_port"
    fi
  fi

  return $validation_failed
}

# Manual Reality structure validation using jq
#
# Performs critical Reality-specific validation checks when
# proper schema validation tools (ajv/jsonschema) are unavailable.
#
# Args:
#   $1 - Path to configuration file
#
# Returns:
#   0 if validation passes
#   1 if validation fails
#
# Example:
#   validate_reality_structure /etc/sing-box/config.json
#
validate_reality_structure() {
  local config_file="${1:-}"

  if [[ -z "$config_file" ]]; then
    err "validate_reality_structure: config_file parameter required"
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    err "Configuration file not found: $config_file"
    return 1
  fi

  if ! have jq; then
    warn "jq not available, skipping manual structure validation"
    return 0
  fi

  # Check if Reality configuration exists
  if ! jq -e '.inbounds[].tls.reality' "$config_file" >/dev/null 2>&1; then
    warn "No Reality configuration found in inbounds"
    return 0  # Not a failure - config might not use Reality
  fi

  msg "  ✓ Reality configuration detected"

  # Run all validation checks
  _validate_reality_enabled "$config_file" || return 1
  _validate_reality_required_fields "$config_file" || return 1
  _validate_reality_field_types "$config_file" || return 1
  _validate_reality_field_values "$config_file" || return 1

  success "Reality structure validation passed"
  return 0
}

# Export functions for use in other modules
export -f check_schema_tool
export -f validate_config_schema
export -f validate_reality_structure
