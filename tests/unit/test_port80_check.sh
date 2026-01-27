#!/usr/bin/env bash
# tests/unit/test_port80_check.sh - Port 80 availability check tests
# Tests for check_port_80_for_acme() and show_port_80_guidance()

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
# Test: check_port_80_for_acme function exists
#==============================================================================

test_check_port_80_function_exists() {
  echo ""
  echo "Testing check_port_80_for_acme function exists..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null
    if declare -f check_port_80_for_acme > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "check_port_80_for_acme function exists" "pass" \
    || test_result "check_port_80_for_acme function exists" "fail"
}

#==============================================================================
# Test: show_port_80_guidance function exists
#==============================================================================

test_show_port_80_guidance_function_exists() {
  echo ""
  echo "Testing show_port_80_guidance function exists..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null
    if declare -f show_port_80_guidance > /dev/null 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "show_port_80_guidance function exists" "pass" \
    || test_result "show_port_80_guidance function exists" "fail"
}

#==============================================================================
# Test: check_port_80_for_acme returns 0 when port 80 is available
#==============================================================================

test_port_80_available_returns_0() {
  echo ""
  echo "Testing check_port_80_for_acme returns 0 when available..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null

    # Mock port_in_use to return 1 (port not in use)
    port_in_use() { return 1; }
    export -f port_in_use

    if check_port_80_for_acme; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Returns 0 when port 80 available" "pass" \
    || test_result "Returns 0 when port 80 available" "fail"
}

#==============================================================================
# Test: check_port_80_for_acme returns 1 when port 80 is in use
#==============================================================================

test_port_80_in_use_returns_1() {
  echo ""
  echo "Testing check_port_80_for_acme returns 1 when in use..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null

    # Mock port_in_use to return 0 (port is in use)
    port_in_use() { return 0; }
    export -f port_in_use

    # Suppress output for test
    if ! check_port_80_for_acme 2> /dev/null; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Returns 1 when port 80 in use" "pass" \
    || test_result "Returns 1 when port 80 in use" "fail"
}

#==============================================================================
# Test: show_port_80_guidance outputs cloud platform hints
#==============================================================================

test_show_port_80_guidance_outputs_hints() {
  echo ""
  echo "Testing show_port_80_guidance outputs cloud platform hints..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null

    output=$(show_port_80_guidance 2>&1)

    # Check for key platform hints
    if echo "$output" | grep -q "GCP" \
      && echo "$output" | grep -q "AWS" \
      && echo "$output" | grep -q "Azure"; then
      echo "pass"
    else
      echo "fail: output=$output"
    fi
  ) | grep -q "pass" && test_result "Outputs GCP, AWS, Azure hints" "pass" \
    || test_result "Outputs GCP, AWS, Azure hints" "fail"
}

#==============================================================================
# Test: show_port_80_guidance outputs firewall commands
#==============================================================================

test_show_port_80_guidance_outputs_firewall_commands() {
  echo ""
  echo "Testing show_port_80_guidance outputs firewall commands..."

  (
    source "${PROJECT_ROOT}/lib/network.sh" 2> /dev/null

    output=$(show_port_80_guidance 2>&1)

    # Check for firewall commands
    if echo "$output" | grep -q "firewalld" \
      && echo "$output" | grep -q "ufw" \
      && echo "$output" | grep -q "iptables"; then
      echo "pass"
    else
      echo "fail"
    fi
  ) | grep -q "pass" && test_result "Outputs firewalld, ufw, iptables commands" "pass" \
    || test_result "Outputs firewalld, ufw, iptables commands" "fail"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: Port 80 Check"
echo "=========================================="

test_check_port_80_function_exists
test_show_port_80_guidance_function_exists
test_port_80_available_returns_0
test_port_80_in_use_returns_1
test_show_port_80_guidance_outputs_hints
test_show_port_80_guidance_outputs_firewall_commands

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
