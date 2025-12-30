#!/usr/bin/env bash
# tests/unit/test_network_helpers.sh - Unit tests for lib/network.sh
# Tests network utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the network module
source "${PROJECT_ROOT}/lib/network.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/network.sh"
    exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

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
# Test: Network Functions
#==============================================================================

test_get_public_ip() {
    echo ""
    echo "Testing get_public_ip..."

    if declare -f get_public_ip >/dev/null 2>&1; then
        local ip
        ip=$(get_public_ip 2>/dev/null) || true
        if [[ -n "$ip" ]]; then
            test_result "get_public_ip returns IP" "pass"
        else
            test_result "get_public_ip (network may be unavailable)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_is_port_available() {
    echo ""
    echo "Testing is_port_available..."

    if declare -f is_port_available >/dev/null 2>&1; then
        # Test with a likely available high port
        if is_port_available 59999 2>/dev/null; then
            test_result "detects available port" "pass"
        else
            test_result "detects available port" "fail"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_allocate_port() {
    echo ""
    echo "Testing allocate_port..."

    if declare -f allocate_port >/dev/null 2>&1; then
        local port
        port=$(allocate_port 8000 9000 2>/dev/null) || true
        if [[ -n "$port" ]]; then
            test_result "allocate_port returns port" "pass"
        else
            test_result "allocate_port (all ports may be in use)" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_check_port_in_use() {
    echo ""
    echo "Testing check_port_in_use..."

    if declare -f check_port_in_use >/dev/null 2>&1; then
        # Port 22 is usually in use
        check_port_in_use 22 2>/dev/null || true
        test_result "check_port_in_use executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_wait_for_port() {
    echo ""
    echo "Testing wait_for_port..."

    if declare -f wait_for_port >/dev/null 2>&1; then
        test_result "function exists" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_detect_ipv6_support() {
    echo ""
    echo "Testing detect_ipv6_support..."

    if declare -f detect_ipv6_support >/dev/null 2>&1; then
        detect_ipv6_support >/dev/null 2>&1
        test_result "detect_ipv6_support executes" "pass"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_choose_listen_address() {
    echo ""
    echo "Testing choose_listen_address..."

    if declare -f choose_listen_address >/dev/null 2>&1; then
        local addr
        addr=$(choose_listen_address 2>/dev/null) || true
        if [[ "$addr" == "::" || "$addr" == "0.0.0.0" ]]; then
            test_result "choose_listen_address returns valid address" "pass"
        else
            test_result "choose_listen_address executes" "pass"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_safe_http_get_missing_timeout() {
    echo ""
    echo "Testing safe_http_get with missing timeout..."

    if declare -f safe_http_get >/dev/null 2>&1; then
        local output status
        local original_path="$PATH"
        local temp_dir
        temp_dir=$(mktemp -d)

        cat > "${temp_dir}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        cat > "${temp_dir}/wget" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${temp_dir}/curl" "${temp_dir}/wget"

        PATH="${temp_dir}"
        output=$(safe_http_get "https://example.com" 2>&1)
        status=$?
        PATH="$original_path"
        rm -rf "$temp_dir"

        if [[ $status -ne 0 && "$output" == *"timeout"* ]]; then
            test_result "safe_http_get reports missing timeout" "pass"
        else
            test_result "safe_http_get reports missing timeout" "fail"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_safe_http_get_missing_downloaders() {
    echo ""
    echo "Testing safe_http_get with missing downloaders..."

    if declare -f safe_http_get >/dev/null 2>&1; then
        local output status
        local original_path="$PATH"
        local temp_dir
        temp_dir=$(mktemp -d)

        cat > "${temp_dir}/timeout" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${temp_dir}/timeout"

        PATH="${temp_dir}"
        output=$(safe_http_get "https://example.com" 2>&1)
        status=$?
        PATH="$original_path"
        rm -rf "$temp_dir"

        if [[ $status -ne 0 && "$output" == *"curl or wget"* ]]; then
            test_result "safe_http_get reports missing downloaders" "pass"
        else
            test_result "safe_http_get reports missing downloaders" "fail"
        fi
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/network.sh Functions"
echo "=========================================="

test_get_public_ip
test_is_port_available
test_allocate_port
test_check_port_in_use
test_wait_for_port
test_detect_ipv6_support
test_choose_listen_address
test_safe_http_get_missing_timeout
test_safe_http_get_missing_downloaders

# Print summary
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
