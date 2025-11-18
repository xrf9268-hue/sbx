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

### Adding a New Feature
1. Read: @docs/REALITY_BEST_PRACTICES.md + official sing-box docs
2. Write: Follow bash standards from @.claude/CODING_STANDARDS.md
3. Test: `bash tests/test_reality.sh`
4. Integrate: `bash tests/integration/test_reality_connection.sh`
5. Document: Update relevant docs
6. Commit: Conventional commits (feat:, fix:, docs:)

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

## Testing Requirements

**Before every config change:**
```bash
sing-box check -c /etc/sing-box/config.json
systemctl restart sing-box && sleep 3 && systemctl status sing-box
journalctl -u sing-box -f  # Watch 10-15 seconds
```

**Before committing code:**
```bash
bash tests/test_reality.sh  # All unit tests
make check                  # ShellCheck if available
bash install_multi.sh       # Test actual installation
```

## Version Information

- **Current:** v2.2.0 (Phase 4 complete)
- **Architecture:** Modular v2.0 (11 library modules)
- **sing-box:** 1.8.0+ (recommended 1.12.0+)
- **License:** MIT
