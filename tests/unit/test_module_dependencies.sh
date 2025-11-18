#!/usr/bin/env bash
# tests/unit/test_module_dependencies.sh - Verify all sourced modules are in download list
# This test prevents the "colors.sh not found" bug from happening again

set -eo pipefail  # Use -e -o pipefail but not -u to avoid issues with empty arrays

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Unit Test: Module Dependency Validation ==="
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
# Test 1: Extract module list from install_multi.sh
#==============================================================================
test_start "Extract module list from install_multi.sh"

# Extract the module list from install_multi.sh - use simpler approach
module_line=$(grep "local modules=(.*)" "$SCRIPT_DIR/install_multi.sh" | grep "colors\|common")

if [[ -n "$module_line" ]]; then
    # Extract just the module names between parentheses
    module_list=$(echo "$module_line" | sed 's/.*local modules=(\(.*\))/\1/')
    # Convert to array
    read -ra DOWNLOAD_MODULES <<< "$module_list"
    test_pass
else
    test_fail "Could not extract module list"
    exit 1
fi

#==============================================================================
# Test 2: Find all 'source' statements in lib/ directory
#==============================================================================
test_start "Find all module source statements"

# Find all source statements that reference other modules
# Pattern: source "${_LIB_DIR}/module.sh" or source "./module.sh"
sourced_modules=$(grep -rh 'source.*\${_LIB_DIR}/.*\.sh' "$SCRIPT_DIR/lib/" 2>/dev/null | \
    sed -E 's/.*source.*\$\{_LIB_DIR\}\/(.*\.sh).*/\1/' | \
    sed 's/\.sh$//' | \
    sort -u)

if [[ -n "$sourced_modules" ]]; then
    test_pass
    readarray -t SOURCED_MODULES <<< "$sourced_modules"
else
    test_fail "Could not find sourced modules"
fi

#==============================================================================
# Test 3: Verify all sourced modules are in download list
#==============================================================================
test_start "All sourced modules are in download list"

missing_modules=()
for sourced in "${SOURCED_MODULES[@]}"; do
    found=0
    for downloaded in "${DOWNLOAD_MODULES[@]}"; do
        if [[ "$sourced" == "$downloaded" ]]; then
            found=1
            break
        fi
    done

    if [[ $found -eq 0 ]]; then
        missing_modules+=("$sourced")
    fi
done

if [[ ${#missing_modules[@]} -eq 0 ]]; then
    test_pass
else
    test_fail "Missing modules in download list: ${missing_modules[*]}"
    echo ""
    echo "  Modules sourced in lib/ but NOT in install_multi.sh download list:"
    for mod in "${missing_modules[@]}"; do
        echo "    • $mod"
        # Show which file sources this module
        grep -rn "source.*${mod}.sh" "$SCRIPT_DIR/lib/" | head -3 | sed 's/^/      /'
    done
    echo ""
fi

#==============================================================================
# Test 4: Verify module count matches
#==============================================================================
test_start "Module count in install_multi.sh matches actual files"

actual_module_count=$(find "$SCRIPT_DIR/lib/" -name "*.sh" -type f | wc -l)
declared_module_count=${#DOWNLOAD_MODULES[@]}

if [[ $actual_module_count -eq $declared_module_count ]]; then
    test_pass
else
    test_fail "Mismatch: $actual_module_count files in lib/, but $declared_module_count in download list"
    echo ""
    echo "  Files in lib/ directory:"
    ls -1 "$SCRIPT_DIR/lib/"*.sh | xargs -n1 basename | sed 's/\.sh$//' | sed 's/^/    • /'
    echo ""
    echo "  Modules in download list:"
    printf '    • %s\n' "${DOWNLOAD_MODULES[@]}"
    echo ""
fi

#==============================================================================
# Test 5: Check for circular dependencies
#==============================================================================
test_start "No circular dependencies detected"

circular_found=0
for module in "${DOWNLOAD_MODULES[@]}"; do
    module_file="$SCRIPT_DIR/lib/${module}.sh"
    if [[ -f "$module_file" ]]; then
        # Check if module sources itself
        if grep -q "source.*${module}.sh" "$module_file" 2>/dev/null; then
            echo ""
            echo "  WARNING: $module.sh sources itself (circular dependency)"
            circular_found=1
        fi
    fi
done

if [[ $circular_found -eq 0 ]]; then
    test_pass
else
    test_fail "Circular dependencies detected"
fi

#==============================================================================
# Test 6: Verify common.sh dependencies are first in list
#==============================================================================
test_start "Dependencies loaded before dependents"

# common.sh sources colors.sh, so colors should come before common
colors_pos=-1
common_pos=-1

for i in "${!DOWNLOAD_MODULES[@]}"; do
    if [[ "${DOWNLOAD_MODULES[$i]}" == "colors" ]]; then
        colors_pos=$i
    elif [[ "${DOWNLOAD_MODULES[$i]}" == "common" ]]; then
        common_pos=$i
    fi
done

if [[ $colors_pos -ge 0 && $common_pos -ge 0 && $colors_pos -lt $common_pos ]]; then
    test_pass
elif [[ $colors_pos -lt 0 ]]; then
    test_fail "colors module not found in download list"
elif [[ $common_pos -lt 0 ]]; then
    test_fail "common module not found in download list"
else
    test_fail "colors (pos $colors_pos) must come before common (pos $common_pos)"
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
    echo "✓ All module dependency tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
