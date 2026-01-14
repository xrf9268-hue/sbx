# CLAUDE.md

sing-box proxy deployment script with VLESS-REALITY protocol support.

## Project Context

- **What**: Bash installer for sing-box with Reality protocol, modular architecture (18 lib modules, ~4,100 lines)
- **Why**: Zero-config proxy deployment - auto-detects IP, no domain/certs required for Reality-only mode
- **How**: `bash install.sh` for Reality-only, `DOMAIN=x.com bash install.sh` for multi-protocol

## Quick Reference

```bash
# Test & validate
bash tests/test-runner.sh unit        # Run unit tests
sing-box check -c /etc/sing-box/config.json  # Validate config

# Install
bash install.sh                       # Reality-only
DOMAIN=x.com bash install.sh          # Full setup

# Manage
sbx info | status | check | restart   # Post-install management
```

## Key Rules

**Bash strict mode** (`set -euo pipefail`):
- Initialize all local variables at declaration: `local var=""`
- Use safe expansion: `${VAR:-default}`
- Quote all variables: `"$VAR"`

**Variable declarations in modules** (CRITICAL):
- Use `declare -gr` NOT `declare -r` in lib/*.sh modules
- Reason: `declare -r` creates local vars when sourced inside a function
- See `.claude/CODING_STANDARDS.md` § "Variable Scope in Sourced Scripts"

**Reality protocol** (sing-box 1.12.0+):
- Short ID: 8 chars max via `openssl rand -hex 4`
- Must nest under `tls.reality`, not top-level
- Flow field in `users[]` array, not inbound level

**Validation after changes**:
- Always run `sing-box check` before restart
- Test with `bash -u script.sh` for unbound variables

**Bootstrap constants** (defined before module loading):
- Add early constants to `install.sh` (after `set -euo pipefail`, before module loading)
- See `tests/unit/README_BOOTSTRAP_TESTS.md` for patterns

## File Locations

| Type | Path |
|------|------|
| Config | `/etc/sing-box/config.json` |
| Binary | `/usr/local/bin/sing-box` |
| Manager | `/usr/local/bin/sbx` |
| Libraries | `/usr/local/lib/sbx/*.sh` |
| Backups | `/var/backups/sbx/` |

## Documentation

**Core guides** (use `@` to import):
- @.claude/REALITY_CONFIG.md - Reality protocol details
- @.claude/ARCHITECTURE.md - Code structure
- @.claude/CODING_STANDARDS.md - Bash patterns
- @.claude/WORKFLOWS.md - TDD and git workflows

**Reference**:
- @README.md - User guide
- @CONTRIBUTING.md - Contributor setup
- @docs/REALITY_TROUBLESHOOTING.md - Common issues

## Automated Quality

Hooks run automatically - no manual checks needed:
- **SessionStart**: Installs git hooks, verifies deps, validates constants
- **PostToolUse**: Formats with shfmt, lints with shellcheck
- **Pre-commit**: Syntax check, strict mode, unbound variable detection

Setup: `bash hooks/install-hooks.sh`

## Environment Variables

```bash
DOMAIN=x.com          # Enable multi-protocol (WS-TLS + Hysteria2)
SINGBOX_VERSION=v1.12.0  # Specific version
DEBUG=1               # Debug output
```
