#!/usr/bin/env bash
# tests/unit/test_client_info_security.sh - Validate client info loading safety
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Bring in assertion helpers
source "${PROJECT_ROOT}/tests/test_framework.sh"
set +e
set -o pipefail
export TERM="xterm"

TEST_TMPDIR=""
LAST_OUTPUT=""
LAST_EXIT_CODE=0

setup_fixture() {
    TEST_TMPDIR=$(create_test_tmpdir)
    export LIB_DIR="${PROJECT_ROOT}/lib"
    export TEST_CLIENT_INFO="${TEST_TMPDIR}/client-info.txt"
}

teardown_fixture() {
    cleanup_test_tmpdir "$TEST_TMPDIR"
}

run_sbx_info_with_content() {
    local content="$1"
    echo "$content" > "$TEST_CLIENT_INFO"
    chmod 600 "$TEST_CLIENT_INFO"

    set +e
    LAST_OUTPUT=$(LIB_DIR="$LIB_DIR" TEST_CLIENT_INFO="$TEST_CLIENT_INFO" bash "${PROJECT_ROOT}/bin/sbx-manager.sh" info 2>&1)
    LAST_EXIT_CODE=$?
}

test_unexpected_keys_rejected() {
    echo ""
    echo "Running: test_unexpected_keys_rejected"

    run_sbx_info_with_content "$(cat <<EOF
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="abcd"
SHORT_ID="1234abcd"
SNI="www.microsoft.com"
REALITY_PORT="443"
MALICIOUS="\$(touch ${TEST_TMPDIR}/malicious.txt)"
EOF
)"

    assert_equals "1" "$LAST_EXIT_CODE" "sbx info should fail when client info contains unexpected keys"
    assert_contains "$LAST_OUTPUT" "Unexpected key 'MALICIOUS'" "error message should mention unexpected key"
    assert_file_not_exists "${TEST_TMPDIR}/malicious.txt" "malicious payload should not be executed"
}

test_suspicious_values_rejected() {
    echo ""
    echo "Running: test_suspicious_values_rejected"

    run_sbx_info_with_content "$(cat <<EOF
DOMAIN="example.com"
UUID="11111111-2222-3333-4444-555555555555"
PUBLIC_KEY="\$(touch ${TEST_TMPDIR}/pk_marker.txt)"
SHORT_ID="1234abcd"
SNI="www.microsoft.com"
REALITY_PORT="443"
EOF
)"

    assert_equals "1" "$LAST_EXIT_CODE" "sbx info should fail when client info contains suspicious values"
    assert_contains "$LAST_OUTPUT" "Suspicious characters in value for PUBLIC_KEY" "error message should flag suspicious value"
    assert_file_not_exists "${TEST_TMPDIR}/pk_marker.txt" "command substitutions must not be executed"
}

test_unquoted_format_accepted() {
    echo ""
    echo "Running: test_unquoted_format_accepted"

    # Test that unquoted KEY=value format works correctly
    run_sbx_info_with_content "$(cat <<EOF
DOMAIN=example.com
UUID=11111111-2222-3333-4444-555555555555
PUBLIC_KEY=abcdefghijklmnopqrstuvwxyz123456789012345
SHORT_ID=1234abcd
SNI=www.microsoft.com
REALITY_PORT=443
EOF
)"

    # Should succeed (exit 0) or at least not fail on format validation
    # Note: May fail on other checks like missing service, but format should be accepted
    assert_not_contains "$LAST_OUTPUT" "Invalid client info format" "unquoted format should be accepted"
    assert_not_contains "$LAST_OUTPUT" "Invalid client info entry" "unquoted entries should be valid"
}

test_unquoted_suspicious_values_rejected() {
    echo ""
    echo "Running: test_unquoted_suspicious_values_rejected"

    # Test that unquoted format with shell injection is caught
    # Note: Using $(id) instead of $(touch ...) because unquoted values
    # cannot contain spaces (spaces cause format validation failure)
    run_sbx_info_with_content "$(cat <<EOF
DOMAIN=example.com
UUID=11111111-2222-3333-4444-555555555555
PUBLIC_KEY=\$(id)
SHORT_ID=1234abcd
SNI=www.microsoft.com
REALITY_PORT=443
EOF
)"

    assert_equals "1" "$LAST_EXIT_CODE" "sbx info should fail when unquoted value contains suspicious chars"
    assert_contains "$LAST_OUTPUT" "Suspicious characters in value for PUBLIC_KEY" "error should flag unquoted suspicious value"
}

test_mixed_format_accepted() {
    echo ""
    echo "Running: test_mixed_format_accepted"

    # Test that mixing quoted and unquoted formats works
    run_sbx_info_with_content "$(cat <<EOF
DOMAIN="example.com"
UUID=11111111-2222-3333-4444-555555555555
PUBLIC_KEY="abcdefghijklmnopqrstuvwxyz123456789012345"
SHORT_ID=1234abcd
SNI="www.microsoft.com"
REALITY_PORT=443
EOF
)"

    assert_not_contains "$LAST_OUTPUT" "Invalid client info format" "mixed format should be accepted"
    assert_not_contains "$LAST_OUTPUT" "Invalid client info entry" "mixed entries should be valid"
}

# Main execution
setup_fixture

test_unexpected_keys_rejected
test_suspicious_values_rejected
test_unquoted_format_accepted
test_unquoted_suspicious_values_rejected
test_mixed_format_accepted

teardown_fixture
print_test_summary

exit $(( TESTS_FAILED > 0 ? 1 : 0 ))
