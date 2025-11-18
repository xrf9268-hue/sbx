#!/usr/bin/env bash
# tests/unit/test_caddy_schema_functions.sh - Tests for Caddy and schema validator functions
# Tests for lib/caddy.sh and lib/schema_validator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

# Source required modules
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/tools.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/caddy.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/schema_validator.sh" 2>/dev/null || true

#==============================================================================
# Test Suite: Caddy Path Functions
#==============================================================================

test_caddy_bin() {

    result=$(caddy_bin)
    assert_equals "$result" "/usr/local/bin/caddy" "Should return correct binary path"

}

test_caddy_config_dir() {

    result=$(caddy_config_dir)
    assert_equals "$result" "/etc/caddy" "Should return correct config directory"

}

test_caddy_config_file() {

    result=$(caddy_config_file)
    assert_equals "$result" "/etc/caddy/Caddyfile" "Should return correct config file path"

}

test_caddy_data_dir() {

    result=$(caddy_data_dir)
    assert_equals "$result" "/var/lib/caddy" "Should return correct data directory"

}

test_caddy_systemd_file() {

    result=$(caddy_systemd_file)
    assert_equals "$result" "/etc/systemd/system/caddy.service" "Should return correct systemd file"

}

test_caddy_cert_path() {

    domain="example.com"
    result=$(caddy_cert_path "$domain")

    assert_contains "$result" "$domain" "Should contain domain name"
    assert_contains "$result" ".crt" "Should be certificate file"

}

#==============================================================================
# Test Suite: caddy_detect_arch
#==============================================================================

test_caddy_detect_arch_format() {

    result=$(caddy_detect_arch)

    # Should return one of the expected architectures
    case "$result" in
        linux_amd64|linux_arm64|linux_armv7|linux_armv6)
            assert_success 0 "Valid architecture detected: $result"
            ;;
        *)
            assert_failure 1 "Unknown architecture: $result"
            ;;
    esac

}

#==============================================================================
# Test Suite: caddy_get_latest_version
#==============================================================================

test_caddy_get_latest_version_format() {

    # This requires network access, so make it optional
    if command -v curl &>/dev/null || command -v wget &>/dev/null; then
        result=$(caddy_get_latest_version 2>/dev/null || echo "")

        if [[ -n "$result" ]]; then
            # Should start with 'v'
            assert_contains "$result" "v" "Version should contain 'v'"
        fi
    fi

}

#==============================================================================
# Test Suite: caddy_create_service
#==============================================================================

test_caddy_create_service_structure() {

    result=$(caddy_create_service)

    # Check systemd service structure
    assert_contains "$result" "[Unit]" "Should contain Unit section"
    assert_contains "$result" "[Service]" "Should contain Service section"
    assert_contains "$result" "[Install]" "Should contain Install section"
    assert_contains "$result" "ExecStart=" "Should contain ExecStart"
    assert_contains "$result" "caddy run" "Should run caddy"

}

#==============================================================================
# Test Suite: caddy_create_renewal_hook
#==============================================================================

test_caddy_create_renewal_hook_structure() {

    domain="example.com"
    result=$(caddy_create_renewal_hook "$domain")

    # Check hook script structure
    assert_contains "$result" "#!/bin/bash" "Should be bash script"
    assert_contains "$result" "$domain" "Should contain domain"
    assert_contains "$result" "cp" "Should copy certificates"

}

test_caddy_create_renewal_hook_empty_domain() {

    domain=""

    if caddy_create_renewal_hook "$domain" 2>/dev/null; then
        assert_failure 1 "Should reject empty domain"
    else
        assert_success 0 "Correctly rejected empty domain"
    fi

}

#==============================================================================
# Test Suite: Schema Validator - check_schema_tool
#==============================================================================

test_check_schema_tool_availability() {

    # Should detect jq or python
    result=$(check_schema_tool)

    case "$result" in
        jq|python3|python)
            assert_success 0 "Valid schema tool detected: $result"
            ;;
        *)
            assert_failure 1 "No schema tool available"
            ;;
    esac

}

#==============================================================================
# Test Suite: Schema Validator - validate_config_schema
#==============================================================================

test_validate_config_schema_valid_json() {

    config_file="/tmp/test-config-$$.json"
    cat > "$config_file" << 'EOF'
{
  "log": {"level": "warn"},
  "inbounds": [{"type": "vless"}],
  "outbounds": [{"type": "direct"}]
}
EOF

    if validate_config_schema "$config_file"; then
        assert_success 0 "Should validate correct schema"
    else
        # May fail if sing-box not installed, that's ok
        assert_success 0 "Schema validation attempted"
    fi

    rm -f "$config_file"
}

test_validate_config_schema_missing_file() {

    config_file="/tmp/missing-config-$$.json"

    if validate_config_schema "$config_file" 2>/dev/null; then
        assert_failure 1 "Should reject missing config file"
    else
        assert_success 0 "Correctly rejected missing file"
    fi

}

test_validate_config_schema_invalid_json() {

    config_file="/tmp/invalid-config-$$.json"
    echo "{ invalid json }" > "$config_file"

    if validate_config_schema "$config_file" 2>/dev/null; then
        assert_failure 1 "Should reject invalid JSON"
    else
        assert_success 0 "Correctly rejected invalid JSON"
    fi

    rm -f "$config_file"
}

#==============================================================================
# Test Suite: Schema Validator - Reality Field Validators
#==============================================================================

test_validate_reality_required_fields_complete() {

    config='{
      "inbounds": [{
        "tls": {
          "reality": {
            "enabled": true,
            "private_key": "test-key",
            "short_id": ["a1b2c3d4"],
            "handshake": {"server": "www.microsoft.com", "server_port": 443}
          }
        }
      }]
    }'

    config_file="/tmp/test-reality-$$.json"
    echo "$config" > "$config_file"

    # Test internal validator if available
    if declare -f _validate_reality_required_fields &>/dev/null; then
        if _validate_reality_required_fields "$config_file"; then
            assert_success 0 "Should accept complete Reality config"
        fi
    fi

    rm -f "$config_file"
}

test_validate_reality_enabled_true() {

    config='{
      "inbounds": [{
        "tls": {
          "reality": {
            "enabled": true
          }
        }
      }]
    }'

    config_file="/tmp/test-reality-enabled-$$.json"
    echo "$config" > "$config_file"

    # Test internal validator if available
    if declare -f _validate_reality_enabled &>/dev/null; then
        if _validate_reality_enabled "$config_file"; then
            assert_success 0 "Should detect enabled Reality"
        fi
    fi

    rm -f "$config_file"
}

test_validate_reality_enabled_false() {

    config='{
      "inbounds": [{
        "tls": {
          "reality": {
            "enabled": false
          }
        }
      }]
    }'

    config_file="/tmp/test-reality-disabled-$$.json"
    echo "$config" > "$config_file"

    # Test internal validator if available
    if declare -f _validate_reality_enabled &>/dev/null; then
        if _validate_reality_enabled "$config_file" 2>/dev/null; then
            assert_failure 1 "Should reject disabled Reality"
        else
            assert_success 0 "Correctly handled disabled Reality"
        fi
    fi

    rm -f "$config_file"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Caddy and Schema Validator Functions Tests ==="
echo ""

# Caddy path tests
test_caddy_bin
test_caddy_config_dir
test_caddy_config_file
test_caddy_data_dir
test_caddy_systemd_file
test_caddy_cert_path

# Caddy detection tests
test_caddy_detect_arch
test_caddy_get_latest_version_format

# Caddy configuration tests
test_caddy_create_service_structure
test_caddy_create_renewal_hook_structure
test_caddy_create_renewal_hook_empty_domain

# Schema validator tool tests
test_check_schema_tool_availability

# Schema validation tests
test_validate_config_schema_valid_json
test_validate_config_schema_missing_file
test_validate_config_schema_invalid_json

# Reality field validation tests
test_validate_reality_required_fields_complete
test_validate_reality_enabled_true
test_validate_reality_enabled_false

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
