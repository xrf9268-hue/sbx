#!/usr/bin/env bash
# Unit tests for Reality validation functions in lib/validation.sh
# Tests: validate_reality_sni, validate_reality_keypair, validate_menu_choice
#        _validate_vision_requirements, _validate_incompatible_combinations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test environment flag
export SBX_TEST_MODE=1

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Load required modules
source lib/common.sh 2> /dev/null || {
    echo "✗ Failed to load lib/common.sh"
    exit 1
}

source lib/messages.sh 2> /dev/null || {
    echo "✗ Failed to load lib/messages.sh"
    exit 1
}

source lib/validation.sh 2> /dev/null || {
    echo "✗ Failed to load lib/validation.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo ""
    echo "Test $((TOTAL_TESTS + 1)): $test_name"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if $test_func 2> /dev/null; then
        echo "✓ PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
  else
        echo "✗ FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
  fi
}

echo "=== Reality Validation Functions Unit Tests ==="

#==============================================================================
# Tests for validate_reality_sni()
#==============================================================================

test_validate_reality_sni_valid_domain() {
    validate_reality_sni "www.microsoft.com" > /dev/null 2>&1
}

test_validate_reality_sni_valid_subdomain() {
    validate_reality_sni "cdn.cloudflare.com" > /dev/null 2>&1
}

test_validate_reality_sni_valid_wildcard() {
    validate_reality_sni "*.cloudflare.com" > /dev/null 2>&1
}

test_validate_reality_sni_empty_fails() {
    ! validate_reality_sni "" > /dev/null 2>&1
}

test_validate_reality_sni_consecutive_dots_fails() {
    ! validate_reality_sni "www..microsoft.com" > /dev/null 2>&1
}

test_validate_reality_sni_hyphen_start_fails() {
    ! validate_reality_sni "-microsoft.com" > /dev/null 2>&1
}

test_validate_reality_sni_long_domain() {
    validate_reality_sni "subdomain.example.com" > /dev/null 2>&1
}

setup_sni_probe_mocks() {
    local mock_dir="$1"
    mkdir -p "${mock_dir}"

cat > "${mock_dir}/openssl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "s_client" ]]; then
  connect_target=''
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-connect" && -n "${2:-}" ]]; then
      connect_target="${2}"
      break
    fi
    shift
  done

  if [[ -n "${MOCK_FAIL_DOMAIN:-}" && "${connect_target}" == "${MOCK_FAIL_DOMAIN}:443" ]]; then
    exit 1
  fi

  if [[ "${MOCK_OPENSSL_EXIT:-0}" != "0" ]]; then
    exit "${MOCK_OPENSSL_EXIT}"
  fi
  [[ "${MOCK_TLS13:-1}" == "1" ]] && echo "Protocol  : TLSv1.3"
  [[ "${MOCK_ALPN_H2:-1}" == "1" ]] && echo "ALPN protocol: h2"
  exit 0
fi
exit 0
EOF

    cat > "${mock_dir}/timeout" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" =~ ^[0-9]+$ ]]; then
  shift
fi
"$@"
EOF

    chmod +x "${mock_dir}/openssl" "${mock_dir}/timeout"
}

test_validate_sni_domain_probe_success() {
    local mock_dir=''
    mock_dir=$(mktemp -d /tmp/sbx-sni-probe.XXXXXX)
    setup_sni_probe_mocks "${mock_dir}"

    local old_path="${PATH}"
    export PATH="${mock_dir}:${PATH}"
    export MOCK_TLS13=1 MOCK_ALPN_H2=1 MOCK_OPENSSL_EXIT=0
    validate_sni_domain "www.microsoft.com" 1 > /dev/null 2>&1
    local rc=$?
    export PATH="${old_path}"
    rm -rf "${mock_dir}"
    [[ ${rc} -eq 0 ]]
}

test_validate_sni_domain_probe_tls13_missing_fails() {
    local mock_dir=''
    mock_dir=$(mktemp -d /tmp/sbx-sni-probe.XXXXXX)
    setup_sni_probe_mocks "${mock_dir}"

    local old_path="${PATH}"
    export PATH="${mock_dir}:${PATH}"
    export MOCK_TLS13=0 MOCK_ALPN_H2=1 MOCK_OPENSSL_EXIT=0
    ! validate_sni_domain "www.microsoft.com" 1 > /dev/null 2>&1
    local rc=$?
    export PATH="${old_path}"
    rm -rf "${mock_dir}"
    [[ ${rc} -eq 0 ]]
}

test_select_reality_sni_domain_fallback() {
    local mock_dir=''
    mock_dir=$(mktemp -d /tmp/sbx-sni-probe.XXXXXX)
    setup_sni_probe_mocks "${mock_dir}"

    local old_path="${PATH}"
    export PATH="${mock_dir}:${PATH}"
    export MOCK_TLS13=1 MOCK_ALPN_H2=1 MOCK_OPENSSL_EXIT=0
    export MOCK_FAIL_DOMAIN="www.microsoft.com"

    # shellcheck disable=SC2312
    local selected
    selected=$(select_reality_sni_domain "www.microsoft.com" "www.apple.com,www.amazon.com" 1)
    local rc=$?
    export PATH="${old_path}"
    rm -rf "${mock_dir}"

    [[ ${rc} -eq 0 ]] && [[ "${selected}" == "www.apple.com" ]]
}

#==============================================================================
# Tests for validate_reality_keypair()
#==============================================================================

test_validate_reality_keypair_valid() {
    # Real X25519 keys are 43 characters base64url
    local priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
    local pub="abc123DEF456ghi789JKL012mno345PQR678stu90-_W"
    validate_reality_keypair "$priv" "$pub" > /dev/null 2>&1
}

test_validate_reality_keypair_empty_private_fails() {
    ! validate_reality_keypair "" "abc123DEF456ghi789JKL012mno345PQR678stu90-_W" > /dev/null 2>&1
}

test_validate_reality_keypair_empty_public_fails() {
    ! validate_reality_keypair "UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc" "" > /dev/null 2>&1
}

test_validate_reality_keypair_invalid_chars_fails() {
    # Keys with invalid characters (spaces, +, =) should fail
    ! validate_reality_keypair "invalid key with spaces" "another invalid key" > /dev/null 2>&1
}

test_validate_reality_keypair_too_short_fails() {
    # X25519 keys must be 42-44 characters
    ! validate_reality_keypair "tooshort" "alsotooshort" > /dev/null 2>&1
}

test_validate_reality_keypair_both_empty_fails() {
    ! validate_reality_keypair "" "" > /dev/null 2>&1
}

#==============================================================================
# Tests for validate_menu_choice()
#==============================================================================

test_validate_menu_choice_valid_single() {
    validate_menu_choice "1" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_valid_middle() {
    validate_menu_choice "3" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_valid_max() {
    validate_menu_choice "5" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_below_min_fails() {
    ! validate_menu_choice "0" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_above_max_fails() {
    ! validate_menu_choice "6" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_non_numeric_fails() {
    ! validate_menu_choice "abc" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_empty_fails() {
    ! validate_menu_choice "" 1 5 > /dev/null 2>&1
}

test_validate_menu_choice_default_range() {
    # Default is 1-9
    validate_menu_choice "5" > /dev/null 2>&1
}

#==============================================================================
# Tests for _validate_vision_requirements()
#==============================================================================

test_validate_vision_requirements_valid() {
    _validate_vision_requirements "tcp" "reality" "xtls-rprx-vision" > /dev/null 2>&1
}

test_validate_vision_requirements_wrong_transport_fails() {
    ! _validate_vision_requirements "ws" "reality" "xtls-rprx-vision" > /dev/null 2>&1
}

test_validate_vision_requirements_wrong_security_fails() {
    ! _validate_vision_requirements "tcp" "tls" "xtls-rprx-vision" > /dev/null 2>&1
}

test_validate_vision_requirements_grpc_transport_fails() {
    ! _validate_vision_requirements "grpc" "reality" "xtls-rprx-vision" > /dev/null 2>&1
}

#==============================================================================
# Tests for _validate_incompatible_combinations()
#==============================================================================

test_validate_incompatible_ws_reality_fails() {
    ! _validate_incompatible_combinations "ws" "reality" > /dev/null 2>&1
}

test_validate_incompatible_grpc_reality_fails() {
    ! _validate_incompatible_combinations "grpc" "reality" > /dev/null 2>&1
}

test_validate_incompatible_http_reality_fails() {
    ! _validate_incompatible_combinations "http" "reality" > /dev/null 2>&1
}

test_validate_incompatible_quic_reality_fails() {
    ! _validate_incompatible_combinations "quic" "reality" > /dev/null 2>&1
}

test_validate_compatible_tcp_reality() {
    _validate_incompatible_combinations "tcp" "reality" > /dev/null 2>&1
}

test_validate_compatible_ws_tls() {
    _validate_incompatible_combinations "ws" "tls" > /dev/null 2>&1
}

test_validate_compatible_grpc_tls() {
    _validate_incompatible_combinations "grpc" "tls" > /dev/null 2>&1
}

#==============================================================================
# Run all tests
#==============================================================================

echo ""
echo "Testing validate_reality_sni..."
run_test "Valid domain (www.microsoft.com)" test_validate_reality_sni_valid_domain
run_test "Valid subdomain (cdn.cloudflare.com)" test_validate_reality_sni_valid_subdomain
run_test "Valid wildcard (*.cloudflare.com)" test_validate_reality_sni_valid_wildcard
run_test "Empty SNI fails" test_validate_reality_sni_empty_fails
run_test "Consecutive dots fails" test_validate_reality_sni_consecutive_dots_fails
run_test "Hyphen start fails" test_validate_reality_sni_hyphen_start_fails
run_test "Long domain accepted" test_validate_reality_sni_long_domain
run_test "SNI probe success with TLS1.3+h2" test_validate_sni_domain_probe_success
run_test "SNI probe fails without TLS1.3" test_validate_sni_domain_probe_tls13_missing_fails
run_test "SNI selector supports fallback list" test_select_reality_sni_domain_fallback

echo ""
echo "Testing validate_reality_keypair..."
run_test "Valid keypair accepted" test_validate_reality_keypair_valid
run_test "Empty private key fails" test_validate_reality_keypair_empty_private_fails
run_test "Empty public key fails" test_validate_reality_keypair_empty_public_fails
run_test "Invalid chars fail" test_validate_reality_keypair_invalid_chars_fails
run_test "Too short keys fail" test_validate_reality_keypair_too_short_fails
run_test "Both empty fails" test_validate_reality_keypair_both_empty_fails

echo ""
echo "Testing validate_menu_choice..."
run_test "Valid choice (1)" test_validate_menu_choice_valid_single
run_test "Valid choice (middle)" test_validate_menu_choice_valid_middle
run_test "Valid choice (max)" test_validate_menu_choice_valid_max
run_test "Below min fails" test_validate_menu_choice_below_min_fails
run_test "Above max fails" test_validate_menu_choice_above_max_fails
run_test "Non-numeric fails" test_validate_menu_choice_non_numeric_fails
run_test "Empty fails" test_validate_menu_choice_empty_fails
run_test "Default range works" test_validate_menu_choice_default_range

echo ""
echo "Testing _validate_vision_requirements..."
run_test "Valid Vision config (tcp+reality)" test_validate_vision_requirements_valid
run_test "Wrong transport (ws) fails" test_validate_vision_requirements_wrong_transport_fails
run_test "Wrong security (tls) fails" test_validate_vision_requirements_wrong_security_fails
run_test "gRPC transport fails" test_validate_vision_requirements_grpc_transport_fails

echo ""
echo "Testing _validate_incompatible_combinations..."
run_test "ws+reality incompatible" test_validate_incompatible_ws_reality_fails
run_test "grpc+reality incompatible" test_validate_incompatible_grpc_reality_fails
run_test "http+reality incompatible" test_validate_incompatible_http_reality_fails
run_test "quic+reality incompatible" test_validate_incompatible_quic_reality_fails
run_test "tcp+reality compatible" test_validate_compatible_tcp_reality
run_test "ws+tls compatible" test_validate_compatible_ws_tls
run_test "grpc+tls compatible" test_validate_compatible_grpc_tls

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "------------------------------------------"
echo "Total:   $TOTAL_TESTS"
echo "Passed:  $PASSED_TESTS"
echo "Failed:  $FAILED_TESTS"
echo "=========================================="

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi

exit 0
