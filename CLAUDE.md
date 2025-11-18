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

**Error Signatures:**
```
# get_file_size error
get_file_size: command not found

# HTTP_DOWNLOAD_TIMEOUT_SEC error
HTTP_DOWNLOAD_TIMEOUT_SEC: unbound variable
[ERR] Failed to fetch release information from GitHub API
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
