# sbx vs xray Comparison Analysis

Cross-project comparison between [sbx](https://github.com/xrf9268-hue/sbx) (sing-box) and [xray](https://github.com/xrf9268-hue/xray) (Xray-core).

## Architecture Overview

| Dimension | sbx (sing-box) | xray (Xray-core) |
|-----------|----------------|-------------------|
| Total code | ~22,000 lines | ~19,000 lines |
| Entry point | Monolithic `install.sh` (1,581 lines) | Downloader `install.sh` + CLI dispatcher `bin/xrf` |
| Module loading | `_load_modules()` sequential load (21 modules) | On-demand explicit `source` per command |
| Config format | Single JSON: `/etc/sing-box/config.json` | Numbered JSON: `00_log.json`, `05_inbounds.json`, etc. |
| Management CLI | `sbx-manager.sh` (case dispatch) | `bin/xrf` -> `commands/*.sh` (dispatcher pattern) |
| State storage | Text file: `client-info.txt` | JSON file: `state.json` |
| Protocols | VLESS-Reality + WS-TLS + Hysteria2 | VLESS-Reality + Vision-Reality |
| Test framework | Custom `test_framework.sh` | BATS (industry standard) |

## What sbx Can Learn from xray

### High Priority

| Improvement | xray Reference | sbx Issue |
|-------------|---------------|-----------|
| Structured error codes with remediation | `lib/error_codes.sh` | [#79](https://github.com/xrf9268-hue/sbx/issues/79) |
| Post-install health check system | `lib/health_check.sh` | [#80](https://github.com/xrf9268-hue/sbx/issues/80) |

### Medium Priority

| Improvement | xray Reference | sbx Issue |
|-------------|---------------|-----------|
| `--json` structured output | `core::init()` JSON flag | [#81](https://github.com/xrf9268-hue/sbx/issues/81) |
| SNI domain validation | `lib/sni_validator.sh` | [#82](https://github.com/xrf9268-hue/sbx/issues/82) |
| File locking for concurrent access | `lib/core.sh` `core::with_flock()` | [#83](https://github.com/xrf9268-hue/sbx/issues/83) |

### Low Priority

| Improvement | xray Reference | sbx Issue |
|-------------|---------------|-----------|
| `--dry-run` install preview | `lib/preview.sh` | [#84](https://github.com/xrf9268-hue/sbx/issues/84) |
| ERR trap with line number context | `core::error_handler()` | [#85](https://github.com/xrf9268-hue/sbx/issues/85) |
| JSON state file (replace client-info.txt) | `modules/state.sh` | [#86](https://github.com/xrf9268-hue/sbx/issues/86) |

### Additional Ideas (No Issues Yet)

- Config template presets (`lib/templates.sh`)
- Plugin/event hook system (`lib/plugins.sh`)
- Config digest to skip unnecessary restarts (`digest_confdir()`)
- Architecture Decision Records (`docs/adr/`)
- Same-directory temp files for atomic `mv` safety

## What xray Can Learn from sbx

### High Priority

| Improvement | sbx Reference | xray Issue |
|-------------|--------------|------------|
| Multi-protocol support (WS-TLS + Hysteria2) | `lib/config.sh` `_create_all_inbounds()` | [#36](https://github.com/xrf9268-hue/xray/issues/36) |
| Rich client export (Clash, QR, subscriptions) | `lib/export.sh` (411 lines) | [#37](https://github.com/xrf9268-hue/xray/issues/37) |

### Medium Priority

| Improvement | sbx Reference | xray Issue |
|-------------|--------------|------------|
| Three-layer config validation pipeline | `lib/schema_validator.sh` + `lib/config_validator.sh` | [#38](https://github.com/xrf9268-hue/xray/issues/38) |
| Encrypted backup support | `lib/backup.sh` AES-256-CBC | [#39](https://github.com/xrf9268-hue/xray/issues/39) |
| Bootstrap constants validation test | `tests/unit/test_bootstrap_constants.sh` | [#40](https://github.com/xrf9268-hue/xray/issues/40) |
| IPv6 dual-stack auto-detection | `lib/config.sh` `detect_ipv6_support()` | [#41](https://github.com/xrf9268-hue/xray/issues/41) |

### Low Priority

| Improvement | sbx Reference | xray Issue |
|-------------|--------------|------------|
| Exponential backoff with jitter | `lib/retry.sh` (Google SRE pattern) | [#42](https://github.com/xrf9268-hue/xray/issues/42) |

### Additional Ideas (No Issues Yet)

- Module API verification (`_verify_module_apis()`)
- Certificate backup in archives
- SHA256 archive integrity validation before restore
- Coding standards documentation (`.claude/CODING_STANDARDS.md`)

## Summary

Each project has distinct strengths:

- **sbx excels at**: Multi-protocol support, config validation depth, client export formats, backup encryption, bootstrap reliability
- **xray excels at**: Architecture clarity (command dispatcher), error handling UX, health checks, plugin extensibility, SNI validation, BATS testing

**Top priority cross-pollination**:
1. sbx <- Structured error codes + health checks (user experience)
2. xray <- Multi-protocol + export formats (feature coverage)
