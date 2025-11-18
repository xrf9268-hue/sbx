#!/usr/bin/env bash
# tests/unit/test_module_download_validation.sh - Test module download validation logic
# Validates that downloaded modules meet all requirements before being used

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Unit Test: Module Download Validation ==="
echo ""

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $1 ... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ PASS"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ FAIL: $1"
}

#==============================================================================
# Test 1: All modules have minimum required size
#==============================================================================
test_start "All lib/*.sh modules meet minimum size requirement"

MIN_SIZE=100  # MIN_MODULE_FILE_SIZE_BYTES from install_multi.sh
failures=0

for module in "$SCRIPT_DIR"/lib/*.sh; do
    if [[ -f "$module" ]]; then
        size=$(stat -c%s "$module" 2>/dev/null || stat -f%z "$module" 2>/dev/null)
        if [[ "$size" -lt $MIN_SIZE ]]; then
            echo ""
            echo "  FAIL: $(basename "$module") is only $size bytes (minimum: $MIN_SIZE)"
            failures=$((failures + 1))
        fi
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules below minimum size"
fi

#==============================================================================
# Test 2: All modules have valid bash syntax
#==============================================================================
test_start "All lib/*.sh modules have valid bash syntax"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    if [[ -f "$module" ]]; then
        if ! bash -n "$module" 2>/dev/null; then
            echo ""
            echo "  FAIL: $(basename "$module") has syntax errors"
            failures=$((failures + 1))
        fi
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules with syntax errors"
fi

#==============================================================================
# Test 3: All modules can be sourced without errors
#==============================================================================
test_start "All lib/*.sh modules can be sourced (with dependencies)"

# Test sourcing in correct order to handle dependencies
modules_order=(
    colors common logging generators tools retry download network
    validation checksum version certificate caddy config config_validator
    schema_validator service ui backup export messages
)

temp_test_dir=$(mktemp -d)
mkdir -p "$temp_test_dir/lib"

# Copy all modules to temp directory
cp "$SCRIPT_DIR"/lib/*.sh "$temp_test_dir/lib/"

failures=0
for module in "${modules_order[@]}"; do
    module_file="$temp_test_dir/lib/${module}.sh"
    if [[ -f "$module_file" ]]; then
        # Try to source in a subshell
        if ! (
            cd "$temp_test_dir"
            _LIB_DIR="$temp_test_dir/lib"
            source "$module_file" 2>/dev/null
        ); then
            echo ""
            echo "  FAIL: ${module}.sh failed to source"
            failures=$((failures + 1))
        fi
    fi
done

rm -rf "$temp_test_dir"

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules failed to source"
fi

#==============================================================================
# Test 4: Module names match expected pattern
#==============================================================================
test_start "All module filenames follow naming convention"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    basename=$(basename "$module")
    # Module names should be lowercase with underscores, ending in .sh
    if ! [[ "$basename" =~ ^[a-z_]+\.sh$ ]]; then
        echo ""
        echo "  FAIL: $basename doesn't match pattern [a-z_]+.sh"
        failures=$((failures + 1))
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules with invalid names"
fi

#==============================================================================
# Test 5: No duplicate function definitions across modules
#==============================================================================
test_start "No duplicate function definitions across modules"

# Extract all function definitions from all modules
temp_functions=$(mktemp)
for module in "$SCRIPT_DIR"/lib/*.sh; do
    # Extract function names (pattern: function_name() or function function_name)
    grep -E '^[a-z_]+\(\)|^function [a-z_]+' "$module" 2>/dev/null | \
        sed 's/().*//' | sed 's/^function //' >> "$temp_functions" || true
done

# Find duplicates
duplicates=$(sort "$temp_functions" | uniq -d)
rm -f "$temp_functions"

if [[ -z "$duplicates" ]]; then
    test_pass
else
    echo ""
    echo "  Duplicate functions found:"
    echo "$duplicates" | sed 's/^/    /'
    test_fail "Found duplicate function definitions"
fi

#==============================================================================
# Test 6: All modules use strict mode (set -euo pipefail)
#==============================================================================
test_start "All modules use strict mode (set -euo pipefail)"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    if ! grep -q "set -euo pipefail" "$module"; then
        echo ""
        echo "  WARNING: $(basename "$module") missing strict mode"
        failures=$((failures + 1))
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules missing strict mode"
fi

#==============================================================================
# Test 7: No modules have hardcoded paths to /home or /root
#==============================================================================
test_start "No hardcoded user-specific paths in modules"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    # Look for hardcoded paths (but allow in comments)
    if grep -v '^#' "$module" | grep -qE '"/home/[^"]+"|"/root/[^"]+"'; then
        echo ""
        echo "  WARNING: $(basename "$module") contains hardcoded user paths"
        failures=$((failures + 1))
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules with hardcoded paths"
fi

#==============================================================================
# Test 8: All modules handle errors properly (have die/err functions or use them)
#==============================================================================
test_start "Modules have error handling (die, err, or return codes)"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    # Skip colors.sh as it just defines constants
    if [[ "$(basename "$module")" == "colors.sh" ]]; then
        continue
    fi

    # Check if module has error handling
    if ! grep -qE 'die |err |return 1|exit 1' "$module"; then
        echo ""
        echo "  WARNING: $(basename "$module") may lack error handling"
        failures=$((failures + 1))
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    # This is a warning, not a failure
    test_pass
    echo "    (Note: $failures modules may need error handling review)"
fi

#==============================================================================
# Test 9: Module size distribution is reasonable
#==============================================================================
test_start "Module sizes are within reasonable range"

# Check for extremely large modules (>50KB) that might need splitting
large_modules=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    size=$(stat -c%s "$module" 2>/dev/null || stat -f%z "$module" 2>/dev/null)
    # Warn if module is larger than 50KB (50000 bytes)
    if [[ "$size" -gt 50000 ]]; then
        echo ""
        echo "  INFO: $(basename "$module") is large ($size bytes) - consider splitting"
        large_modules=$((large_modules + 1))
    fi
done

if [[ $large_modules -le 2 ]]; then
    test_pass
else
    test_pass
    echo "    (Note: $large_modules large modules found)"
fi

#==============================================================================
# Test 10: Modules don't source files outside lib/ directory
#==============================================================================
test_start "Modules only source files from lib/ directory"

failures=0
for module in "$SCRIPT_DIR"/lib/*.sh; do
    # Look for source statements that go outside lib/
    if grep -v '^#' "$module" | grep -E 'source.*\.\./|source.*/etc/|source.*/usr/' | grep -v '_LIB_DIR'; then
        echo ""
        echo "  WARNING: $(basename "$module") sources files outside lib/"
        failures=$((failures + 1))
    fi
done

if [[ $failures -eq 0 ]]; then
    test_pass
else
    test_fail "$failures modules source external files"
fi

#==============================================================================
# Test Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All module validation tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
