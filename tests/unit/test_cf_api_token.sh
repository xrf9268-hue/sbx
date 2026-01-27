#!/usr/bin/env bash
# tests/unit/test_cf_api_token.sh - Cloudflare API Token validation tests
# Tests for validate_cf_api_token() and CF_Token backward compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local test_name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$result" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $test_name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $test_name"
  fi
}

#==============================================================================
# Test: validate_cf_api_token function exists
#==============================================================================

test_validate_cf_api_token_function_exists() {
  echo ""
  echo "Testing validate_cf_api_token function exists..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null
    if declare -f validate_cf_api_token > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "validate_cf_api_token function exists" "pass" \
    || test_result "validate_cf_api_token function exists" "fail"
}

#==============================================================================
# Test: Valid token passes validation
#==============================================================================

test_valid_token_passes() {
  echo ""
  echo "Testing valid token passes validation..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    # Valid 40-character alphanumeric token
    local valid_token="abcdef1234567890abcdef1234567890abcdef12"

    if validate_cf_api_token "$valid_token"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Valid 40-char token passes" "pass" \
    || test_result "Valid 40-char token passes" "fail"
}

#==============================================================================
# Test: Empty token fails validation
#==============================================================================

test_empty_token_fails() {
  echo ""
  echo "Testing empty token fails validation..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    if ! validate_cf_api_token ""; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Empty token fails" "pass" \
    || test_result "Empty token fails" "fail"
}

#==============================================================================
# Test: Token too short fails validation
#==============================================================================

test_short_token_fails() {
  echo ""
  echo "Testing short token fails validation..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    # Token with only 30 characters (too short)
    local short_token="abcdef1234567890abcdef12345678"

    if ! validate_cf_api_token "$short_token"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "30-char token fails (too short)" "pass" \
    || test_result "30-char token fails (too short)" "fail"
}

#==============================================================================
# Test: Token too long fails validation
#==============================================================================

test_long_token_fails() {
  echo ""
  echo "Testing long token fails validation..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    # Token with 70 characters (too long)
    local long_token="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12"

    if ! validate_cf_api_token "$long_token"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "70-char token fails (too long)" "pass" \
    || test_result "70-char token fails (too long)" "fail"
}

#==============================================================================
# Test: Token with invalid characters fails
#==============================================================================

test_invalid_characters_fails() {
  echo ""
  echo "Testing token with invalid characters fails..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    # Token with special characters
    local invalid_token="abcdef1234567890abcdef1234567890abc!@#\$%"

    if ! validate_cf_api_token "$invalid_token"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Token with special chars fails" "pass" \
    || test_result "Token with special chars fails" "fail"
}

#==============================================================================
# Test: Token with underscores and dashes passes
#==============================================================================

test_token_with_underscores_dashes_passes() {
  echo ""
  echo "Testing token with underscores and dashes passes..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    # Valid token with underscores and dashes (common in CF tokens)
    local valid_token="abcdef-1234_567890abcdef-1234_567890abcd"

    if validate_cf_api_token "$valid_token"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Token with _- passes" "pass" \
    || test_result "Token with _- passes" "fail"
}

#==============================================================================
# Test: CF_Token backward compatibility constant exists
#==============================================================================

test_cf_api_token_min_length_constant_exists() {
  echo ""
  echo "Testing CF_API_TOKEN_MIN_LENGTH constant exists..."

  (
    source "${PROJECT_ROOT}/lib/common.sh" 2> /dev/null

    if [[ -n "${CF_API_TOKEN_MIN_LENGTH:-}" ]]; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "CF_API_TOKEN_MIN_LENGTH constant exists" "pass" \
    || test_result "CF_API_TOKEN_MIN_LENGTH constant exists" "fail"
}

#==============================================================================
# Test: CF_API_TOKEN_MAX_LENGTH constant exists
#==============================================================================

test_cf_api_token_max_length_constant_exists() {
  echo ""
  echo "Testing CF_API_TOKEN_MAX_LENGTH constant exists..."

  (
    source "${PROJECT_ROOT}/lib/common.sh" 2> /dev/null

    if [[ -n "${CF_API_TOKEN_MAX_LENGTH:-}" ]]; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "CF_API_TOKEN_MAX_LENGTH constant exists" "pass" \
    || test_result "CF_API_TOKEN_MAX_LENGTH constant exists" "fail"
}

#==============================================================================
# Test: validate_env_vars handles cf_dns CERT_MODE
#==============================================================================

test_validate_env_vars_cf_dns_mode() {
  echo ""
  echo "Testing validate_env_vars handles cf_dns CERT_MODE..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    export CERT_MODE="cf_dns"
    export CF_API_TOKEN="abcdef1234567890abcdef1234567890abcdef12"
    export DOMAIN="example.com"

    # Should not error with valid CF_API_TOKEN
    if validate_env_vars 2> /dev/null; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "cf_dns with valid CF_API_TOKEN works" "pass" \
    || test_result "cf_dns with valid CF_API_TOKEN works" "fail"
}

#==============================================================================
# Test: CF_Token backward compatibility
#==============================================================================

test_cf_token_backward_compatibility() {
  echo ""
  echo "Testing CF_Token backward compatibility..."

  (
    source "${PROJECT_ROOT}/lib/validation.sh" 2> /dev/null

    export CERT_MODE="cf_dns"
    export CF_Token="abcdef1234567890abcdef1234567890abcdef12"
    unset CF_API_TOKEN
    export DOMAIN="example.com"

    # Should work with legacy CF_Token
    if validate_env_vars 2> /dev/null; then
      # Check if CF_API_TOKEN was set from CF_Token
      if [[ "${CF_API_TOKEN:-}" == "${CF_Token}" ]]; then
        echo "pass"
      else
        echo "fail: CF_API_TOKEN not set from CF_Token"
      fi
    else
      echo "fail: validate_env_vars failed"
    fi
  ) | grep -q "pass" && test_result "CF_Token backward compatibility works" "pass" \
    || test_result "CF_Token backward compatibility works" "fail"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: CF API Token Validation"
echo "=========================================="

test_validate_cf_api_token_function_exists
test_valid_token_passes
test_empty_token_fails
test_short_token_fails
test_long_token_fails
test_invalid_characters_fails
test_token_with_underscores_dashes_passes
test_cf_api_token_min_length_constant_exists
test_cf_api_token_max_length_constant_exists
test_validate_env_vars_cf_dns_mode
test_cf_token_backward_compatibility

echo ""
echo "=========================================="
echo "           Test Summary"
echo "=========================================="
echo "Total tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
