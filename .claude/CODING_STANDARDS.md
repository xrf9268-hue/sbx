# Bash Coding Standards

## Mandatory Security Practices

- Always use strict mode: `set -euo pipefail`
- Quote all variables: `"$VARIABLE"` NOT `$VARIABLE`
- Safe expansion for constants: `${LOG_LEVEL:-warn}`
- Input validation: `sanitize_input "$user_input"`
- Secure temp files: Use `create_temp_file()` and `create_temp_dir()` helpers (NOT raw mktemp)
- JSON generation: Use `jq -n` (NEVER string concatenation)

## Error Handling Patterns

**Pattern A: Fatal errors (use die for immediate exit)**
```bash
command || die "Error message"
validate_config || die "Configuration invalid"
```
**Best for:** Unrecoverable errors, prerequisite failures

**Pattern B: Recoverable errors with detailed context**
```bash
if ! function_call; then
  err "Primary error message"
  err "Additional context line 1"
  err "Additional context line 2"
  return 1
fi
```
**Best for:** Multi-line error explanations, complex validation

**Pattern C: Recoverable errors with cleanup**
```bash
function_call || {
  err "Error message"
  cleanup_resources
  return 1
}
```
**Best for:** Errors requiring resource cleanup, single-line messages

**Pattern Selection Guidelines:**
- Use Pattern A when errors are fatal and script should exit immediately
- Use Pattern B when errors are recoverable and need detailed explanation
- Use Pattern C when errors need resource cleanup before returning
- NEVER mix patterns within the same function

## Common Bash Pitfalls

### Arithmetic in Strict Mode
```bash
# ❌ WRONG - Fails in bash -e when count=0
count=0
((count++))  # Returns 0 (old value), triggers exit

# ✅ CORRECT - Always safe
count=$((count + 1))  # Returns 1 (new value)
```

### Unbound Variables (CRITICAL - Repeatedly Caused Production Bugs)

⚠️ **THIS IS THE #1 SOURCE OF BUGS IN THIS CODEBASE** ⚠️

With `set -u` (strict mode), accessing undefined variables causes immediate script failure.

```bash
# ❌ WRONG - Variable assigned conditionally but used unconditionally
# This pattern has caused 3+ production bugs!
if [[ -n "$some_condition" ]]; then
    local url=$(fetch_url)  # Only assigned if condition true
fi

# BUG: If condition was false, url is completely undefined
if [[ -z "$url" ]]; then  # ERROR: bash: url: unbound variable
    url=$(fallback_url)   # This line never executes
fi
```

**Real production bugs caused by this:**
1. `url` variable (install_multi.sh:836) - Installation failed on 90% of systems
2. `HTTP_DOWNLOAD_TIMEOUT_SEC` - GitHub API completely broken
3. `get_file_size()` - Bootstrap failures preventing installation

```bash
# ✅ CORRECT - Always initialize local variables
local url=""  # ALWAYS initialize, even to empty string

if [[ -n "$some_condition" ]]; then
    url=$(fetch_url)
fi

# SAFE: url is always defined (empty or with value)
if [[ -z "$url" ]]; then
    url=$(fallback_url)
fi
```

**✅ CORRECT: Multiple variable initialization**
```bash
local var="" other="" more=""  # Initialize all at once
```

**✅ CORRECT: Command substitution (always safe)**
```bash
# Command substitution ALWAYS returns a value (even if empty)
local result=$(some_command)  # Never unbound, worst case is ""
```

**❌ WRONG: Conditional declaration**
```bash
if [[ -n "$condition" ]]; then
    local var="value"  # DON'T declare inside conditionals
fi
# var doesn't exist outside the if block!
```

**MANDATORY: Test before committing**
```bash
# Test with strict mode to catch unbound variables
bash -u install_multi.sh  # Must NOT show "unbound variable" errors
bash -u lib/your_module.sh  # Test individual modules

# Syntax validation
bash -n install_multi.sh
bash -n lib/your_module.sh
```

**Pre-commit checklist for local variables:**
- [ ] All local variables initialized at declaration
- [ ] No variables declared inside conditional blocks
- [ ] Tested with `bash -u` to verify no unbound variables
- [ ] ShellCheck passed with no errors

### ShellCheck Directives
```bash
# ✅ CORRECT - Avoid recursive analysis
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
```

## Code Quality Standards

- Use `[[ ]]` for conditionals (NOT `[ ]`)
- Local variables in functions: `local var_name="$1"`
- Check command success: `command || die "Error message"`
- NO Chinese characters in output (English only)
- Network operations: Always use timeout protection
- Error handling: Check jq operations with `|| die "message"`

## Common Validation Patterns

### Parameter Validation
```bash
# Single required parameter
require "DOMAIN" "$DOMAIN" "Domain" || return 1

# Multiple required parameters
require_all UUID PRIV SID DOMAIN || return 1

# Parameter with custom validation
require_valid "PORT" "$PORT" "Port number" validate_port || return 1
```

### File Integrity Validation
```bash
# Certificate/key file integrity
validate_file_integrity "$cert_path" "$key_path" || return 1

# Manual checks
[[ -f "$file" ]] || die "File not found: $file"
[[ -r "$file" ]] || die "File not readable: $file"
```

### Temp File Creation
```bash
# Secure temp file (600 permissions automatic)
tmpfile=$(create_temp_file "backup") || return 1

# Secure temp directory (700 permissions automatic)
tmpdir=$(create_temp_dir "restore") || return 1
```
