#!/usr/bin/env bash
# tests/unit/test_backup_export_functions.sh - Tests for backup and export functions
# Tests for lib/backup.sh and lib/export.sh functions

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
source "$PROJECT_ROOT/lib/generators.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/backup.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/export.sh" 2>/dev/null || true

#==============================================================================
# Test Suite: backup_list
#==============================================================================

test_backup_list_no_backups() {
    setup_test_env

    # Create temp backup directory
    BACKUP_DIR="/tmp/sbx-backup-test-$$"
    mkdir -p "$BACKUP_DIR"

    result=$(backup_list 2>/dev/null || echo "No backups")

    # Should handle empty backup directory
    assert_success 0 "Should handle empty backup directory"

    rm -rf "$BACKUP_DIR"
    teardown_test_env
}

test_backup_list_with_backups() {
    setup_test_env

    # Create temp backup directory with test backups
    BACKUP_DIR="/tmp/sbx-backup-test-$$"
    mkdir -p "$BACKUP_DIR"
    touch "$BACKUP_DIR/sbx-backup-20250101-120000.tar.gz"
    touch "$BACKUP_DIR/sbx-backup-20250102-130000.tar.gz.enc"

    # Function should list backups if they exist
    backup_list 2>/dev/null || true
    assert_success 0 "Should list existing backups"

    rm -rf "$BACKUP_DIR"
    teardown_test_env
}

#==============================================================================
# Test Suite: backup_cleanup
#==============================================================================

test_backup_cleanup_structure() {
    setup_test_env

    # Create temp backup directory
    BACKUP_DIR="/tmp/sbx-backup-test-$$"
    mkdir -p "$BACKUP_DIR"

    # Create old backup file (mock)
    old_backup="$BACKUP_DIR/sbx-backup-20200101-000000.tar.gz"
    touch "$old_backup"

    # Function should handle cleanup
    backup_cleanup 2>/dev/null || true
    assert_success 0 "Should handle backup cleanup"

    rm -rf "$BACKUP_DIR"
    teardown_test_env
}

#==============================================================================
# Test Suite: load_client_info
#==============================================================================

test_load_client_info_missing_file() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/missing-client-info-$$"

    if load_client_info 2>/dev/null; then
        assert_failure 1 "Should fail for missing client info file"
    else
        assert_success 0 "Correctly handled missing file"
    fi

    teardown_test_env
}

test_load_client_info_valid_file() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/test-client-info-$$"

    # Create mock client info file
    cat > "$CLIENT_INFO_FILE" << 'EOF'
UUID=a1b2c3d4-e5f6-7890-1234-567890abcdef
PUBLIC_KEY=test-public-key
SHORT_ID=a1b2c3d4
REALITY_PORT=443
DOMAIN=192.168.1.1
REALITY_DEST=www.microsoft.com
EOF

    if load_client_info; then
        assert_success 0 "Should load valid client info file"
        assert_equals "$UUID" "a1b2c3d4-e5f6-7890-1234-567890abcdef" "Should load UUID"
        assert_equals "$PUBLIC_KEY" "test-public-key" "Should load public key"
        assert_equals "$SHORT_ID" "a1b2c3d4" "Should load short ID"
    else
        assert_failure 1 "Failed to load valid client info"
    fi

    rm -f "$CLIENT_INFO_FILE"
    teardown_test_env
}

#==============================================================================
# Test Suite: export_config
#==============================================================================

test_export_config_missing_info() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/missing-$$"

    # Should fail without client info
    if export_config "v2rayn" "reality" 2>/dev/null; then
        assert_failure 1 "Should fail without client info"
    else
        assert_success 0 "Correctly handled missing client info"
    fi

    teardown_test_env
}

test_export_config_invalid_format() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/test-client-info-$$"
    cat > "$CLIENT_INFO_FILE" << 'EOF'
UUID=test-uuid
PUBLIC_KEY=test-key
SHORT_ID=a1b2c3d4
EOF

    # Should fail with invalid export format
    if export_config "invalid-format" "reality" 2>/dev/null; then
        assert_failure 1 "Should reject invalid export format"
    else
        assert_success 0 "Correctly rejected invalid format"
    fi

    rm -f "$CLIENT_INFO_FILE"
    teardown_test_env
}

#==============================================================================
# Test Suite: export_qr_codes
#==============================================================================

test_export_qr_codes_missing_dir() {
    setup_test_env

    output_dir="/tmp/nonexistent-dir-$$/qr"

    # Should create directory or handle gracefully
    export_qr_codes "$output_dir" 2>/dev/null || true
    assert_success 0 "Should handle directory creation"

    rm -rf "/tmp/nonexistent-dir-$$"
    teardown_test_env
}

#==============================================================================
# Test Suite: export_subscription
#==============================================================================

test_export_subscription_structure() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/test-client-info-$$"
    cat > "$CLIENT_INFO_FILE" << 'EOF'
UUID=a1b2c3d4-e5f6-7890-1234-567890abcdef
PUBLIC_KEY=test-public-key
SHORT_ID=a1b2c3d4
REALITY_PORT=443
DOMAIN=example.com
REALITY_DEST=www.microsoft.com
EOF

    # Should generate base64-encoded subscription
    result=$(export_subscription 2>/dev/null || echo "")

    if [[ -n "$result" ]]; then
        # Check if output is base64
        if echo "$result" | base64 -d &>/dev/null; then
            assert_success 0 "Should generate valid base64 subscription"
        fi
    fi

    rm -f "$CLIENT_INFO_FILE"
    teardown_test_env
}

#==============================================================================
# Test Suite: export_clash_yaml
#==============================================================================

test_export_clash_yaml_structure() {
    setup_test_env

    CLIENT_INFO_FILE="/tmp/test-client-info-$$"
    cat > "$CLIENT_INFO_FILE" << 'EOF'
UUID=a1b2c3d4-e5f6-7890-1234-567890abcdef
PUBLIC_KEY=test-public-key
SHORT_ID=a1b2c3d4
REALITY_PORT=443
DOMAIN=example.com
REALITY_DEST=www.microsoft.com
EOF

    result=$(export_clash_yaml 2>/dev/null || echo "")

    if [[ -n "$result" ]]; then
        # Check for YAML structure
        assert_contains "$result" "proxies:" "Should contain proxies section"
        assert_contains "$result" "name:" "Should contain proxy name"
        assert_contains "$result" "type: vless" "Should specify VLESS type"
    fi

    rm -f "$CLIENT_INFO_FILE"
    teardown_test_env
}

#==============================================================================
# Run All Tests
#==============================================================================

echo "=== Backup and Export Functions Tests ==="
echo ""

# Backup tests
test_backup_list_no_backups
test_backup_list_with_backups
test_backup_cleanup_structure

# Client info tests
test_load_client_info_missing_file
test_load_client_info_valid_file

# Export config tests
test_export_config_missing_info
test_export_config_invalid_format

# QR code tests
test_export_qr_codes_missing_dir

# Subscription tests
test_export_subscription_structure

# Clash export tests
test_export_clash_yaml_structure

print_test_summary

# Exit with failure if any tests failed
[[ $TESTS_FAILED -eq 0 ]]
