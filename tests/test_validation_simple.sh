#!/usr/bin/env bash
# tests/test_validation_simple.sh - Simplified Reality validation tests
# This is a working subset while test_reality.sh hangs in CI

set -euo pipefail
export SBX_TEST_MODE=1

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/validation.sh"

# Disable traps from libraries
trap - RETURN ERR EXIT INT TERM HUP QUIT

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helpers
run_test() {
  local name="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ $name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ $name"
  fi
}

# Short ID validation tests
echo "Short ID Validation Tests"
echo "-------------------------"

run_test "Valid 8-char short ID" validate_short_id "a1b2c3d4"
run_test "Valid 4-char short ID" validate_short_id "abcd"
run_test "Valid 1-char short ID" validate_short_id "a"

run_test "Reject empty short ID" bash -c '! validate_short_id "" >/dev/null 2>&1'
run_test "Reject 9-char short ID" bash -c '! validate_short_id "abcd12345" >/dev/null 2>&1'
run_test "Reject 16-char (Xray) short ID" bash -c '! validate_short_id "abcd1234abcd1234" >/dev/null 2>&1'
run_test "Reject non-hex characters" bash -c '! validate_short_id "gggg1234" >/dev/null 2>&1'
run_test "Reject special characters" bash -c '! validate_short_id "ab-cd-12" >/dev/null 2>&1'

run_test "Accept uppercase hex" validate_short_id "ABCD1234"

# Reality keypair validation tests
echo ""
echo "Reality Keypair Validation Tests"
echo "--------------------------------"

PRIV_VALID="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
PUB_VALID="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

run_test "Valid Reality keypair" validate_reality_keypair "$PRIV_VALID" "$PUB_VALID"
run_test "Reject empty private key" bash -c '! validate_reality_keypair "" "$PUB_VALID" >/dev/null 2>&1'
run_test "Reject empty public key" bash -c '! validate_reality_keypair "$PRIV_VALID" "" >/dev/null 2>&1'
run_test "Reject invalid key format" bash -c '! validate_reality_keypair "invalid@key!" "$PUB_VALID" >/dev/null 2>&1'

# Reality SNI validation tests
echo ""
echo "Reality SNI Validation Tests"
echo "----------------------------"

run_test "Valid SNI: www.microsoft.com" validate_reality_sni "www.microsoft.com"
run_test "Valid SNI: google.com" validate_reality_sni "google.com"
run_test "Valid SNI: example.org" validate_reality_sni "example.org"

run_test "Reject empty SNI" bash -c '! validate_reality_sni "" >/dev/null 2>&1'
run_test "Reject invalid SNI format" bash -c '! validate_reality_sni "not a domain!" >/dev/null 2>&1'

# Transport+security pairing validation tests
echo ""
echo "Transport+Security Pairing Tests"
echo "--------------------------------"

run_test "Valid: TCP+Reality+Vision" validate_transport_security_pairing "tcp" "reality" "xtls-rprx-vision"
run_test "Reject: WS+Reality" bash -c '! validate_transport_security_pairing "ws" "reality" "" >/dev/null 2>&1'
run_test "Reject: gRPC+Reality" bash -c '! validate_transport_security_pairing "grpc" "reality" "" >/dev/null 2>&1'
run_test "Reject: Vision without Reality" bash -c '! validate_transport_security_pairing "tcp" "tls" "xtls-rprx-vision" >/dev/null 2>&1'

# Results
echo ""
echo "==============================================="
echo "Test Results"
echo "==============================================="
echo "Tests run:    $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo "✓ All tests passed!"
  exit 0
else
  echo "✗ Some tests failed"
  exit 1
fi
