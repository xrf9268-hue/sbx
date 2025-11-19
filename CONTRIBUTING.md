# Contributing to sbx-lite

Thank you for contributing to sbx-lite! This document provides guidelines and setup instructions for developers.

## Table of Contents

- [Development Setup](#development-setup)
- [Git Hooks (REQUIRED)](#git-hooks-required)
- [Code Quality Standards](#code-quality-standards)
- [Testing Requirements](#testing-requirements)
- [Commit Guidelines](#commit-guidelines)
- [Common Issues](#common-issues)

---

## Development Setup

### Prerequisites

```bash
# Required
- bash 4.0+
- git

# Recommended
- jq (JSON processing)
- shellcheck (bash linting)
- openssl (cryptographic operations)
```

### Clone and Setup

```bash
# Clone the repository
git clone https://github.com/xrf9268-hue/sbx.git
cd sbx

# Install git hooks (REQUIRED - see next section)
bash hooks/install-hooks.sh
```

---

## Git Hooks (REQUIRED)

### ⚠️ CRITICAL: Install Pre-Commit Hooks

**This is MANDATORY, not optional.** The pre-commit hooks prevent recurring bugs that have caused **6+ production failures** in the past.

### Installation

```bash
# One-time setup
bash hooks/install-hooks.sh
```

**Output:**
```
=== sbx-lite Git Hooks Installer ===

[1/3] Installing pre-commit hook...
  ✓  Pre-commit hook installed

[2/3] Verifying installation...
  ✓  pre-commit hook is executable

[3/3] Testing hook functionality...
  ✓  Pre-commit hook has valid syntax

========================================
Installation Summary
----------------------------------------
✓ Git hooks successfully installed!

The following checks will run on every commit:
  1. Bash syntax validation
  2. Bootstrap constants validation
  3. Strict mode enforcement (set -euo pipefail)
  4. ShellCheck linting (if installed)
  5. Unbound variable detection (bash -u)
```

### What Gets Checked

Every time you run `git commit`, the hook automatically validates:

| Check | Purpose | Prevents |
|-------|---------|----------|
| **Bash Syntax** | All `.sh` files have valid syntax | Script execution errors |
| **Bootstrap Constants** | All constants properly defined | Unbound variable errors (6+ past bugs) |
| **Strict Mode** | All scripts use `set -euo pipefail` | Silent failures |
| **ShellCheck** | Linting for common issues | Code quality problems |
| **Unbound Variables** | Test with `bash -u` | Installation failures |

### Why This Matters

**Historical Failures Prevented by These Hooks:**

1. ✅ `url` variable - Installation failed on 90% of systems
2. ✅ `HTTP_DOWNLOAD_TIMEOUT_SEC` - API fetches completely broken
3. ✅ `get_file_size()` - Bootstrap failures
4. ✅ `REALITY_SHORT_ID_MIN_LENGTH` - Validation errors
5. ✅ `REALITY_FLOW_VISION` - Config generation failures
6. ✅ `REALITY_MAX_TIME_DIFF` - Config generation failures

**All of these would have been caught by the pre-commit hook.**

### Emergency Bypass

**Only use in true emergencies:**

```bash
git commit --no-verify -m "Emergency fix"
```

**⚠️ WARNING:** Bypassing hooks increases the risk of breaking production.

---

## Code Quality Standards

### Mandatory Bash Standards

All bash scripts MUST:

1. **Use strict mode:**
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   ```

2. **Quote all variables:**
   ```bash
   # ✓ CORRECT
   echo "$VAR"

   # ✗ WRONG
   echo $VAR
   ```

3. **Initialize all local variables:**
   ```bash
   # ✓ CORRECT
   local var=""  # Initialize even if assigned later
   if [[ condition ]]; then
     var=$(command)
   fi

   # ✗ WRONG (causes unbound variable errors)
   if [[ condition ]]; then
     local var=$(command)  # Only defined if condition true
   fi
   ```

4. **Use safe expansion for optional variables:**
   ```bash
   # ✓ CORRECT
   echo "${OPTIONAL_VAR:-default}"

   # ✗ WRONG
   echo "$OPTIONAL_VAR"  # Fails if unset
   ```

### Bootstrap Constants Pattern

When adding constants used during bootstrap (before module loading):

1. **Add to `install.sh` early section (lines 16-44):**
   ```bash
   readonly MY_NEW_CONSTANT=value
   ```

2. **Update `lib/common.sh` with conditional declaration:**
   ```bash
   if [[ -z "${MY_NEW_CONSTANT:-}" ]]; then
     declare -r MY_NEW_CONSTANT=value
   fi
   ```

3. **Update `tests/unit/test_bootstrap_constants.sh`:**
   ```bash
   # Add to appropriate category
   DOWNLOAD_CONSTANTS=(
       "EXISTING_CONSTANT"
       "MY_NEW_CONSTANT"  # Add here
   )
   ```

4. **Test:**
   ```bash
   bash tests/unit/test_bootstrap_constants.sh
   ```

**See:** `tests/unit/README_BOOTSTRAP_TESTS.md` for complete guide.

---

## Testing Requirements

### Before Committing

```bash
# Run all unit tests
bash tests/test-runner.sh unit

# Run specific bootstrap validation
bash tests/unit/test_bootstrap_constants.sh

# Test with strict mode
bash -u install.sh --help
```

### Test-Driven Development (TDD)

We practice TDD for all new features:

1. **Write tests first** (RED phase)
2. **Verify tests fail**
3. **Implement feature** (GREEN phase)
4. **Verify tests pass**
5. **Refactor** (keeping tests passing)

**Example:**
```bash
# 1. Create test file
tests/unit/test_new_feature.sh

# 2. Write failing tests
test_my_feature() {
  assert_equals "expected" "$(my_function)"
}

# 3. Run tests (should fail)
bash tests/unit/test_new_feature.sh
# Expected: FAIL

# 4. Implement feature
lib/new_feature.sh

# 5. Run tests again (should pass)
bash tests/unit/test_new_feature.sh
# Expected: PASS
```

### Test Coverage

All new code should have:
- ✅ Unit tests for individual functions
- ✅ Integration tests for workflows
- ✅ Bootstrap tests if adding early constants

---

## Commit Guidelines

### Conventional Commits

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): subject

body

footer
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `test`: Adding tests
- `refactor`: Code refactoring
- `docs`: Documentation only
- `chore`: Maintenance tasks

**Examples:**
```bash
git commit -m "feat: add backup encryption support"

git commit -m "fix: resolve Reality short ID validation error

Fixes bootstrap failure when REALITY_SHORT_ID_MIN_LENGTH was
accessed before module loading completed.

Changes:
- Added constant to install.sh early section
- Updated lib/common.sh to use conditional declaration
- Added test coverage in test_bootstrap_constants.sh

Closes #42"

git commit -m "test: add comprehensive bootstrap validation suite"
```

### Commit Message Quality

**Good commit messages:**
- ✅ Explain **why** not just **what**
- ✅ Reference related issues
- ✅ List specific changes
- ✅ Provide context for future developers

**Example:**
```
fix: resolve REALITY_FLOW_VISION unbound variable during bootstrap

Root cause: lib/config.sh referenced REALITY_FLOW_VISION during
configuration generation, but the constant wasn't defined until
lib/common.sh loaded (after bootstrap).

Solution: Added REALITY_FLOW_VISION to install.sh early
constants section following the established bootstrap pattern
documented in CLAUDE.md.

This prevents installation failures on systems without pre-existing
sing-box installations.

Testing:
- bash -u install.sh (no unbound variable errors)
- tests/unit/test_bootstrap_constants.sh (10/10 pass)

Related: Similar fix for REALITY_SHORT_ID_MIN_LENGTH in commit abc123
```

---

## Common Issues

### Issue: Pre-commit hook blocks my commit

**Cause:** Code quality checks failed.

**Solution:**
1. Read the error message carefully
2. Fix the issues listed
3. Commit again

**Example:**
```
✗ Pre-commit checks FAILED

[2/5] Validating bootstrap constants...
✗ FAIL: Bootstrap constants validation failed

Missing constants: MY_NEW_CONSTANT

Remediation:
  1. Add missing constant to install.sh early section (lines 16-44)
  2. Update lib/common.sh with conditional declaration
```

### Issue: "unbound variable" error during testing

**Cause:** Variable used before initialization.

**Solution:**
```bash
# ✗ WRONG
if [[ condition ]]; then
  local var=$(command)
fi
echo "$var"  # ERROR: var unbound if condition was false

# ✓ CORRECT
local var=""  # Initialize first
if [[ condition ]]; then
  var=$(command)
fi
echo "$var"  # SAFE: var always defined (empty or with value)
```

### Issue: Bootstrap constant validation fails

**Cause:** Added constant to `lib/common.sh` without updating bootstrap.

**Solution:** Follow the [Bootstrap Constants Pattern](#bootstrap-constants-pattern) above.

### Issue: ShellCheck warnings

**Cause:** Code doesn't follow bash best practices.

**Solution:**
```bash
# Run ShellCheck locally
shellcheck lib/my_module.sh

# Fix reported issues
# Common: Use [[ ]] instead of [ ]
# Common: Quote variables: "$VAR" not $VAR
# Common: Use lowercase for local variables
```

---

## Getting Help

### Documentation

- **Bootstrap Pattern**: `tests/unit/README_BOOTSTRAP_TESTS.md`
- **Developer Guide**: `CLAUDE.md`
- **Architecture**: `.claude/ARCHITECTURE.md`
- **Coding Standards**: `.claude/CODING_STANDARDS.md`

### Questions

- **GitHub Issues**: https://github.com/xrf9268-hue/sbx/issues
- **Pull Request Discussion**: Comment on your PR

### Reporting Bugs

When reporting bugs, include:
1. What you were trying to do
2. What happened instead
3. Steps to reproduce
4. System information (`uname -a`, `bash --version`)
5. Relevant log output

---

## Pull Request Process

1. **Install git hooks** (see above)
2. **Create feature branch**: `git checkout -b feature/my-feature`
3. **Make changes** following code standards
4. **Write tests** (TDD approach)
5. **Run local tests**: `bash tests/test-runner.sh unit`
6. **Commit** with clear messages
7. **Push**: `git push origin feature/my-feature`
8. **Create PR** on GitHub
9. **Wait for CI checks** (automated validation)
10. **Address review feedback**

---

## License

By contributing to sbx-lite, you agree that your contributions will be licensed under the MIT License.

---

**Last Updated:** 2025-11-18
**Questions?** Open an issue or comment on your PR.
