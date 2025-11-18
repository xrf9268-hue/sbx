# CLAUDE.md

Project guidance for Claude Code when working with sbx-lite, a sing-box proxy deployment script with VLESS-REALITY protocol support.

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

## Critical Implementation Rules

### Reality Protocol Configuration (sing-box 1.12.0+)

**MUST follow these requirements:**
- Short ID: `openssl rand -hex 4` (8 chars, NOT 16 like Xray)
- Short ID validation: `[[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]]` immediately after generation
- Reality MUST be nested under `tls.reality` (NOT top-level)
- Flow field: `"flow": "xtls-rprx-vision"` in users array (NOT at inbound level)
- Short ID type: Array format `["a1b2c3d4"]` (NOT string)
- Transport: Vision flow requires TCP with Reality security
- Keypair: Use `sing-box generate reality-keypair` (NOT openssl)

**Mandatory Post-Configuration Validation:**
```bash
# 1. Validate syntax
sing-box check -c /etc/sing-box/config.json || die "Config invalid"

# 2. Verify structure
jq -e '.inbounds[0].tls.reality' /etc/sing-box/config.json || die "Reality not nested"

# 3. Check short_id type
[[ $(jq -r '.inbounds[0].tls.reality.short_id | type' /etc/sing-box/config.json) == "array" ]] || die "Short ID must be array"

# 4. Restart service and verify
systemctl restart sing-box && sleep 3
systemctl is-active sing-box || die "Service failed"
```

### sing-box 1.12.0+ Compliance

**NEVER use deprecated fields:**
- ❌ `sniff`, `sniff_override_destination`, `domain_strategy` in inbounds
- ❌ `domain_strategy` in outbounds (causes IPv6 failures)

**ALWAYS use:**
- ✅ `dns.strategy: "ipv4_only"` for IPv4-only networks (global setting)
- ✅ `listen: "::"` for dual-stack (NEVER "0.0.0.0")
- ✅ Route configuration with `action: "sniff"` and `action: "hijack-dns"`

### Reality Configuration Checklist

**When creating/modifying Reality configs:**
1. Generate materials with proper tools: `UUID`, `KEYPAIR`, `SID`
2. Validate materials immediately (especially short_id length)
3. Build config with validated materials
4. Verify structure: `jq -e '.tls.reality'`
5. Write and validate: `sing-box check`
6. Apply and verify service starts
7. Monitor logs for 10-15 seconds

## Code Architecture

### Modular Structure (v2.2.0)

**Main:** `install_multi.sh` (~583 lines) - Orchestrates installation
**Library:** `lib/` directory (11 modules, 3,523 lines total)

**Key Modules:**
- `lib/common.sh` - Logging, utilities, constants
- `lib/network.sh` - IP detection, port allocation
- `lib/validation.sh` - Input sanitization, security
- `lib/config.sh` - sing-box JSON generation
- `lib/service.sh` - systemd management
- `lib/backup.sh` - Backup/restore operations
- `lib/export.sh` - Client config export

**Security-Critical Functions:**
- `sanitize_input()` - Remove shell metacharacters (lib/validation.sh)
- `validate_short_id()` - Enforce 8-char limit (lib/validation.sh)
- `verify_singbox_binary()` - SHA256 verification (lib/checksum.sh)
- `write_config()` - Atomic config writes (lib/config.sh)
- `cleanup()` - Secure temp file cleanup (lib/common.sh)

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

## Documentation References

**User Documentation:**
- @README.md - Quick start, commands, client setup
- @docs/REALITY_TROUBLESHOOTING.md - Common issues, solutions
- @CHANGELOG.md - Version history, migrations

**Developer Documentation:**
- @docs/REALITY_BEST_PRACTICES.md - Production deployment patterns
- @docs/SING_BOX_VS_XRAY.md - Xray migration guide

**Official sing-box Docs (Git Submodule):**
```bash
# Initialize submodule
git submodule update --init --recursive

# Key paths
docs/sing-box-official/docs/configuration/inbound/vless.md
docs/sing-box-official/docs/configuration/shared/tls.md
docs/sing-box-official/docs/migration.md
```

**Online:** https://sing-box.sagernet.org/

## Coding Standards & Reference

**Detailed coding standards:** @.claude/CODING_STANDARDS.md
**Constants reference:** @.claude/CONSTANTS_REFERENCE.md

## Common Workflows

### Adding a New Feature (TDD Workflow)

**Phase 1: Explore** (Research existing code)
1. Use Task tool with Explore agent to understand current implementation
2. Read relevant modules: `@lib/[module].sh`
3. Review best practices: `@docs/REALITY_BEST_PRACTICES.md`

**Phase 2: Plan** (Design before coding)
1. Use thinking mode: "think: Design [feature] considering [constraints]"
2. Document approach in comments or temporary planning file
3. Identify test cases and edge cases

**Phase 3: Test** (Write tests first)
1. Create test file: `tests/unit/test_[feature].sh`
2. Write failing tests based on requirements
3. Verify tests fail (RED phase)
4. **Commit tests:** `git commit -m "test: add tests for [feature]"`

**Phase 4: Code** (Implement feature)
1. Write minimal code to pass tests
2. Follow standards: `@.claude/CODING_STANDARDS.md`
3. Iterate: code → run tests → adjust → repeat
4. Verify all tests pass (GREEN phase)
5. **Commit implementation:** `git commit -m "feat: implement [feature]"`

**Phase 5: Refactor** (Improve quality)
1. Extract magic numbers to constants
2. Improve error messages using `lib/messages.sh`
3. Add documentation comments
4. Run tests after each refactoring
5. **Commit improvements:** `git commit -m "refactor: improve [aspect]"`

**Phase 6: Document** (Update docs)
1. Update relevant documentation files
2. Add usage examples if user-facing
3. **Commit docs:** `git commit -m "docs: document [feature]"`

### Modifying Reality Configuration
1. Read current config structure
2. Generate materials with validation
3. Create config using jq (never string manipulation)
4. Validate: `sing-box check -c /etc/sing-box/config.json`
5. Verify structure (Reality nesting, short_id type, flow field)
6. Restart: `systemctl restart sing-box`
7. Monitor: `journalctl -u sing-box -f` for 10-15 seconds

### Debugging Installation
```bash
# Enable full debug logging
DEBUG=1 LOG_TIMESTAMPS=1 LOG_FILE=/tmp/debug.log bash install_multi.sh

# Check for errors
grep -i error /tmp/debug.log

# Test in strict mode (like CI)
bash -e install_multi.sh
```

## Development Workflow (Test-Driven)

### TDD Pattern (Recommended for All Features)

**IMPORTANT:** Always practice Test-Driven Development for new features and bug fixes.

**Step 1: Write Tests First**
```bash
# Tell Claude explicitly that you're practicing TDD
# This prevents Claude from creating mock implementations

# Example prompt:
# "We're practicing TDD. Write tests for [feature] based on these requirements:
# - Input: [description]
# - Expected output: [description]
# - Edge cases: [list]
# Do NOT implement the feature yet - only write failing tests."

# Create test file
tests/unit/test_new_feature.sh
```

**Step 2: Verify Tests Fail**
```bash
# Run tests - they MUST fail initially
bash tests/unit/test_new_feature.sh

# Expected output: Test failures (RED phase)
# If tests pass, they're incorrectly implemented!
```

**Step 3: Implement Feature**
```bash
# Now write minimal code to pass tests
# Iterate: code → run tests → adjust → repeat
lib/new_feature.sh
```

**Step 4: Verify Tests Pass**
```bash
# Run tests again - should all pass now (GREEN phase)
bash tests/unit/test_new_feature.sh

# If failures remain, continue iteration
```

**Step 5: Refactor (Optional)**
```bash
# Improve code quality while keeping tests passing
# REFACTOR phase - tests provide safety net
```

**Step 6: Commit Separately**
```bash
# Commit tests first
git add tests/unit/test_new_feature.sh
git commit -m "test: add tests for [feature]"

# Then commit implementation
git add lib/new_feature.sh
git commit -m "feat: implement [feature]"

# Ask Claude to generate commit messages based on git diff
```

### Independent Verification (Critical Features)

For security-critical or complex features:

1. **Initial Implementation**: Claude instance A writes tests and code
2. **Independent Review**: Ask a NEW Claude instance (use /clear) to:
   - Review tests for completeness
   - Verify implementation doesn't overfit to tests
   - Suggest additional edge cases

## Git Workflow Best Practices

### Commit Frequency

**Commit often during iteration:**
- ✅ After tests pass (GREEN phase)
- ✅ After successful refactoring
- ✅ After fixing each distinct issue
- ✅ Before attempting risky changes

**Separate commits for:**
1. Tests (first)
2. Implementation (second)
3. Documentation (third, if substantial)

### Commit Message Generation

**Let Claude write commit messages:**
```bash
# After staging changes
git add [files]

# Ask Claude:
"Examine git diff --staged and recent git log.
Write a conventional commit message following our project style."

# Claude will analyze:
# - What changed (git diff --staged)
# - Project conventions (git log --oneline -10)
# - Generate appropriate message
```

### Complex Git Operations

**Use Claude for:**
- Reverting files: "Revert lib/config.sh to previous commit"
- Resolving rebase conflicts: "Help resolve conflicts in [file]"
- Cherry-picking patches: "Apply the certificate validation logic from commit abc123"
- Searching history: "When was SNI validation added?"

### Pre-Commit Validation

**ALWAYS before committing:**
```bash
# 1. Tests pass
bash tests/test_reality.sh

# 2. Syntax valid
bash -n lib/modified_file.sh

# 3. ShellCheck passes
shellcheck lib/modified_file.sh

# 4. No debug code left
grep -n "echo.*DEBUG" lib/modified_file.sh
```

## Testing Requirements

### Test-First Development (Mandatory)

**For ALL new features:**
1. ✅ Write tests BEFORE implementation
2. ✅ Verify tests fail initially (RED)
3. ✅ Implement code to pass tests (GREEN)
4. ✅ Refactor while keeping tests passing
5. ✅ Commit tests separately from implementation

### Before Every Config Change

```bash
sing-box check -c /etc/sing-box/config.json
systemctl restart sing-box && sleep 3 && systemctl status sing-box
journalctl -u sing-box -f  # Watch 10-15 seconds
```

### Before Committing Code

```bash
# 1. All unit tests pass
bash tests/test_reality.sh

# 2. ShellCheck validation
make check

# 3. Integration tests pass
bash tests/integration/test_reality_connection.sh

# 4. Actual installation works
bash install_multi.sh
```

### Independent Verification (Critical Features)

For security-critical features (validation, encryption, authentication):

1. **Initial implementation** - Claude instance A
2. **Clear context:** `/clear`
3. **Independent review** - Fresh Claude instance
4. **Verification focus:**
   - Are tests comprehensive?
   - Are there edge cases missed?
   - Is implementation overfitting to tests?

## Working Effectively with Claude

### Thinking Modes for Complex Problems

Use thinking modes for planning complex features:

```bash
# Simple task - normal mode
"Add validation for port numbers"

# Medium complexity - use thinking
"think: Design a backup encryption system with key rotation"

# High complexity - deeper thinking
"think hard: Refactor config generation to support multi-protocol setups"

# Critical architecture decisions - maximum depth
"think harder: Design a plugin system for custom protocol handlers"
```

### Early Course Correction

**Interrupt immediately if Claude is going wrong direction:**
- Press **Escape key** to stop execution
- Provide correction: "Actually, we should use [approach] instead"
- This saves tokens and time vs. letting Claude finish wrong implementation

### Context Management

**Use /clear between unrelated tasks:**
```bash
# After completing feature A
/clear

# Start fresh context for feature B
"Implement feature B..."
```

**Benefits:**
- Maintains focus on current task
- Prevents confusion from previous context
- Improves performance and accuracy

### Subagent Usage (Task Tool)

**Use subagents early for:**
- Codebase exploration ("Where are errors from client handled?")
- Multi-file refactoring
- Complex searches requiring multiple iterations
- Tasks that might require 5+ tool calls

```bash
# Instead of running Grep/Glob directly for exploration:
# Use Task tool with subagent_type=Explore

# Example prompt:
"Use the Explore agent to find all certificate validation logic"
```

### Specificity Matters

**Good prompts (specific):**
```bash
"Add a validate_certificate() function to lib/validation.sh that:
- Checks file exists and is readable
- Verifies PEM format with openssl
- Warns if expiring within 30 days
- Returns 0 on success, 1 on failure
- Uses format_error() for error messages"
```

**Poor prompts (vague):**
```bash
"Add certificate validation"  # Too vague!
```

## Version Information

- **Current:** v2.2.0 (Phase 4 complete)
- **Architecture:** Modular v2.0 (11 library modules)
- **sing-box:** 1.8.0+ (recommended 1.12.0+)
- **License:** MIT
