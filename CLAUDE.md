# CLAUDE.md

Project guidance for Claude Code when working with sbx-lite, a sing-box proxy deployment script with VLESS-REALITY protocol support.

## Quick Commands

### Essential Development Commands
```bash
# Testing & Validation (Run after ANY config change)
sing-box check -c /etc/sing-box/config.json  # MUST pass before restart
systemctl restart sing-box && sleep 3 && systemctl status sing-box
journalctl -u sing-box -f  # Monitor for 10-15 seconds

# Test installation
bash install_multi.sh  # Reality-only (auto-detect IP)
DOMAIN=test.domain.com bash install_multi.sh  # Full setup with domain

# Unit tests
bash tests/test_reality.sh

# Integration tests (requires installation)
bash tests/integration/test_reality_connection.sh

# Management commands (post-installation)
sbx info     # View URIs and config
sbx status   # Check service
sbx check    # Validate config
sbx restart  # Restart service
```

## Critical Implementation Rules

### Reality Protocol Configuration (sing-box 1.12.0+)
- **Short ID generation**: `openssl rand -hex 4` (8 chars, NOT 16 like Xray)
- **Short ID validation**: `[[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]]` - MUST validate immediately after generation
- **Configuration structure**: Reality MUST be nested under `tls.reality` (NOT top-level)
- **Flow field**: `"flow": "xtls-rprx-vision"` in users array (NOT at inbound level)
- **Short ID type**: Array format `["a1b2c3d4"]` (NOT string)
- **Transport pairing**: Vision flow requires TCP transport with Reality security
- **Keypair generation**: Use `sing-box generate reality-keypair` (NOT openssl)

### Mandatory Post-Configuration Validation
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
- **NEVER use deprecated fields**: `sniff`, `sniff_override_destination`, `domain_strategy` in inbounds
- **NEVER use** `domain_strategy` in outbounds (causes IPv6 connection failures)
- **ALWAYS use** `dns.strategy: "ipv4_only"` for IPv4-only networks (global, not per-outbound)
- **ALWAYS use** `listen: "::"` for dual-stack (NEVER "0.0.0.0")
- **ALWAYS include** route configuration with `action: "sniff"` and `action: "hijack-dns"`

### Reality Configuration Best Practices

#### Configuration Structure Rules
- Reality **MUST** be nested under `tls.reality` (NOT at top-level in inbound)
- Flow field **MUST** be `"xtls-rprx-vision"` in users array for Vision protocol
- Short ID **MUST** be array format: `["a1b2c3d4"]` not string `"a1b2c3d4"`
- Transport **MUST** be TCP (implicit or explicit) for Vision flow compatibility

#### Official sing-box Reference Locations
- **VLESS Inbound**: `docs/sing-box-official/docs/configuration/inbound/vless.md`
- **Reality/TLS Fields**: `docs/sing-box-official/docs/configuration/shared/tls.md#reality-fields`
- **Migration Guide**: `docs/sing-box-official/docs/migration.md`
- **Online Docs**: https://sing-box.sagernet.org/

#### Reality Configuration Validation Checklist
When creating or modifying Reality configurations, follow this workflow:

```bash
# 1. Generate materials with proper tools
UUID=$(generate_uuid)
KEYPAIR=$(generate_reality_keypair)
read -r PRIV PUB <<< "$KEYPAIR"
SID=$(openssl rand -hex 4)  # Exactly 4, not 8!

# 2. Validate materials immediately
validate_short_id "$SID" || die "Invalid short ID: $SID"
validate_reality_keypair "$PRIV" "$PUB" || die "Invalid keypair"

# 3. Build configuration with validated materials
CONFIG=$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")

# 4. Verify configuration structure
echo "$CONFIG" | jq -e '.tls.reality' || die "Reality not nested under tls"
echo "$CONFIG" | jq -e '.users[0].flow == "xtls-rprx-vision"' || die "Wrong flow"
echo "$CONFIG" | jq -e '.tls.reality.short_id | type == "array"' || die "Short ID not array"

# 5. Write and validate with sing-box
echo "$CONFIG" > /tmp/config.json
sing-box check -c /tmp/config.json || die "Config validation failed"

# 6. Apply and verify service
systemctl restart sing-box && sleep 3
systemctl is-active sing-box || die "Service failed to start"

# 7. Monitor logs for errors
journalctl -u sing-box -f  # Watch for 10-15 seconds
```

#### Common Reality Configuration Mistakes

**WRONG:**
```json
{
  "inbounds": [{
    "type": "vless",
    "flow": "xtls-rprx-vision",        // ✗ Flow at inbound level
    "reality": {                        // ✗ Reality at top-level
      "short_id": "a1b2c3d4abcdef01"  // ✗ String format, 16 chars (Xray)
    }
  }]
}
```

**CORRECT:**
```json
{
  "inbounds": [{
    "type": "vless",
    "users": [
      {"uuid": "...", "flow": "xtls-rprx-vision"}  // ✓ Flow in users array
    ],
    "tls": {                           // ✓ Reality nested under tls
      "enabled": true,
      "reality": {
        "enabled": true,
        "short_id": ["a1b2c3d4"]      // ✓ Array format, 8 chars
      }
    }
  }]
}
```

#### sing-box vs Xray Reality Differences

| Aspect | sing-box | Xray |
|--------|----------|------|
| **Short ID Length** | 1-8 hex chars | 1-16 hex chars |
| **Generation** | `openssl rand -hex 4` | `openssl rand -hex 8` |
| **Config Path** | `tls.reality` | `streamSettings.realitySettings` |
| **Client Core** | Must use sing-box core | Must use Xray core |

**Migration Note:** When migrating from Xray, truncate short IDs to 8 chars or regenerate. See [SING_BOX_VS_XRAY.md](docs/SING_BOX_VS_XRAY.md) for full migration guide.

## Code Architecture

### Modular Structure (v2.0)
**Main script**: `install_multi.sh` (~583 lines) - Orchestrates installation flow
**Library modules** in `lib/` directory (11 modules, 3,523 lines total):

1. **common.sh** (308 lines) - Logging, utilities, constants
2. **network.sh** (242 lines) - IP detection, port allocation
3. **validation.sh** (331 lines) - Input sanitization, security
4. **checksum.sh** (200 lines) - SHA256 binary verification
5. **certificate.sh** (102 lines) - Certificate management
6. **caddy.sh** (429 lines) - Automatic TLS via Caddy
7. **config.sh** (330 lines) - sing-box JSON generation
8. **service.sh** (230 lines) - systemd management
9. **ui.sh** (310 lines) - User interface
10. **backup.sh** (291 lines) - Backup/restore operations
11. **export.sh** (345 lines) - Client config export

### Key Functions (Security-Critical)
- `sanitize_input()` - Removes shell metacharacters from user input (lib/validation.sh)
- `validate_short_id()` - Enforces 8-char limit for sing-box (lib/validation.sh)
- `verify_singbox_binary()` - SHA256 checksum verification (lib/checksum.sh)
- `write_config()` - Atomic config writes with validation (lib/config.sh)
- `cleanup()` - Secure temp file cleanup with trap integration (lib/common.sh)

## Bash Coding Standards

### Mandatory Security Practices
```bash
# Always use strict mode
set -euo pipefail

# Quote all variables
"$VARIABLE"  # NOT $VARIABLE

# Safe expansion for constants/readonly vars
${LOG_LEVEL:-warn}  # NOT $LOG_LEVEL (prevents unbound errors in strict mode)

# Use existing logging functions
msg "info message"
warn "warning message"
err "error message"
die "fatal error"  # Exits with code 1

# Input validation
sanitize_input "$user_input"
validate_domain "$domain" || die "Invalid domain"

# Secure temp files (use helpers from lib/common.sh)
tmpfile=$(create_temp_file "prefix") || return 1  # Automatic 600 permissions
tmpdir=$(create_temp_dir "prefix") || return 1     # Automatic 700 permissions
trap 'rm -rf "$tmpfile" "$tmpdir"' EXIT

# Legacy manual method (avoid - use helpers above instead)
# tmpfile=$(mktemp) || die "Failed to create temp file"
# chmod 600 "$tmpfile"
# trap 'rm -f "$tmpfile"' EXIT

# JSON generation via jq (NEVER string concatenation)
jq -n --arg uuid "$UUID" '{users: [{uuid: $uuid}]}'
```

### Error Handling Patterns

**Standard patterns for consistent error handling:**

```bash
# Pattern A: Fatal errors (use die for immediate exit)
# Best for: Unrecoverable errors, prerequisite failures
command || die "Error message"
validate_config || die "Configuration invalid"

# Pattern B: Recoverable errors with detailed context
# Best for: Multi-line error explanations, complex validation
if ! function_call; then
  err "Primary error message"
  err "Additional context line 1"
  err "Additional context line 2"
  return 1
fi

# Pattern C: Recoverable errors with cleanup
# Best for: Errors requiring resource cleanup, single-line messages
function_call || {
  err "Error message"
  cleanup_resources
  return 1
}
```

**Pattern Selection Guidelines:**
- **Use Pattern A** when errors are fatal and script should exit immediately
- **Use Pattern B** when errors are recoverable and need detailed explanation
- **Use Pattern C** when errors need resource cleanup before returning
- **NEVER mix** patterns within the same function for consistency

**Examples in Codebase:**
```bash
# Pattern A (lib/service.sh): Fatal service errors
systemctl start sing-box || die "Failed to start sing-box service"

# Pattern B (lib/validation.sh): Detailed validation errors
if [[ $priv_len -lt "$X25519_KEY_MIN_LENGTH" ]]; then
  err "Private key has invalid length: $priv_len"
  err "Expected: ${X25519_KEY_MIN_LENGTH}-${X25519_KEY_MAX_LENGTH} characters"
  err "Generate valid keypair: sing-box generate reality-keypair"
  return 1
fi

# Pattern C (lib/config.sh): Errors with cleanup
write_config || {
  err "Failed to write configuration"
  rm -f "$temp_conf"
  return 1
}
```

### Common Bash Pitfalls (CI/CD)
```bash
# WRONG - Fails in bash -e when count=0
count=0
((count++))  # Returns 0 (old value), triggers exit in bash -e

# CORRECT - Always safe
count=$((count + 1))  # Returns 1 (new value)

# ShellCheck directives (avoid recursive analysis)
# shellcheck source=/dev/null  # NOT source=lib/file.sh
source "${_LIB_DIR}/common.sh"
```

### GitHub Actions Best Practices (CI/CD)

**CRITICAL: Don't Pin System Package Versions**
```bash
# ❌ WRONG - Ubuntu package versions use complex Debian formats
env:
  SHELLCHECK_VERSION: "0.10.0"  # Doesn't match Ubuntu's "0.9.0-1"
  JQ_VERSION: "1.6"              # Doesn't match Ubuntu's "1.7.1-3ubuntu0.24.04.1"

steps:
  - run: sudo apt-get install -y shellcheck=${SHELLCHECK_VERSION}*  # FAILS!

# ✅ CORRECT - Let GitHub Actions runner OS provide version pinning
steps:
  - run: sudo apt-get install -y shellcheck jq  # Works reliably
```

**Why This Works:**
- GitHub Actions runners use specific Ubuntu versions (e.g., `ubuntu-24.04`)
- Each runner OS has **snapshot/frozen package repositories** with locked versions
- Package versions are **implicitly pinned by the runner OS version**
- Ubuntu package versions use complex Debian formats incompatible with simple version strings
- Reference: [xray project](https://github.com/xrf9268-hue/xray/.github/workflows/test.yml)

**What TO Pin (Security-Critical):**
```yaml
# ✅ Pin GitHub Actions to commit SHAs (prevents supply chain attacks)
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
- uses: actions/cache@1bd1e32a3bdc45362d1e726936510720a7c30a57 # v4.2.0

# ✅ Use Dependabot to automate SHA updates
# .github/dependabot.yml handles this automatically
```

**Cache Key Best Practices:**
```yaml
# ✅ Include content hashes and version prefixes
cache:
  key: ${{ runner.os }}-shellcheck-v1-${{ hashFiles('lib/**/*.sh', 'bin/**/*.sh') }}
  restore-keys: |
    ${{ runner.os }}-shellcheck-v1-
    ${{ runner.os }}-shellcheck-

# ❌ AVOID workflow file hash only (rarely changes, risks cache poisoning)
# key: ${{ hashFiles('.github/workflows/shellcheck.yml') }}
```

**Lesson Learned (2025-01-18):**
Initial CI/CD modernization attempted system package version pinning following general best practices, but failed because:
1. Ubuntu package versions (e.g., `1.7.1-3ubuntu0.24.04.1`) don't match simple version strings (e.g., `1.6`)
2. GitHub Actions runners already provide implicit version pinning via OS-level package snapshots
3. The xray reference project demonstrated the correct approach: no apt version pinning, SHA-pinned GitHub Actions only

### Code Quality Requirements
- Use `[[ ]]` for conditionals (NOT `[ ]`)
- Local variables in functions: `local var_name="$1"`
- Check command success: `command || die "Error message"`
- **NO Chinese characters** in output (use English only for compatibility)
- Network operations: Always use timeout protection
- Error handling: Check jq operations with `|| die "message"`

### Common Validation Patterns

**Parameter Validation (lib/validation.sh):**
```bash
# Validate single required parameter
require "DOMAIN" "$DOMAIN" "Domain" || return 1

# Validate multiple required parameters
require_all UUID PRIV SID DOMAIN || return 1

# Validate parameter with custom validation function
require_valid "PORT" "$PORT" "Port number" validate_port || return 1
```

**File Integrity Validation (lib/validation.sh):**
```bash
# Validate certificate/key file integrity
validate_file_integrity "$cert_path" "$key_path" || return 1

# Manual checks (if helper not applicable)
[[ -f "$file" ]] || die "File not found: $file"
[[ -r "$file" ]] || die "File not readable: $file"
```

**Temp File Creation (lib/common.sh):**
```bash
# Create secure temp file (600 permissions automatic)
tmpfile=$(create_temp_file "backup") || return 1

# Create secure temp directory (700 permissions automatic)
tmpdir=$(create_temp_dir "restore") || return 1

# Both helpers provide detailed error diagnostics on failure
```

## Constants Reference

### Global Configuration Constants

All constants are defined in `lib/common.sh` and available globally after module loading.

#### Certificate Management
| Constant | Value | Purpose |
|----------|-------|---------|
| `CERT_EXPIRY_WARNING_DAYS` | 30 | Days before expiry to show warning |
| `CERT_EXPIRY_WARNING_SEC` | 2592000 | Seconds (30 days) for openssl -checkend |

**Usage:**
```bash
# lib/validation.sh:149
if ! openssl x509 -in "$fullchain" -checkend "$CERT_EXPIRY_WARNING_SEC" -noout; then
  warn "Certificate will expire within ${CERT_EXPIRY_WARNING_DAYS} days"
fi
```

#### Cryptographic Validation
| Constant | Value | Purpose |
|----------|-------|---------|
| `X25519_KEY_MIN_LENGTH` | 42 | Minimum X25519 key length (base64url) |
| `X25519_KEY_MAX_LENGTH` | 44 | Maximum X25519 key length (base64url) |
| `X25519_KEY_BYTES` | 32 | X25519 key size in bytes |

**Usage:**
```bash
# lib/validation.sh:408
if [[ $priv_len -lt "$X25519_KEY_MIN_LENGTH" || $priv_len -gt "$X25519_KEY_MAX_LENGTH" ]]; then
  err "Expected: ${X25519_KEY_MIN_LENGTH}-${X25519_KEY_MAX_LENGTH} characters"
fi
```

#### Backup & Encryption
| Constant | Value | Purpose |
|----------|-------|---------|
| `BACKUP_PASSWORD_RANDOM_BYTES` | 48 | Random bytes for password generation |
| `BACKUP_PASSWORD_LENGTH` | 64 | Final password length (chars) |
| `BACKUP_PASSWORD_MIN_LENGTH` | 32 | Minimum acceptable password length |

**Usage:**
```bash
# lib/backup.sh:112
password=$(openssl rand -base64 "$BACKUP_PASSWORD_RANDOM_BYTES" | head -c "$BACKUP_PASSWORD_LENGTH")
```

#### Caddy Configuration
| Constant | Value | Purpose |
|----------|-------|---------|
| `CADDY_HTTP_PORT_DEFAULT` | 80 | Default HTTP port |
| `CADDY_HTTPS_PORT_DEFAULT` | 8445 | Default HTTPS port (cert management) |
| `CADDY_FALLBACK_PORT_DEFAULT` | 8080 | Fallback HTTP port |
| `CADDY_STARTUP_WAIT_SEC` | 2 | Wait time after starting Caddy |
| `CADDY_CERT_POLL_INTERVAL_SEC` | 3 | Poll interval for cert availability |

**Usage:**
```bash
# lib/caddy.sh:234
local caddy_https_port="${CADDY_HTTPS_PORT:-$CADDY_HTTPS_PORT_DEFAULT}"
```

#### Network & Timeouts
| Constant | Value | Purpose |
|----------|-------|---------|
| `NETWORK_TIMEOUT_SEC` | 5 | General network operation timeout |
| `HTTP_DOWNLOAD_TIMEOUT_SEC` | 30 | Large file download timeout |

**Usage:**
```bash
# lib/network.sh:50
ip=$(timeout "$NETWORK_TIMEOUT_SEC" curl -s --max-time "$NETWORK_TIMEOUT_SEC" "$service")
```

#### Logging & Monitoring
| Constant | Value | Purpose |
|----------|-------|---------|
| `LOG_VIEW_MAX_LINES` | 10000 | Maximum log lines to display |
| `LOG_VIEW_DEFAULT_HISTORY` | "5 minutes ago" | Default log history window |
| `LOG_ROTATION_CHECK_INTERVAL` | 100 | Check rotation every N writes |

**Usage:**
```bash
# lib/service.sh:299
if [[ "$lines" -gt "$LOG_VIEW_MAX_LINES" ]]; then
  err "Invalid line count (must be 1-${LOG_VIEW_MAX_LINES})"
fi
```

#### File Validation
| Constant | Value | Purpose |
|----------|-------|---------|
| `MIN_MODULE_FILE_SIZE_BYTES` | 100 | Minimum module file size |
| `MIN_MANAGER_FILE_SIZE_BYTES` | 5000 | Minimum manager script size (~15KB expected) |

**Usage:**
```bash
# install_multi.sh:398
if [[ "${mgr_size}" -lt "$MIN_MANAGER_FILE_SIZE_BYTES" ]]; then
  echo "ERROR: Downloaded sbx-manager.sh is too small"
fi
```

### Helper Functions Reference

#### File Operations
```bash
# Get file size (cross-platform: Linux/BSD/macOS)
size=$(get_file_size "/path/to/file")
# Returns: Size in bytes, or "0" if error

# Get file modification time (cross-platform)
mtime=$(get_file_mtime "/path/to/file")
# Returns: "YYYY-MM-DD HH:MM:SS" or empty string if error
# Example: "2025-11-18 10:30:45"
```

#### Secure Temporary Files
```bash
# Create temporary file with secure permissions (600)
tmpfile=$(create_temp_file "prefix") || return 1
# Automatic permissions, detailed error diagnostics

# Create temporary directory with secure permissions (700)
tmpdir=$(create_temp_dir "prefix") || return 1
# Automatic permissions, automatic cleanup on failure
```

#### JSON Operations
```bash
# Parse JSON with fallback (jq → python3 → python)
value=$(json_parse "$json_string" ".field.path")

# Build JSON with fallback
json=$(json_build "$key" "$value")
```

#### Cryptographic Operations
```bash
# Generate random hex string with fallback (openssl → /dev/urandom)
hex=$(crypto_random_hex 8)  # 8 bytes = 16 hex chars

# Calculate SHA256 with fallback (openssl → shasum)
hash=$(crypto_sha256 "$file_path")
```

### Best Practices for Constants

**When to create a new constant:**
- ✅ Magic number appears 2+ times
- ✅ Value has semantic meaning (timeout, limit, size)
- ✅ Value might need tuning/configuration
- ✅ Value is security-critical (password length, key size)

**Where to define constants:**
- **lib/common.sh** - Global constants used across modules
- **install_multi.sh (early)** - Boot-time constants needed before module loading
- **Module-specific** - Only if constant is truly module-internal

**Naming conventions:**
- Use `SCREAMING_SNAKE_CASE`
- Include units in name: `_SEC`, `_BYTES`, `_LENGTH`, `_DAYS`
- Group related constants: `BACKUP_PASSWORD_*`, `CADDY_*_PORT_DEFAULT`
- Make readonly: `declare -r CONSTANT_NAME=value`

**Example:**
```bash
# ❌ BAD: Magic number
sleep 5
password=$(openssl rand -base64 48 | head -c 64)

# ✅ GOOD: Named constant with clear intent
declare -r SERVICE_STARTUP_WAIT_SEC=5
declare -r BACKUP_PASSWORD_RANDOM_BYTES=48
declare -r BACKUP_PASSWORD_LENGTH=64

sleep "$SERVICE_STARTUP_WAIT_SEC"
password=$(openssl rand -base64 "$BACKUP_PASSWORD_RANDOM_BYTES" | head -c "$BACKUP_PASSWORD_LENGTH")
```

## File Locations

### Runtime Files
- Binary: `/usr/local/bin/sing-box`
- Config: `/etc/sing-box/config.json`
- Client info: `/etc/sing-box/client-info.txt`
- Service: `/etc/systemd/system/sing-box.service`
- Certificates: `/etc/ssl/sbx/<domain>/fullchain.pem` and `privkey.pem`

### Management Tools
- Manager script: `/usr/local/bin/sbx-manager`
- Symlink: `/usr/local/bin/sbx`
- Library modules: `/usr/local/lib/sbx/*.sh`

### Backup & Data
- Backup directory: `/var/backups/sbx/`
- Backup files: `sbx-backup-YYYYMMDD-HHMMSS.tar.gz[.enc]`
- Backup retention: 30 days

## Environment Variables

### Installation Variables (All Optional)
```bash
# Domain/IP (auto-detects if omitted)
DOMAIN=your.domain.com    # Enables full setup (WS-TLS + Hysteria2)
DOMAIN=1.2.3.4            # Reality-only with explicit IP

# Version selection
SINGBOX_VERSION=stable    # Latest stable (default)
SINGBOX_VERSION=latest    # Including pre-releases
SINGBOX_VERSION=v1.10.7   # Specific version

# Certificate mode
CERT_MODE=caddy           # Auto TLS (default with domain)
CERT_FULLCHAIN=/path/fullchain.pem
CERT_KEY=/path/privkey.pem

# Port overrides
REALITY_PORT=443          # Default 443, fallback 24443
WS_PORT=8444              # Default 8444, fallback 24444
HY2_PORT=8443             # Default 8443, fallback 24445

# Security
SKIP_CHECKSUM=1           # NOT recommended

# Debugging
DEBUG=1                   # Enable debug output
LOG_TIMESTAMPS=1          # Add timestamps
LOG_FORMAT=json           # JSON output
LOG_FILE=/path/file.log   # Log to file
LOG_LEVEL_FILTER=ERROR    # Filter by severity (ERROR/WARN/INFO/DEBUG)
```

## Documentation References

### User Documentation
- **Installation & Usage**: @README.md - Quick start, commands, client setup
- **Troubleshooting**: @docs/REALITY_TROUBLESHOOTING.md - Common issues and solutions
- **Changelog**: @CHANGELOG.md - Version history and migration notes

### Developer Documentation
- **Best Practices**: @docs/REALITY_BEST_PRACTICES.md - Production-grade deployment patterns
- **sing-box vs Xray**: @docs/SING_BOX_VS_XRAY.md - Migration guide for Xray users

### Official sing-box Documentation (Git Submodule)
```bash
# Initialize submodule (first time)
git submodule update --init --recursive

# Update to latest
git submodule update --remote docs/sing-box-official

# Key paths
docs/sing-box-official/docs/configuration/inbound/vless.md
docs/sing-box-official/docs/configuration/shared/tls.md
docs/sing-box-official/docs/migration.md
```

**Online access**:
- VLESS: https://sing-box.sagernet.org/configuration/inbound/vless/
- Reality/TLS: https://sing-box.sagernet.org/configuration/shared/tls/
- Migration: https://sing-box.sagernet.org/migration/

## Common Workflows

### Adding a New Feature
1. **Read documentation**: Check @docs/REALITY_BEST_PRACTICES.md and official sing-box docs for compliance requirements
2. **Write code**: Follow bash coding standards above
3. **Add tests**: Create unit tests in `tests/` directory
4. **Validate**: Run `bash tests/test_reality.sh`
5. **Test integration**: Run `bash tests/integration/test_reality_connection.sh`
6. **Update docs**: Update relevant documentation files
7. **Commit**: Follow conventional commits (feat:, fix:, docs:, etc.)

### Modifying Reality Configuration
1. **ALWAYS** read current config structure
2. **Generate materials** with proper validation
3. **Create config** using `jq` (never string manipulation)
4. **Validate immediately**: `sing-box check -c /etc/sing-box/config.json`
5. **Verify structure**: Check Reality nesting, short_id type, flow field
6. **Restart service**: `systemctl restart sing-box`
7. **Monitor logs**: `journalctl -u sing-box -f` for 10-15 seconds

### Debugging Installation Issues
```bash
# Enable full debug logging
DEBUG=1 LOG_TIMESTAMPS=1 LOG_FILE=/tmp/debug.log bash install_multi.sh

# Check log for errors
grep -i error /tmp/debug.log

# Test in bash -e mode (like CI)
bash -e install_multi.sh
```

## Testing Requirements

### Before Every Config Change
```bash
# 1. Validate config syntax
sing-box check -c /etc/sing-box/config.json

# 2. Verify content
cat /etc/sing-box/config.json | head -30

# 3. Restart and check
systemctl restart sing-box && sleep 3 && systemctl status sing-box

# 4. Monitor logs
journalctl -u sing-box -f  # Watch for 10-15 seconds
```

### Before Committing Code
```bash
# Run all tests
bash tests/test_reality.sh

# Validate with ShellCheck (if installed)
make check

# Test actual installation (if possible)
bash install_multi.sh
```

## Version Information

- **Current**: v2.2.0 (Phase 4 complete)
- **Architecture**: Modular v2.0 (11 library modules)
- **sing-box compatibility**: 1.8.0+ (recommended 1.12.0+)
- **License**: MIT
