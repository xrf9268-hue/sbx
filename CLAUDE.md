# CLAUDE.md

Project guidance for Claude Code when working with sbx-lite, a sing-box proxy deployment script with VLESS-REALITY protocol support.

## Documentation Index

**Critical Technical Guides:**
- Reality Protocol Configuration: @.claude/REALITY_CONFIG.md
- Code Architecture: @.claude/ARCHITECTURE.md
- Development Workflows: @.claude/WORKFLOWS.md
- Coding Standards: @.claude/CODING_STANDARDS.md
- Constants Reference: @.claude/CONSTANTS_REFERENCE.md

**Project Documentation:**
- Quick Start: @README.md
- Troubleshooting: @docs/REALITY_TROUBLESHOOTING.md
- Best Practices: @docs/REALITY_BEST_PRACTICES.md
- Xray Migration: @docs/SING_BOX_VS_XRAY.md
- Changelog: @CHANGELOG.md

**Official sing-box Docs:**
- Online: https://sing-box.sagernet.org/
- Local submodule: `docs/sing-box-official/`

## 🤖 Automated Quality Enforcement (NEW)

This project has **automated enforcement** at every stage to prevent recurring bugs:

### For Claude Code Users (Web/iOS)
**SessionStart hook runs automatically when you start a new session:**
- ✅ Installs git hooks (pre-commit validation)
- ✅ Verifies/installs dependencies (jq, openssl)
- ✅ Validates bootstrap constants (prevents unbound variable errors)
- ✅ Displays helpful project information

**PostToolUse hook runs after Edit/Write on shell scripts:**
- ✅ Formats code with shfmt (sequential: format → lint)
- ✅ Lints formatted result with shellcheck
- ✅ Prevents race conditions via single combined script
- ✅ Non-blocking if tools unavailable

**Configuration:** `.claude/settings.json` (see `.claude/README.md` and `.claude/docs/POSTTOOLUSE_HOOKS_FIX.md`)

### For All Developers
**Pre-commit hooks run automatically on every commit:**
```bash
# One-time setup (REQUIRED for contributors)
bash hooks/install-hooks.sh

# Then commit normally - hooks run automatically
git commit -m "my changes"
```

**What gets validated:**
1. Bash syntax (all .sh files)
2. Bootstrap constants (15 constants verified)
3. Strict mode enforcement (set -euo pipefail)
4. ShellCheck linting (if installed)
5. Unbound variable detection (bash -u)

**See:** `CONTRIBUTING.md` for complete developer guide.

### In CI/CD
GitHub Actions runs same validation on every push/PR.

**Impact:** The manual checklist below is now **automatically enforced**. You can still reference it for understanding, but the hooks catch issues before commit.

## ⚠️ CRITICAL WARNINGS - READ BEFORE CODING ⚠️

### DO NOT Make These Common Mistakes (Repeatedly Caused Bugs)

**1. UNINITIALIZED LOCAL VARIABLES** 🔴 **MOST COMMON ERROR**

This codebase uses `set -u` (strict mode). **ALL local variables MUST be initialized**, even to empty string.

```bash
❌ WRONG - Causes "unbound variable" errors:
if [[ -n "$condition" ]]; then
    local var=$(command)  # Only assigned if condition true
fi
if [[ -z "$var" ]]; then  # ERROR: var unbound if condition was false
    ...
fi

✅ CORRECT - Always initialize:
local var=""  # Initialize at declaration
if [[ -n "$condition" ]]; then
    var=$(command)
fi
if [[ -z "$var" ]]; then  # SAFE: var always defined
    ...
fi
```

**Bugs caused by this mistake:**
- `url` variable - Installation failed on glibc systems (commit 49e4b91)
- `HTTP_DOWNLOAD_TIMEOUT_SEC` - API fetches failed (commit a078273)
- `get_file_size()` - Bootstrap failures (multiple commits)

**How to prevent:**
1. Initialize all local variables: `local var="" other="" more=""`
2. Test with strict mode: `bash -u install_multi.sh`
3. Check the pre-commit checklist in "Bootstrapping Fixes" section below

**2. Reality Protocol Configuration Errors**

See @.claude/REALITY_CONFIG.md for full details:
- Short ID: MUST be 8 chars max (use `openssl rand -hex 4`)
- Reality: MUST be nested under `tls.reality` (NOT top-level)
- Flow: In `users[]` array (NOT at inbound level)

**3. Validation After Changes**

Always run after ANY configuration or code change:
```bash
sing-box check -c /etc/sing-box/config.json
bash -u install_multi.sh  # Test for unbound variables
bash -n install_multi.sh  # Syntax check
```

**4. Claude Code Hooks - Parallel Execution Race Conditions** 🔴 **CRITICAL**

Multiple hooks under the same matcher run **in parallel** (per Claude Code design). This causes race conditions if hooks share resources.

```bash
❌ WRONG - Parallel hooks cause race conditions:
"PostToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [
    {"command": "format-file.sh"},  # Modifies file
    {"command": "lint-file.sh"}     # Reads file (PARALLEL!)
  ]
}]

# Race Condition 1: stdin consumption
# Both hooks do INPUT=$(cat), competing for same stdin stream
# Result: One gets all data, other gets nothing/partial

# Race Condition 2: File modification
# format-file.sh writes file while lint-file.sh reads it
# Result: Lint may read unformatted/partially-written/corrupted data

✅ CORRECT - Single hook with sequential operations:
"PostToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [
    {"command": "format-and-lint.sh"}  # Does both sequentially
  ]
}]

# Inside format-and-lint.sh:
INPUT=$(cat)  # Read stdin ONCE
# Step 1: Format file
# Step 2: Lint formatted result
```

**Bugs caused by this mistake:**
- PostToolUse hooks had stdin consumption races (commit 7e43091)
- File modification races caused non-deterministic lint results
- No execution order guarantee for dependent operations

**How to prevent:**
1. **Never** create multiple hooks that share resources (stdin, files, etc.)
2. Combine dependent operations into single sequential script
3. Read stdin only ONCE at start of script
4. Test hook concurrency with rapid file edits
5. See `.claude/docs/POSTTOOLUSE_HOOKS_FIX.md` for detailed analysis

**Key principle:** Parallel hooks = independent operations only (e.g., notify Slack + log to file). Sequential operations = single hook script.

## Quick Commands

**Essential Development Commands:**
```bash
# Testing & Validation (Run after ANY config change)
sing-box check -c /etc/sing-box/config.json  # MUST pass before restart
systemctl restart sing-box && sleep 3 && systemctl status sing-box
journalctl -u sing-box -f  # Monitor for 10-15 seconds

# Test installation
bash install_multi.sh  # Reality-only (auto-detect IP)
DOMAIN=test.domain.com bash install_multi.sh  # Full setup

# Unit tests
bash tests/test_reality.sh

# Integration tests
bash tests/integration/test_reality_connection.sh

# Management (post-installation)
sbx info     # View URIs and config
sbx status   # Check service
sbx check    # Validate config
sbx restart  # Restart service
```

## Critical Rules Summary

**Reality Protocol (sing-box 1.12.0+):**
- Short ID: `openssl rand -hex 4` (8 chars max, NOT 16 like Xray)
- Reality nesting: MUST be under `tls.reality` (NOT top-level)
- Flow field: In `users[]` array (NOT at inbound level)
- Short ID type: Array `["a1b2c3d4"]` (NOT string)
- Full details: @.claude/REALITY_CONFIG.md

**Mandatory Validation:**
```bash
sing-box check -c /etc/sing-box/config.json || die "Config invalid"
jq -e '.inbounds[0].tls.reality' /etc/sing-box/config.json || die "Reality not nested"
systemctl restart sing-box && sleep 3 && systemctl is-active sing-box
```

**Development Workflow:**
- Practice TDD: Write tests first, verify they fail (RED), implement (GREEN), refactor
- Full TDD guide: @.claude/WORKFLOWS.md
- Coding standards: @.claude/CODING_STANDARDS.md

## File Locations

### Runtime Files
- Binary: `/usr/local/bin/sing-box`
- Config: `/etc/sing-box/config.json`
- Client info: `/etc/sing-box/client-info.txt`
- Service: `/etc/systemd/system/sing-box.service`
- Certificates: `/etc/ssl/sbx/<domain>/`

### Management Tools
- Manager: `/usr/local/bin/sbx-manager`
- Symlink: `/usr/local/bin/sbx`
- Libraries: `/usr/local/lib/sbx/*.sh`

### Backup & Data
- Backups: `/var/backups/sbx/`
- Format: `sbx-backup-YYYYMMDD-HHMMSS.tar.gz[.enc]`
- Retention: 30 days

## Environment Variables (All Optional)

```bash
# Domain/IP (auto-detects if omitted)
DOMAIN=your.domain.com    # Full setup (WS-TLS + Hysteria2)
DOMAIN=1.2.3.4            # Reality-only with explicit IP

# Version
SINGBOX_VERSION=stable    # Latest stable (default)
SINGBOX_VERSION=v1.10.7   # Specific version

# Certificate
CERT_MODE=caddy           # Auto TLS (default)
CERT_FULLCHAIN=/path/fullchain.pem
CERT_KEY=/path/privkey.pem

# Ports
REALITY_PORT=443          # Default 443
WS_PORT=8444              # Default 8444
HY2_PORT=8443             # Default 8443

# Debugging
DEBUG=1                   # Enable debug output
LOG_TIMESTAMPS=1          # Add timestamps
LOG_FILE=/path/file.log   # Log to file
```

## Bootstrapping Fixes

### Bootstrap Pattern (Lessons Learned)

When adding constants or functions that are:
1. Defined in `lib/common.sh` or other modules
2. Used during early bootstrap (before module loading)
3. Called from sourced modules during initialization

**Apply this pattern:**
1. Add to `install_multi.sh` early constants section (lines 16-29)
2. Make module declaration conditional: `if [[ -z "${VAR:-}" ]]; then declare -r VAR=value; fi`
3. Document in commit message and CLAUDE.md
4. Test bootstrap scenario: one-liner installation without git clone

**Implemented Fixes:**
- Fix 1: `get_file_size()` function - Available before module loading
- Fix 2: `HTTP_DOWNLOAD_TIMEOUT_SEC` constant - Available for safe_http_get() (commit a078273)
- Fix 3: `url` variable initialization - Prevent unbound variable in conditional flow (install_multi.sh:836)

### Variable Initialization Pattern (CRITICAL - DO NOT SKIP)

⚠️ **THIS PATTERN HAS CAUSED MULTIPLE RECURRING BUGS - READ CAREFULLY** ⚠️

**CRITICAL RULE**: With `set -u` (strict mode), **ALL local variables MUST be initialized at declaration**, even if just to an empty string. Failure to do this causes "unbound variable" errors.

**❌ WRONG PATTERN (Has caused 3+ production bugs):**
```bash
# DANGEROUS: Variable only assigned in conditional block
if [[ -n "$some_condition" ]]; then
    local var=$(some_command)  # Only assigned if condition true!
fi

# FAILS: If condition was false, var is completely unbound
if [[ -z "$var" ]]; then  # ERROR: bash: var: unbound variable
    ...
fi
```

**Real-world failures this pattern has caused:**
- `url` variable (install_multi.sh:836) - Installation failed on glibc systems
- `HTTP_DOWNLOAD_TIMEOUT_SEC` - GitHub API fetches failed
- Multiple other instances caught during audits

**✅ CORRECT PATTERN (Always use this):**
```bash
# SAFE: Variable declared and initialized
local var=""  # Initialize to empty string

# Assignment in conditional block
if [[ -n "$some_condition" ]]; then
    var=$(some_command)
fi

# SAFE: var is always defined (empty or with value)
if [[ -z "$var" ]]; then  # Works correctly
    ...
fi
```

**✅ ALSO CORRECT: Initialize multiple at once**
```bash
local var="" other="" more="" all="" initialized=""
```

**✅ ALSO CORRECT: Initialize with command substitution**
```bash
# This is safe because command substitution always returns a value (even if empty)
local result=$(some_command)  # Never unbound, worst case is empty string
```

**🚨 PRE-COMMIT VALIDATION (AUTOMATED) 🚨**

**Good news:** This checklist is now **automatically enforced** by pre-commit hooks!

Install once with: `bash hooks/install-hooks.sh`

The hooks automatically verify:
1. ✅ All local variables declared with `local`
2. ✅ Variables initialized at declaration
3. ✅ No unbound variable usage (`bash -u` test)
4. ✅ Bash syntax validation (`bash -n`)
5. ✅ Strict mode enabled (`set -euo pipefail`)

**For reference (auto-checked by hooks):**
Before committing code with local variables:
1. [ ] Did I declare the variable with `local`?
2. [ ] Did I initialize it at declaration? `local var=""`
3. [ ] If assigned in a conditional, is it used outside that conditional?
4. [ ] If yes to #3, did I verify initialization at declaration?
5. [ ] Did I test with `bash -u script.sh`? ← **Hooks do this automatically**

**Manual testing (if needed):**
```bash
# Test your changes with strict mode (hooks run this automatically)
bash -u install_multi.sh  # Should NOT show "unbound variable" errors
bash -n install_multi.sh  # Should pass syntax check
```

**Error Signatures:**
```
# get_file_size error
get_file_size: command not found

# HTTP_DOWNLOAD_TIMEOUT_SEC error
HTTP_DOWNLOAD_TIMEOUT_SEC: unbound variable
[ERR] Failed to fetch release information from GitHub API

# url unbound variable error
/dev/fd/63: line 870: url: unbound variable
[ERR] Script execution failed with exit code 1
```

## Recent Improvements (2025-11-18)

### Optional jq Dependency
✅ Implemented - Works on minimal systems (Alpine, BusyBox, containers)
- Fallback chain: jq → python3 → python2 (via lib/tools.sh)
- Faster installation (no package manager calls)
- Full functionality maintained with python fallbacks

### Alpine Linux Support (musl libc Detection)
✅ Implemented - Proper support for Alpine/musl-based systems
- Auto-detects musl vs glibc with `detect_libc()` function
- Downloads correct binary variant (linux-amd64 vs linux-amd64-musl)
- Testing: `docker run --rm -it alpine:latest sh -c "apk add bash curl && curl -fsSL ... | bash"`

## Version Information

- **Current:** v2.2.0 (Phase 4 complete)
- **Architecture:** Modular v2.0 (11 library modules, 3,523 lines)
- **sing-box:** 1.8.0+ (recommended 1.12.0+)
- **License:** MIT
