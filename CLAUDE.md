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
- **Compliance Review**: @docs/REALITY_COMPLIANCE_REVIEW.md - Full audit vs sing-box official standards
- **Improvement Plan**: @docs/MULTI_PHASE_IMPROVEMENT_PLAN.md - Development roadmap
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
1. **Read documentation**: Check @docs/REALITY_COMPLIANCE_REVIEW.md for compliance requirements
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
