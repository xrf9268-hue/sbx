# Code Architecture

Technical architecture and module organization for sbx-lite.

## Modular Structure

**Main:** `install.sh` (~1,581 lines) - Orchestrates installation
**Library:** `lib/` directory (21 modules, ~7,969 lines total)

## Module List

| Module | Lines | Description |
|--------|-------|-------------|
| `lib/backup.sh` | 594 | Backup/restore operations |
| `lib/caddy_cleanup.sh` | 68 | Legacy Caddy uninstall (migration tool) |
| `lib/certificate.sh` | 126 | CERT_MODE resolution, ACME parameter validation |
| `lib/checksum.sh` | 189 | Binary SHA256 verification |
| `lib/colors.sh` | 66 | Terminal color definitions |
| `lib/common.sh` | 537 | Utilities, constants, temp file helpers |
| `lib/config.sh` | 668 | sing-box JSON config generation (ACME, Reality, WS, Hy2) |
| `lib/config_validator.sh` | 456 | Configuration validation rules |
| `lib/download.sh` | 396 | Binary download with retry logic |
| `lib/export.sh` | 411 | Client config export (URI, Clash, QR) |
| `lib/generators.sh` | 243 | UUID, keypair, short ID generation |
| `lib/logging.sh` | 284 | Structured logging framework |
| `lib/messages.sh` | 329 | User-facing message templates |
| `lib/network.sh` | 462 | IP detection, port allocation |
| `lib/retry.sh` | 359 | Retry logic with exponential backoff |
| `lib/schema_validator.sh` | 360 | JSON schema validation |
| `lib/service.sh` | 328 | systemd service management |
| `lib/tools.sh` | 432 | External tool detection and setup |
| `lib/ui.sh` | 326 | Interactive UI helpers |
| `lib/validation.sh` | 872 | Input sanitization, security validation |
| `lib/version.sh` | 463 | Version detection, comparison, upgrades |

## Security-Critical Functions

- `sanitize_input()` - Remove shell metacharacters (lib/validation.sh)
- `validate_short_id()` - Enforce 8-char limit (lib/validation.sh)
- `validate_cf_api_token()` - CF API token validation (lib/validation.sh)
- `verify_singbox_binary()` - SHA256 verification (lib/checksum.sh)
- `_build_tls_block()` - ACME/TLS config generation (lib/config.sh)
- `write_config()` - Atomic config writes (lib/config.sh)
- `cleanup()` - Secure temp file cleanup (lib/common.sh)
