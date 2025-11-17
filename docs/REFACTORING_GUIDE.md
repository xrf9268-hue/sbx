# Refactoring Guide for sbx-lite Contributors

**Version:** 1.0
**Last Updated:** 2025-11-17
**Target Audience:** Developers contributing to sbx-lite

---

## Table of Contents

1. [Introduction](#introduction)
2. [Refactoring Principles](#refactoring-principles)
3. [Common Patterns](#common-patterns)
4. [Helper Functions](#helper-functions)
5. [Best Practices](#best-practices)
6. [Testing Requirements](#testing-requirements)
7. [Code Review Checklist](#code-review-checklist)

---

## Introduction

This guide documents the refactoring standards and patterns used in sbx-lite to maintain high code quality, reduce duplication, and improve maintainability.

**Goals:**
- Reduce code duplication through helper functions
- Extract magic numbers to named constants
- Standardize error handling and validation
- Maintain backward compatibility
- Ensure comprehensive testing

**Recent Improvements (Phase 1-3, 2025-11-17):**
- Created 10+ helper functions reducing duplication
- Extracted 20+ magic numbers to named constants
- Centralized error messaging system
- Comprehensive validation pipeline

---

## Refactoring Principles

### 1. DRY (Don't Repeat Yourself)

**Before:**
```bash
# In lib/backup.sh:34
temp_dir=$(mktemp -d) || die "Failed to create temp directory"

# In lib/caddy.sh:119
tmpdir=$(mktemp -d)
chmod 700 "$tmpdir"

# In lib/checksum.sh:148
checksum_file=$(mktemp) || {
    err "Failed to create temporary file"
    return 1
}
```

**After:**
```bash
# Created helper in lib/common.sh:243-309
temp_dir=$(create_temp_dir "backup") || return 1
tmpdir=$(create_temp_dir "caddy") || return 1
checksum_file=$(create_temp_file "checksum") || return 1
```

**Benefits:**
- ✅ Consistent error handling
- ✅ Automatic secure permissions (700/600)
- ✅ Detailed error diagnostics
- ✅ 4 instances reduced to 2 helper functions

### 2. Single Responsibility Principle

Each function should do one thing well.

**Good:**
```bash
# lib/validation.sh
validate_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}
```

**Bad:**
```bash
# Anti-pattern: Single function doing too much
validate_server() {
  validate_domain "$1" && validate_port "$2" && check_dns "$1" && test_connectivity "$1:$2"
}
```

### 3. Extract Magic Numbers

**Before:**
```bash
# lib/logging.sh:80
if [[ $((LOG_WRITE_COUNT % 100)) == 0 ]]; then
```

**After:**
```bash
# lib/common.sh:75
declare -r LOG_ROTATION_CHECK_INTERVAL=100

# lib/logging.sh:80
if [[ $((LOG_WRITE_COUNT % LOG_ROTATION_CHECK_INTERVAL)) == 0 ]]; then
```

**When to Extract:**
- Value appears multiple times
- Value has semantic meaning (not just 0, 1, or -1)
- Value might need tuning in the future

**When NOT to Extract:**
- Universal constants (0, 1, true, false)
- One-off values with no semantic meaning
- Values that are self-documenting in context

### 4. Fail Fast

Validate inputs early and fail with clear error messages.

**Good:**
```bash
validate_config_vars() {
  require_all UUID REALITY_PORT_CHOSEN PRIV SID || {
    err "Configuration validation failed - see errors above"
    return 1
  }
  return 0
}
```

**Bad:**
```bash
# Anti-pattern: Checking too late
write_config() {
  # ... 100 lines of processing ...
  if [[ -z "$UUID" ]]; then  # Should have checked at start!
    err "UUID not set"
    return 1
  fi
}
```

---

## Common Patterns

### Pattern 1: Parameter Validation

**Use Case:** Validate function parameters at entry point

**Helper Functions:**
```bash
# Single parameter
require "VAR_NAME" "$var_value" "Display name" || return 1

# Multiple parameters
require_all UUID DOMAIN PORT || return 1

# Parameter with custom validator
require_valid "PORT" "$PORT" "Port number" validate_port || return 1
```

**Example:**
```bash
setup_reality_inbound() {
  # Validate all required parameters at function entry
  require_all UUID PRIV SID REALITY_PORT_CHOSEN || return 1

  # Additional validation with custom function
  require_valid "SID" "$SID" "Short ID" validate_short_id || return 1

  # Proceed with logic...
}
```

### Pattern 2: File Integrity Validation

**Use Case:** Validate certificate/key pairs or critical files

**Helper Function:**
```bash
validate_file_integrity "$cert_fullchain" "$cert_key" || return 1
```

**What it checks:**
- ✅ Both files exist
- ✅ Both files are readable
- ✅ Certificate validity period
- ✅ Public key extraction and matching
- ✅ Detailed error messages on failure

**Example:**
```bash
setup_tls() {
  local cert="$1"
  local key="$2"

  # Comprehensive validation in one call
  validate_file_integrity "$cert" "$key" || return 1

  # Files are valid, proceed with TLS setup
  configure_tls_inbound "$cert" "$key"
}
```

### Pattern 3: Temporary File Creation

**Use Case:** Create secure temporary files/directories

**Helper Functions:**
```bash
# Temporary directory (700 permissions)
tmpdir=$(create_temp_dir "backup") || return 1

# Temporary file (600 permissions)
tmpfile=$(create_temp_file "config") || return 1
```

**What it provides:**
- ✅ Automatic secure permissions
- ✅ Consistent error handling
- ✅ Detailed error diagnostics (disk full, permissions, SELinux)
- ✅ Cleanup on failure

**Example:**
```bash
backup_create() {
  # Create secure temporary directory
  temp_dir=$(create_temp_dir "backup") || return 1

  # Automatic cleanup on exit
  trap 'rm -rf "$temp_dir"' EXIT

  # Use temp_dir for backup operations
  tar -czf "$temp_dir/backup.tar.gz" /etc/sing-box/
}
```

### Pattern 4: JSON Operations with Fallbacks

**Use Case:** Parse or build JSON with graceful degradation

**Helper Functions:**
```bash
# Parse JSON (tries jq, then python3, then python)
json_parse '.field.path' < input.json

# Build JSON
json_build '{"key": $value}' --arg value "string"
```

**What it provides:**
- ✅ Tries multiple tools (jq → python3 → python)
- ✅ Consistent error handling
- ✅ Works in environments without jq

**Example:**
```bash
get_config_value() {
  local config_file="$1"
  local json_path="$2"

  # Automatically uses best available JSON tool
  json_parse "$json_path" < "$config_file"
}
```

### Pattern 5: Cryptographic Operations

**Use Case:** Generate random values or compute checksums

**Helper Functions:**
```bash
# Generate random hex (tries openssl, then /dev/urandom)
sid=$(crypto_random_hex 4)  # 8-character hex string

# Compute SHA256 (tries openssl, then sha256sum, then shasum)
checksum=$(crypto_sha256 < file.bin)
```

**What it provides:**
- ✅ Tries multiple tools
- ✅ Consistent error handling
- ✅ Cryptographically secure random values

**Example:**
```bash
generate_credentials() {
  # Generate secure random short ID
  SHORT_ID=$(crypto_random_hex 4) || return 1
  validate_short_id "$SHORT_ID" || return 1

  echo "$SHORT_ID"
}
```

---

## Helper Functions

### Parameter Validation (lib/validation.sh)

#### `require()`
Validate a single required parameter.

**Signature:**
```bash
require "VAR_NAME" "$var_value" "Display name"
```

**Returns:**
- 0 if parameter is set and non-empty
- 1 if parameter is unset or empty (prints error)

**Example:**
```bash
require "DOMAIN" "$DOMAIN" "Domain" || return 1
```

#### `require_all()`
Validate multiple required parameters.

**Signature:**
```bash
require_all VAR1 VAR2 VAR3 ...
```

**Returns:**
- 0 if all parameters are set and non-empty
- 1 if any parameter is unset or empty (prints errors for all)

**Example:**
```bash
require_all UUID PRIV SID REALITY_PORT_CHOSEN || return 1
```

#### `require_valid()`
Validate parameter with custom validation function.

**Signature:**
```bash
require_valid "VAR_NAME" "$var_value" "Display name" validation_function
```

**Returns:**
- 0 if parameter passes validation
- 1 if parameter is empty or fails validation

**Example:**
```bash
require_valid "PORT" "$PORT" "Port number" validate_port || return 1
require_valid "SID" "$SID" "Short ID" validate_short_id || return 1
```

### File Operations (lib/validation.sh)

#### `validate_file_integrity()`
Comprehensive validation for certificate/key pairs.

**Signature:**
```bash
validate_file_integrity "$cert_path" "$key_path"
```

**Checks:**
1. Both files exist
2. Both files are readable
3. Certificate validity period (warns if < 30 days)
4. Public key extraction from certificate
5. Public key extraction from private key
6. Keys match (via OpenSSL comparison)

**Returns:**
- 0 if validation passes
- 1 if any check fails (with detailed error messages)

**Example:**
```bash
validate_file_integrity "$CERT_FULLCHAIN" "$CERT_KEY" || return 1
```

### Temporary Files (lib/common.sh)

#### `create_temp_dir()`
Create secure temporary directory with 700 permissions.

**Signature:**
```bash
tmpdir=$(create_temp_dir "prefix")
```

**Features:**
- ✅ Automatic 700 permissions
- ✅ Detailed error messages (disk full, permissions, SELinux)
- ✅ Cleanup on failure
- ✅ Returns absolute path

**Example:**
```bash
tmpdir=$(create_temp_dir "backup") || return 1
trap 'rm -rf "$tmpdir"' EXIT
```

#### `create_temp_file()`
Create secure temporary file with 600 permissions.

**Signature:**
```bash
tmpfile=$(create_temp_file "prefix")
```

**Features:**
- ✅ Automatic 600 permissions
- ✅ Detailed error messages
- ✅ Cleanup on failure
- ✅ Returns absolute path

**Example:**
```bash
tmpfile=$(create_temp_file "config") || return 1
trap 'rm -f "$tmpfile"' EXIT
```

### Tool Abstraction (lib/tools.sh)

#### `json_parse()`
Parse JSON with automatic fallback (jq → python3 → python).

**Signature:**
```bash
json_parse '.path.to.field' < input.json
# or
echo "$json_string" | json_parse '.field'
```

**Example:**
```bash
uuid=$(json_parse '.inbounds[0].users[0].uuid' < /etc/sing-box/config.json)
```

#### `json_build()`
Build JSON with automatic fallback.

**Signature:**
```bash
json_build '{"key": $value}' --arg value "string"
```

**Example:**
```bash
config=$(json_build '{"uuid": $uuid, "port": $port}' --arg uuid "$UUID" --argjson port 443)
```

#### `crypto_random_hex()`
Generate cryptographically secure random hex string.

**Signature:**
```bash
hex_string=$(crypto_random_hex <num_bytes>)
```

**Example:**
```bash
# Generate 8-character hex string (4 bytes)
SHORT_ID=$(crypto_random_hex 4)  # e.g., "a1b2c3d4"
```

#### `crypto_sha256()`
Compute SHA256 checksum with fallback.

**Signature:**
```bash
checksum=$(crypto_sha256 < file)
```

**Example:**
```bash
actual=$(crypto_sha256 < sing-box.tar.gz)
[[ "$actual" == "$expected" ]] || die "Checksum mismatch"
```

---

## Best Practices

### 1. Error Messages

**Good:**
```bash
err "Failed to generate Reality keypair"
err ""
err "This can happen if:"
err "  - sing-box binary is not installed"
err "  - sing-box version is too old (<1.8.0)"
err ""
err "Check binary:"
err "  which sing-box"
err "  sing-box version"
return 1
```

**Bad:**
```bash
err "Error"
return 1
```

### 2. Function Documentation

**Template:**
```bash
# Function name: Short one-line description
#
# Usage: function_name <arg1> <arg2>
#
# Arguments:
#   arg1 - Description of first argument
#   arg2 - Description of second argument
#
# Returns:
#   0 - Success
#   1 - Failure (with error message)
#
# Example:
#   function_name "value1" "value2" || return 1
function_name() {
  local arg1="$1"
  local arg2="$2"

  # Implementation...
}
```

### 3. Variable Naming

**Conventions:**
- `UPPERCASE_WITH_UNDERSCORES` - Constants and environment variables
- `lowercase_with_underscores` - Local variables and function names
- Use descriptive names (avoid `tmp`, `x`, `i` unless in loops)

**Good:**
```bash
readonly REALITY_SHORT_ID_MAX_LENGTH=8
local temp_config_file
local retry_count
```

**Bad:**
```bash
SID_MAX=8  # Not readonly
t="/tmp/config"  # Unclear name
c=0  # What does 'c' mean?
```

### 4. Testing

Every refactoring should include:

1. **Unit tests** for new helper functions
2. **Integration tests** to verify no regressions
3. **Syntax validation** (`bash -n script.sh`)
4. **ShellCheck** validation

**Example test:**
```bash
# tests/test_validation.sh
test_require_all_success() {
  export UUID="test-uuid"
  export PRIV="test-priv"
  export SID="test-sid"

  require_all UUID PRIV SID
  local result=$?

  assert_equals 0 "$result" "require_all should pass"
}

test_require_all_failure() {
  unset UUID
  export PRIV="test-priv"
  export SID="test-sid"

  require_all UUID PRIV SID 2>/dev/null
  local result=$?

  assert_equals 1 "$result" "require_all should fail"
}
```

### 5. Git Commits

**Commit message format:**
```
type(scope): short description

Detailed explanation of changes.

- Bullet point 1
- Bullet point 2

Related: #issue-number
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code refactoring
- `docs` - Documentation changes
- `test` - Test additions/changes
- `chore` - Maintenance tasks

**Example:**
```
refactor(common): consolidate temp file creation

Created create_temp_dir() and create_temp_file() helpers to replace
4 duplicate mktemp calls across lib/backup.sh, lib/caddy.sh, and
lib/checksum.sh.

Changes:
- Added create_temp_dir() with 700 permissions
- Added create_temp_file() with 600 permissions
- Refactored 4 callsites to use helpers
- Added detailed error diagnostics

Benefits:
- Reduced duplication (DRY principle)
- Consistent error handling
- Automatic secure permissions
- Better error messages for debugging

Related: CODE_QUALITY_IMPROVEMENT_PLAN.md Phase 3 Task 3.1
```

---

## Testing Requirements

### Unit Tests

Create tests in `tests/unit/` for new helper functions.

**Required:**
- ✅ Test success cases
- ✅ Test failure cases
- ✅ Test edge cases (empty strings, special characters)
- ✅ Test error messages

**Example:**
```bash
#!/usr/bin/env bash
# tests/unit/test_validation_helpers.sh

source lib/validation.sh

test_require_success() {
  export TEST_VAR="value"
  require "TEST_VAR" "$TEST_VAR" "Test Variable"
  assert_equals 0 $? "require should succeed"
}

test_require_failure_empty() {
  export TEST_VAR=""
  require "TEST_VAR" "$TEST_VAR" "Test Variable" 2>/dev/null
  assert_equals 1 $? "require should fail on empty"
}

test_require_failure_unset() {
  unset TEST_VAR
  require "TEST_VAR" "${TEST_VAR:-}" "Test Variable" 2>/dev/null
  assert_equals 1 $? "require should fail on unset"
}
```

### Integration Tests

Create tests in `tests/integration/` for end-to-end workflows.

**Required:**
- ✅ Test full installation flow
- ✅ Test configuration generation
- ✅ Test service startup
- ✅ Test export functionality

### Regression Tests

Before submitting:

```bash
# Run all tests
bash tests/test_reality.sh

# Syntax validation
bash -n install_multi.sh
bash -n lib/*.sh

# ShellCheck (if installed)
shellcheck install_multi.sh lib/*.sh
```

---

## Code Review Checklist

Before submitting a PR:

### Functionality
- [ ] Code works as intended
- [ ] All tests pass
- [ ] No regressions introduced
- [ ] Backward compatible

### Code Quality
- [ ] No code duplication
- [ ] Magic numbers extracted to constants
- [ ] Consistent error handling
- [ ] Helper functions used where appropriate
- [ ] Functions follow single responsibility

### Documentation
- [ ] Function documentation added/updated
- [ ] CLAUDE.md updated if needed
- [ ] README.md updated if user-facing
- [ ] Commit message follows convention

### Testing
- [ ] Unit tests added for new functions
- [ ] Integration tests cover changes
- [ ] All tests pass
- [ ] ShellCheck validation passes

### Style
- [ ] Consistent with existing code style
- [ ] Variable naming conventions followed
- [ ] Proper quoting and strict mode
- [ ] No shellcheck warnings

---

## Common Refactoring Patterns

### 1. Consolidating Duplicate Code

**Steps:**
1. Identify duplicate code blocks
2. Extract common logic to helper function
3. Add parameter validation
4. Add comprehensive error handling
5. Update callsites to use helper
6. Add unit tests
7. Update documentation

**Example:** See `create_temp_dir()` refactoring (Phase 3, Task 3.1)

### 2. Extracting Magic Numbers

**Steps:**
1. Identify hardcoded numbers with semantic meaning
2. Create constant with descriptive name
3. Add comment explaining value
4. Replace all usages
5. Verify tests still pass

**Example:** See `LOG_ROTATION_CHECK_INTERVAL` (Phase 3, Task 3.2)

### 3. Standardizing Error Messages

**Steps:**
1. Identify inconsistent error patterns
2. Use centralized error templates (lib/messages.sh)
3. Ensure errors are actionable
4. Provide diagnostic commands
5. Test error paths

**Example:** See error message enhancements (Phase 1, Task 1.5)

---

## Resources

### Documentation
- [CLAUDE.md](../CLAUDE.md) - Development guidelines
- [CODE_QUALITY_IMPROVEMENT_PLAN.md](CODE_QUALITY_IMPROVEMENT_PLAN.md) - Refactoring roadmap
- [REALITY_COMPLIANCE_REVIEW.md](REALITY_COMPLIANCE_REVIEW.md) - sing-box compliance

### Tools
- ShellCheck: https://www.shellcheck.net/
- Bash strict mode: `set -euo pipefail`
- Testing framework: `tests/test-runner.sh`

### References
- Bash style guide: https://google.github.io/styleguide/shellguide.html
- sing-box docs: https://sing-box.sagernet.org/

---

**Document Version:** 1.0
**Last Updated:** 2025-11-17
**Maintained by:** sbx-lite project
