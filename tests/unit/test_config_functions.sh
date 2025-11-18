#!/usr/bin/env bash
# tests/unit/test_config_functions.sh - Comprehensive configuration function tests
# Tests for lib/config.sh functions

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
source "$PROJECT_ROOT/lib/generators.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/config.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/tools.sh"

#==============================================================================
# Test Suite: validate_config_vars
#==============================================================================

test_validate_config_vars_success() {
    # Set all required variables
    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key-12345678901234567890123456"
    SID="a1b2c3d4"
    DOMAIN="192.168.1.1"

    # Should succeed
    if validate_config_vars "$UUID" "$PRIV" "$SID" "$DOMAIN"; then
        assert_not_empty "$UUID" "validate_config_vars should succeed with valid inputs"
    else
        echo "✗ validate_config_vars failed unexpectedly"
        return 1
    fi
}

test_validate_config_vars_empty_uuid() {
    setup_test_env

    UUID=""
    PRIV="test-private-key"
    SID="a1b2c3d4"
    DOMAIN="192.168.1.1"

    # Should fail with empty UUID
    if validate_config_vars "$UUID" "$PRIV" "$SID" "$DOMAIN" 2>/dev/null; then
        assert_failure 1 "Should reject empty UUID"
    else
        assert_success 0 "Correctly rejected empty UUID"
    fi

    teardown_test_env
}

test_validate_config_vars_empty_private_key() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV=""
    SID="a1b2c3d4"
    DOMAIN="192.168.1.1"

    # Should fail with empty private key
    if validate_config_vars "$UUID" "$PRIV" "$SID" "$DOMAIN" 2>/dev/null; then
        assert_failure 1 "Should reject empty private key"
    else
        assert_success 0 "Correctly rejected empty private key"
    fi

    teardown_test_env
}

test_validate_config_vars_empty_short_id() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key"
    SID=""
    DOMAIN="192.168.1.1"

    # Should fail with empty short ID
    if validate_config_vars "$UUID" "$PRIV" "$SID" "$DOMAIN" 2>/dev/null; then
        assert_failure 1 "Should reject empty short ID"
    else
        assert_success 0 "Correctly rejected empty short ID"
    fi

    teardown_test_env
}

test_validate_config_vars_empty_domain() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key"
    SID="a1b2c3d4"
    DOMAIN=""

    # Should fail with empty domain
    if validate_config_vars "$UUID" "$PRIV" "$SID" "$DOMAIN" 2>/dev/null; then
        assert_failure 1 "Should reject empty domain"
    else
        assert_success 0 "Correctly rejected empty domain"
    fi

    teardown_test_env
}

#==============================================================================
# Test Suite: create_reality_inbound
#==============================================================================

test_create_reality_inbound_basic() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    PRIV="test-private-key-12345678901234567890123456"
    SID="a1b2c3d4"
    DOMAIN="www.microsoft.com"
    REALITY_PORT="443"

    result=$(create_reality_inbound "$UUID" "$PRIV" "$SID" "$DOMAIN" "$REALITY_PORT")

    # Check for required JSON structure
    assert_contains "$result" '"type": "vless"' "Should contain VLESS type"
    assert_contains "$result" '"tag": "in-reality"' "Should contain reality tag"
    assert_contains "$result" '"listen_port": 443' "Should contain correct port"
    assert_contains "$result" '"uuid": "a1b2c3d4-e5f6-7890-1234-567890abcdef"' "Should contain UUID"
    assert_contains "$result" '"flow": "xtls-rprx-vision"' "Should contain vision flow"
    assert_contains "$result" '"reality":' "Should contain reality section"
    assert_contains "$result" '"private_key": "test-private-key-12345678901234567890123456"' "Should contain private key"
    assert_contains "$result" '"short_id": ["a1b2c3d4"]' "Should contain short ID array"

    teardown_test_env
}

test_create_reality_inbound_custom_port() {
    setup_test_env

    UUID="test-uuid"
    PRIV="test-priv"
    SID="12345678"
    DOMAIN="example.com"
    REALITY_PORT="8443"

    result=$(create_reality_inbound "$UUID" "$PRIV" "$SID" "$DOMAIN" "$REALITY_PORT")

    assert_contains "$result" '"listen_port": 8443' "Should use custom port"

    teardown_test_env
}

#==============================================================================
# Test Suite: add_outbound_config
#==============================================================================

test_add_outbound_config() {
    setup_test_env

    result=$(add_outbound_config)

    # Check for outbound structure
    assert_contains "$result" '"type": "direct"' "Should contain direct outbound"
    assert_contains "$result" '"tag": "direct"' "Should contain direct tag"
    assert_contains "$result" '"tcp_fast_open": true' "Should enable TCP Fast Open"

    teardown_test_env
}

#==============================================================================
# Test Suite: add_route_config
#==============================================================================

test_add_route_config() {
    setup_test_env

    result=$(add_route_config)

    # Check for route structure
    assert_contains "$result" '"rules":' "Should contain rules array"
    assert_contains "$result" '"protocol": ["dns"]' "Should contain DNS protocol rule"
    assert_contains "$result" '"outbound": "dns-out"' "Should contain DNS outbound"

    teardown_test_env
}

#==============================================================================
# Test Suite: create_ws_inbound
#==============================================================================

test_create_ws_inbound() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    WS_PORT="8444"
    WS_PATH="/ws-path"
    CERT_FULLCHAIN="/tmp/cert.pem"
    CERT_KEY="/tmp/key.pem"

    # Create dummy cert files
    touch "$CERT_FULLCHAIN" "$CERT_KEY"

    result=$(create_ws_inbound "$UUID" "$WS_PORT" "$WS_PATH" "$CERT_FULLCHAIN" "$CERT_KEY")

    # Check for WebSocket structure
    assert_contains "$result" '"type": "vless"' "Should contain VLESS type"
    assert_contains "$result" '"tag": "in-ws"' "Should contain WS tag"
    assert_contains "$result" '"listen_port": 8444' "Should contain correct port"
    assert_contains "$result" '"transport":' "Should contain transport section"
    assert_contains "$result" '"type": "ws"' "Should contain WS transport type"
    assert_contains "$result" '"path": "/ws-path"' "Should contain WS path"
    assert_contains "$result" '"tls":' "Should contain TLS section"
    assert_contains "$result" '"enabled": true' "Should enable TLS"

    # Cleanup
    rm -f "$CERT_FULLCHAIN" "$CERT_KEY"

    teardown_test_env
}

#==============================================================================
# Test Suite: create_hysteria2_inbound
#==============================================================================

test_create_hysteria2_inbound() {
    setup_test_env

    UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
    HY2_PORT="8443"
    CERT_FULLCHAIN="/tmp/hy2_cert.pem"
    CERT_KEY="/tmp/hy2_key.pem"

    # Create dummy cert files
    touch "$CERT_FULLCHAIN" "$CERT_KEY"

    result=$(create_hysteria2_inbound "$UUID" "$HY2_PORT" "$CERT_FULLCHAIN" "$CERT_KEY")

    # Check for Hysteria2 structure
    assert_contains "$result" '"type": "hysteria2"' "Should contain hysteria2 type"
    assert_contains "$result" '"tag": "in-hy2"' "Should contain hy2 tag"
    assert_contains "$result" '"listen_port": 8443' "Should contain correct port"
    assert_contains "$result" '"users":' "Should contain users array"
    assert_contains "$result" '"password": "a1b2c3d4-e5f6-7890-1234-567890abcdef"' "Should use UUID as password"
    assert_contains "$result" '"tls":' "Should contain TLS section"

    # Cleanup
    rm -f "$CERT_FULLCHAIN" "$CERT_KEY"

    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Configuration Functions Tests ==="
echo ""

# validate_config_vars tests
test_validate_config_vars_success
test_validate_config_vars_empty_uuid
test_validate_config_vars_empty_private_key
test_validate_config_vars_empty_short_id
test_validate_config_vars_empty_domain

# create_reality_inbound tests
test_create_reality_inbound_basic
test_create_reality_inbound_custom_port

# outbound and route tests
test_add_outbound_config
test_add_route_config

# multi-protocol inbound tests
test_create_ws_inbound
test_create_hysteria2_inbound

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
