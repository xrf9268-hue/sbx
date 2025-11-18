# Bootstrap Constants Testing

## Purpose

This directory contains `test_bootstrap_constants.sh`, a comprehensive test suite designed to **prevent recurring "unbound variable" errors** that have plagued this codebase multiple times.

## The Problem

The sbx-lite codebase uses `set -u` (strict mode), which causes immediate script failure when accessing undefined variables. During bootstrap (before module loading completes), some modules reference constants that haven't been defined yet, causing installation failures.

### Historical Failures

This exact issue has caused **3+ production bugs**:

1. **url variable** (install_multi.sh:836) - Installation failed on glibc systems
2. **HTTP_DOWNLOAD_TIMEOUT_SEC** - GitHub API fetches completely broken
3. **get_file_size()** - Bootstrap failures preventing installation
4. **REALITY_SHORT_ID_MIN_LENGTH** (2025-11-18) - Installation failed during validation
5. **REALITY_FLOW_VISION** (2025-11-18) - Installation failed during config generation
6. **REALITY_MAX_TIME_DIFF** (2025-11-18) - Installation failed during config generation

Each time was manually fixed, but **no automated test existed to prevent recurrence**.

## The Solution

`test_bootstrap_constants.sh` validates:

### 1. **Constant Registration** (Test 1-2)
- All bootstrap constants defined in `install_multi.sh` early section (lines 16-44)
- Constants defined **before** module loading (line < 100)

### 2. **Conditional Declarations** (Test 3-4)
- `lib/common.sh` uses conditional pattern to avoid conflicts:
  ```bash
  if [[ -z "${CONST_NAME:-}" ]]; then
    declare -r CONST_NAME=value
  fi
  ```
- No duplicate unconditional declarations

### 3. **Strict Mode Execution** (Test 5-7, 10)
- Script sources successfully with `bash -u`
- Bootstrap functions don't use unbound variables
- Full script help text works without errors

### 4. **Documentation** (Test 8-9)
- Early constants section properly documented
- CLAUDE.md documents bootstrap pattern

## What This Test Tracks

Currently tracking **15 bootstrap constants**:

| Category | Constants | Count |
|----------|-----------|-------|
| **Download** | `DOWNLOAD_CONNECT_TIMEOUT_SEC`, `DOWNLOAD_MAX_TIMEOUT_SEC`, `HTTP_DOWNLOAD_TIMEOUT_SEC`, `MIN_MODULE_FILE_SIZE_BYTES`, `MIN_MANAGER_FILE_SIZE_BYTES` | 5 |
| **Network** | `NETWORK_TIMEOUT_SEC` | 1 |
| **Reality Validation** | `REALITY_SHORT_ID_MIN_LENGTH`, `REALITY_SHORT_ID_MAX_LENGTH` | 2 |
| **Reality Config** | `REALITY_FLOW_VISION`, `REALITY_DEFAULT_HANDSHAKE_PORT`, `REALITY_MAX_TIME_DIFF`, `REALITY_ALPN_H2`, `REALITY_ALPN_HTTP11` | 5 |
| **Permissions** | `SECURE_DIR_PERMISSIONS`, `SECURE_FILE_PERMISSIONS` | 2 |

## How to Maintain

### When Adding a New Constant

If you add a constant to `lib/common.sh` that will be used during bootstrap:

1. **Add to `install_multi.sh` early constants section** (lines 16-44):
   ```bash
   readonly MY_NEW_CONSTANT=value
   ```

2. **Update `lib/common.sh` to use conditional declaration**:
   ```bash
   if [[ -z "${MY_NEW_CONSTANT:-}" ]]; then
     declare -r MY_NEW_CONSTANT=value
   fi
   ```

3. **Update `test_bootstrap_constants.sh` constant registry**:
   ```bash
   # Add to appropriate category array
   DOWNLOAD_CONSTANTS=(
       "DOWNLOAD_CONNECT_TIMEOUT_SEC"
       "MY_NEW_CONSTANT"  # <-- Add here
   )
   ```

4. **Run the test to verify**:
   ```bash
   bash tests/unit/test_bootstrap_constants.sh
   ```

### How to Identify if a Constant Needs Bootstrap Definition

A constant needs bootstrap definition if:

- ✅ It's defined in `lib/common.sh`
- ✅ It's used by any module loaded before line 542 in `install_multi.sh`
- ✅ It's used during: module download, network detection, config generation, validation

Common culprits:
- `lib/network.sh` - Runs during IP detection
- `lib/validation.sh` - Runs during input validation
- `lib/config.sh` - Runs during configuration generation
- `lib/download.sh` - Runs during module/binary download

## Running the Tests

### Standalone
```bash
bash tests/unit/test_bootstrap_constants.sh
```

### Via Test Runner
```bash
bash tests/test-runner.sh unit
```

### Expected Output
```
=== Bootstrap Constants Validation Test ===

  Test 1: All bootstrap constants defined in install_multi.sh ... ✓ PASS
  Test 2: Bootstrap constants defined before module loading ... ✓ PASS
  Test 3: Reality constants conditionally declared in lib/common.sh ... ✓ PASS
  Test 4: No duplicate constant declarations between files ... ✓ PASS
  Test 5: install_multi.sh sources successfully with strict mode ... ✓ PASS
  Test 6: lib/common.sh sources successfully after bootstrap constants ... ✓ PASS
  Test 7: Bootstrap functions don't use unbound variables ... ✓ PASS
  Test 8: Early constants section has documentation header ... ✓ PASS
  Test 9: CLAUDE.md documents bootstrap constant pattern ... ✓ PASS
  Test 10: install_multi.sh help works with bash -u (no unbound vars) ... ✓ PASS

=== Test Summary ===
Total constants tracked: 15
  - Download: 5
  - Network: 1
  - Reality validation: 2
  - Reality config: 5
  - Permissions: 2

Tests run:    10
Tests passed: 10
Tests failed: 0

✓ All bootstrap constant validation tests passed!
```

## CI/CD Integration

This test should be run:
- ✅ **Pre-commit** - Catch issues before code is committed
- ✅ **Pull Request** - Prevent merging broken bootstrap code
- ✅ **Scheduled** - Weekly validation that nothing regressed

### GitHub Actions Example

```yaml
- name: Validate Bootstrap Constants
  run: bash tests/unit/test_bootstrap_constants.sh
```

## Why This Matters

Without this test:
- ❌ **Installation fails silently** for end users
- ❌ **Same bugs recur** months later
- ❌ **Developer time wasted** on preventable issues
- ❌ **User trust eroded** by broken installations

With this test:
- ✅ **Errors caught during development** before code is committed
- ✅ **Clear remediation steps** when tests fail
- ✅ **Historical context preserved** in test documentation
- ✅ **Confidence in bootstrap reliability**

## References

- **Bootstrap Pattern Documentation**: `CLAUDE.md` (lines 106-195)
- **Installation Script**: `install_multi.sh` (lines 16-44 for early constants)
- **Common Constants**: `lib/common.sh` (lines 82-112 for Reality constants)
- **Historical Fixes**: `CHANGELOG.md` (search for "unbound variable")

---

**Last Updated**: 2025-11-18
**Test Version**: 1.0
**Maintained By**: sbx-lite project
