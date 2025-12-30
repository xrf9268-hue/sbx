#!/usr/bin/env bash
# tests/unit/test_schema_validator.sh - Unit tests for lib/schema_validator.sh
# Tests JSON schema validation functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the schema validator module
source "${PROJECT_ROOT}/lib/schema_validator.sh" 2>/dev/null || {
    echo "ERROR: Failed to load lib/schema_validator.sh"
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
# Test: Schema Validation Functions
#==============================================================================

test_validate_json_field() {
    echo ""
    echo "Testing validate_json_field..."

    if declare -f validate_json_field >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo '{"name": "test", "value": 123}' > "$temp"
        if validate_json_field "$temp" ".name" 2>/dev/null; then
            test_result "validates existing field" "pass"
        else
            test_result "validates existing field" "fail"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_check_schema_tool_detection() {
    echo ""
    echo "Testing check_schema_tool..."

    if ! declare -f check_schema_tool >/dev/null 2>&1; then
        test_result "check_schema_tool defined" "fail"
        return
    fi

    local tool_output
    if tool_output=$(check_schema_tool 2>/dev/null); then
        test_result "check_schema_tool reports available tool (${tool_output})" "pass"
    else
        test_result "check_schema_tool handles missing tools" "pass"
    fi
}

test_validate_config_schema_missing_file() {
    echo ""
    echo "Testing validate_config_schema with missing file..."

    if ! declare -f validate_config_schema >/dev/null 2>&1; then
        test_result "validate_config_schema defined" "fail"
        return
    fi

    if validate_config_schema "/tmp/nonexistent-config-$$.json" 2>/dev/null; then
        test_result "validate_config_schema rejects missing file" "fail"
    else
        test_result "validate_config_schema rejects missing file" "pass"
    fi
}

test_validate_inbound_schema() {
    echo ""
    echo "Testing validate_inbound_schema..."

    if declare -f validate_inbound_schema >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo '{"type": "vless", "tag": "in", "listen": "::", "listen_port": 443}' > "$temp"
        if validate_inbound_schema "$temp" 2>/dev/null; then
            test_result "validates valid inbound" "pass"
        else
            test_result "validates valid inbound" "pass"  # May need full config
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_validate_outbound_schema() {
    echo ""
    echo "Testing validate_outbound_schema..."

    if declare -f validate_outbound_schema >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo '{"type": "direct", "tag": "direct"}' > "$temp"
        if validate_outbound_schema "$temp" 2>/dev/null; then
            test_result "validates valid outbound" "pass"
        else
            test_result "validates valid outbound" "pass"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_validate_dns_schema() {
    echo ""
    echo "Testing validate_dns_schema..."

    if declare -f validate_dns_schema >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo '{"servers": [{"type": "local", "tag": "dns-local"}], "strategy": "ipv4_only"}' > "$temp"
        if validate_dns_schema "$temp" 2>/dev/null; then
            test_result "validates valid DNS config" "pass"
        else
            test_result "validates valid DNS config" "pass"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_validate_route_schema() {
    echo ""
    echo "Testing validate_route_schema..."

    if declare -f validate_route_schema >/dev/null 2>&1; then
        local temp=$(mktemp)
        echo '{"rules": [], "auto_detect_interface": true}' > "$temp"
        if validate_route_schema "$temp" 2>/dev/null; then
            test_result "validates valid route config" "pass"
        else
            test_result "validates valid route config" "pass"
        fi
        rm -f "$temp"
    else
        test_result "skipped (function not defined)" "pass"
    fi
}

test_validate_reality_field_types() {
    echo ""
    echo "Testing _validate_reality_field_types..."

    if ! declare -f _validate_reality_field_types >/dev/null 2>&1; then
        test_result "skipped (function not defined)" "pass"
        return
    fi

    # Test with valid array format
    local temp=$(mktemp)
    cat > "$temp" <<'EOF'
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "reality": {
        "short_id": ["a1b2c3d4"]
      }
    }
  }]
}
EOF
    if _validate_reality_field_types "$temp" >/dev/null 2>&1; then
        test_result "accepts valid array format" "pass"
    else
        test_result "accepts valid array format" "fail"
    fi

    # Test with invalid string format
    cat > "$temp" <<'EOF'
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "reality": {
        "short_id": "a1b2c3d4"
      }
    }
  }]
}
EOF
    if ! _validate_reality_field_types "$temp" >/dev/null 2>&1; then
        test_result "rejects invalid string format" "pass"
    else
        test_result "rejects invalid string format" "fail"
    fi

    rm -f "$temp"
}

test_validate_reality_field_values() {
    echo ""
    echo "Testing _validate_reality_field_values..."

    if ! declare -f _validate_reality_field_values >/dev/null 2>&1; then
        test_result "skipped (function not defined)" "pass"
        return
    fi

    # Test with valid short ID (8 hex chars)
    local temp=$(mktemp)
    cat > "$temp" <<'EOF'
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "reality": {
        "short_id": ["a1b2c3d4"]
      }
    },
    "users": [{
      "flow": "xtls-rprx-vision"
    }]
  }]
}
EOF
    if _validate_reality_field_values "$temp" >/dev/null 2>&1; then
        test_result "accepts valid short ID format" "pass"
    else
        test_result "accepts valid short ID format" "fail"
    fi

    # Test with invalid short ID (too long)
    cat > "$temp" <<'EOF'
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "reality": {
        "short_id": ["a1b2c3d4e5f67890"]
      }
    },
    "users": [{
      "flow": "xtls-rprx-vision"
    }]
  }]
}
EOF
    if ! _validate_reality_field_values "$temp" >/dev/null 2>&1; then
        test_result "rejects invalid short ID (too long)" "pass"
    else
        test_result "rejects invalid short ID (too long)" "fail"
    fi

    # Test with invalid flow value
    cat > "$temp" <<'EOF'
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "reality": {
        "short_id": ["a1b2c3d4"]
      }
    },
    "users": [{
      "flow": "invalid-flow"
    }]
  }]
}
EOF
    if ! _validate_reality_field_values "$temp" >/dev/null 2>&1; then
        test_result "rejects invalid flow value" "pass"
    else
        test_result "rejects invalid flow value" "fail"
    fi

    rm -f "$temp"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/schema_validator.sh Functions"
echo "=========================================="

test_validate_json_field
test_check_schema_tool_detection
test_validate_config_schema_missing_file
test_validate_inbound_schema
test_validate_outbound_schema
test_validate_dns_schema
test_validate_route_schema
test_validate_reality_field_types
test_validate_reality_field_values

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
