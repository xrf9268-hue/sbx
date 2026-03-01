#!/usr/bin/env bash
# tests/unit/test_module_loading_sequence.sh - Test module loading order
# Ensures modules load in correct dependency order to prevent "file not found" errors

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Unit Test: Module Loading Sequence ==="
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
# Helper: Extract module list from install.sh
#==============================================================================
get_module_list() {
    grep "local modules=(.*)" "$SCRIPT_DIR/install.sh" | \
        grep "colors\|common" | \
        sed 's/.*local modules=(\(.*\))/\1/'
}

#==============================================================================
# Helper: Get dependencies for a module
#==============================================================================
get_module_dependencies() {
    local module="$1"
    local module_file="$SCRIPT_DIR/lib/${module}.sh"

    if [[ ! -f "$module_file" ]]; then
        return
    fi

    # Extract source statements
    grep 'source.*\${_LIB_DIR}/' "$module_file" 2>/dev/null | \
        sed -E 's/.*\$\{_LIB_DIR\}\/(.*\.sh).*/\1/' | \
        sed 's/\.sh$//' || true
}

#==============================================================================
# Test 1: Module list extraction works
#==============================================================================
test_start "Can extract module list from install.sh"

module_list=$(get_module_list)

if [[ -n "$module_list" ]]; then
    read -ra MODULES <<< "$module_list"
    if [[ ${#MODULES[@]} -gt 0 ]]; then
        test_pass
    else
        test_fail "Module array is empty"
    fi
else
    test_fail "Could not extract module list"
fi

# Save for other tests
read -ra MODULE_ARRAY <<< "$module_list"

#==============================================================================
# Test 2: colors.sh is first (no dependencies)
#==============================================================================
test_start "colors.sh is loaded first (it has no dependencies)"

if [[ "${MODULE_ARRAY[0]}" == "colors" ]]; then
    test_pass
else
    test_fail "First module should be 'colors', got '${MODULE_ARRAY[0]}'"
fi

#==============================================================================
# Test 3: common.sh comes after colors.sh
#==============================================================================
test_start "common.sh loads after colors.sh (dependency)"

colors_pos=-1
common_pos=-1

for i in "${!MODULE_ARRAY[@]}"; do
    if [[ "${MODULE_ARRAY[$i]}" == "colors" ]]; then
        colors_pos=$i
    elif [[ "${MODULE_ARRAY[$i]}" == "common" ]]; then
        common_pos=$i
    fi
done

if [[ $colors_pos -ge 0 && $common_pos -gt $colors_pos ]]; then
    test_pass
else
    test_fail "common (pos $common_pos) must come after colors (pos $colors_pos)"
fi

#==============================================================================
# Test 4: All dependencies load before dependents (or are sub-modules)
#==============================================================================
test_start "Module dependencies are properly ordered"

violations=0

# Modules that source sub-modules within themselves (acceptable pattern)
# Format: "parent:child1,child2"
known_sub_modules=(
    "common:logging,generators"
    "config:config_validator"
)

is_sub_module() {
    local parent="$1"
    local child="$2"

    for pattern in "${known_sub_modules[@]}"; do
        local p="${pattern%%:*}"
        local children="${pattern#*:}"

        if [[ "$p" == "$parent" ]]; then
            if [[ ",$children," == *",$child,"* ]]; then
                return 0
            fi
        fi
    done
    return 1
}

for i in "${!MODULE_ARRAY[@]}"; do
    module="${MODULE_ARRAY[$i]}"
    dependencies=$(get_module_dependencies "$module")

    if [[ -n "$dependencies" ]]; then
        while IFS= read -r dep; do
            # Find position of dependency
            dep_pos=-1
            for j in "${!MODULE_ARRAY[@]}"; do
                if [[ "${MODULE_ARRAY[$j]}" == "$dep" ]]; then
                    dep_pos=$j
                    break
                fi
            done

            # Check if dependency comes after current module
            if [[ $dep_pos -ge 0 && $dep_pos -gt $i ]]; then
                # Check if this is a known sub-module pattern
                if ! is_sub_module "$module" "$dep"; then
                    echo ""
                    echo "  VIOLATION: $module (pos $i) depends on $dep (pos $dep_pos)"
                    violations=$((violations + 1))
                fi
            fi
        done <<< "$dependencies"
    fi
done

if [[ $violations -eq 0 ]]; then
    test_pass
else
    test_fail "$violations dependency order violations"
fi

#==============================================================================
# Test 5: logging.sh and generators.sh come after common.sh
#==============================================================================
test_start "logging and generators load after common (loaded by common)"

common_pos=-1
logging_pos=-1
generators_pos=-1

for i in "${!MODULE_ARRAY[@]}"; do
    case "${MODULE_ARRAY[$i]}" in
        common) common_pos=$i ;;
        logging) logging_pos=$i ;;
        generators) generators_pos=$i ;;
    esac
done

violations=0
if [[ $logging_pos -ge 0 && $logging_pos -le $common_pos ]]; then
    echo ""
    echo "  VIOLATION: logging (pos $logging_pos) should be after common (pos $common_pos)"
    violations=$((violations + 1))
fi
if [[ $generators_pos -ge 0 && $generators_pos -le $common_pos ]]; then
    echo ""
    echo "  VIOLATION: generators (pos $generators_pos) should be after common (pos $common_pos)"
    violations=$((violations + 1))
fi

if [[ $violations -eq 0 ]]; then
    test_pass
else
    test_fail "$violations ordering violations for common sub-modules"
fi

#==============================================================================
# Test 6: Module count matches actual files in lib/
#==============================================================================
test_start "Module count in install.sh matches lib/*.sh files"

actual_count=$(find "$SCRIPT_DIR/lib" -name "*.sh" -type f | wc -l)
declared_count=${#MODULE_ARRAY[@]}

if [[ $actual_count -eq $declared_count ]]; then
    test_pass
else
    test_fail "Mismatch: $actual_count files in lib/, but $declared_count in module list"
    echo ""
    echo "  Files in lib/:"
    ls -1 "$SCRIPT_DIR/lib"/*.sh | xargs -n1 basename | sed 's/\.sh$//' | sort | sed 's/^/    /'
    echo ""
    echo "  Modules in download list:"
    printf '    %s\n' "${MODULE_ARRAY[@]}" | sort
fi

#==============================================================================
# Test 7: Test actual loading sequence (simulation)
#==============================================================================
test_start "Modules can be loaded in declared sequence"

temp_test_dir=$(mktemp -d)
mkdir -p "$temp_test_dir/lib"

# Copy all modules
cp "$SCRIPT_DIR"/lib/*.sh "$temp_test_dir/lib/"

# Try loading in order
load_errors=0
loaded_modules=()

for module in "${MODULE_ARRAY[@]}"; do
    module_file="$temp_test_dir/lib/${module}.sh"

    if [[ ! -f "$module_file" ]]; then
        echo ""
        echo "  ERROR: Module file missing: ${module}.sh"
        load_errors=$((load_errors + 1))
        continue
    fi

    # Try to source in isolated environment
    if ! (
        cd "$temp_test_dir"
        _LIB_DIR="$temp_test_dir/lib"

        # Source previously loaded modules first (to satisfy dependencies)
        for prev_module in "${loaded_modules[@]}"; do
            source "$temp_test_dir/lib/${prev_module}.sh" 2>/dev/null || true
        done

        # Now source current module
        source "$module_file" 2>/dev/null
    ); then
        echo ""
        echo "  ERROR: Failed to load ${module}.sh in sequence"
        load_errors=$((load_errors + 1))
    else
        loaded_modules+=("$module")
    fi
done

rm -rf "$temp_test_dir"

if [[ $load_errors -eq 0 ]]; then
    test_pass
else
    test_fail "$load_errors modules failed to load in sequence"
fi

#==============================================================================
# Test 8: No unexpected forward dependencies
#==============================================================================
test_start "No unexpected forward dependencies"

forward_deps=0

for i in "${!MODULE_ARRAY[@]}"; do
    module="${MODULE_ARRAY[$i]}"
    dependencies=$(get_module_dependencies "$module")

    if [[ -n "$dependencies" ]]; then
        while IFS= read -r dep; do
            # Find position of dependency
            for j in "${!MODULE_ARRAY[@]}"; do
                if [[ "${MODULE_ARRAY[$j]}" == "$dep" && $j -gt $i ]]; then
                    # Check if this is a known sub-module pattern (acceptable)
                    if ! is_sub_module "$module" "$dep"; then
                        echo ""
                        echo "  FORWARD DEP: $module (pos $i) depends on $dep (pos $j)"
                        forward_deps=$((forward_deps + 1))
                    fi
                fi
            done
        done <<< "$dependencies"
    fi
done

if [[ $forward_deps -eq 0 ]]; then
    test_pass
else
    test_fail "$forward_deps unexpected forward dependencies found"
fi

#==============================================================================
# Test 9: sbx-manager script download is mentioned
#==============================================================================
test_start "install.sh includes sbx-manager download logic"

if grep -q "sbx-manager" "$SCRIPT_DIR/install.sh"; then
    test_pass
else
    test_fail "sbx-manager download not found in installer"
fi

#==============================================================================
# Test 10: Parallel download function exists
#==============================================================================
test_start "Parallel download function (_download_modules_parallel) exists"

if grep -q "_download_modules_parallel" "$SCRIPT_DIR/install.sh"; then
    test_pass
else
    test_fail "Parallel download function not found"
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
    echo "✓ All module loading sequence tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
