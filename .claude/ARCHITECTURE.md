# Code Architecture

Technical architecture and module organization for sbx-lite.

## Modular Structure (v2.2.0)

**Main:** `install_multi.sh` (~583 lines) - Orchestrates installation
**Library:** `lib/` directory (11 modules, 3,523 lines total)

## Key Modules

- `lib/common.sh` - Logging, utilities, constants
- `lib/network.sh` - IP detection, port allocation
- `lib/validation.sh` - Input sanitization, security
- `lib/config.sh` - sing-box JSON generation
- `lib/service.sh` - systemd management
- `lib/backup.sh` - Backup/restore operations
- `lib/export.sh` - Client config export

## Security-Critical Functions

- `sanitize_input()` - Remove shell metacharacters (lib/validation.sh)
- `validate_short_id()` - Enforce 8-char limit (lib/validation.sh)
- `verify_singbox_binary()` - SHA256 verification (lib/checksum.sh)
- `write_config()` - Atomic config writes (lib/config.sh)
- `cleanup()` - Secure temp file cleanup (lib/common.sh)
