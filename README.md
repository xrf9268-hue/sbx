# sbx-lite

One-click deployment script for sing-box proxy server with VLESS-REALITY support.

## Features

- **Zero configuration** - Auto-detects server IP, works immediately
- **Multi-protocol** - VLESS-REALITY (default), WS-TLS, Hysteria2 (optional)
- **Auto management** - Built-in backup, client export, QR codes
- **Production ready** - sing-box 1.12.0+, encrypted backups, CI/CD tested
- **Enterprise logging** - Debug mode, JSON output, log files, timestamps
- **Easy sharing** - Generate client configs, QR codes, subscription links

## Quick Start

**Install (Reality mode, no domain required)**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

**Install with domain (enables WS-TLS + Hysteria2)**
```bash
DOMAIN=your.domain.com bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

After installation, connection URIs are displayed automatically. Copy them to your client.

## Common Commands

```bash
sbx info          # Show connection URIs and config
sbx qr            # Display QR codes
sbx status        # Check service status
sbx restart       # Restart service
sbx backup create # Create backup
sbx uninstall     # Remove everything
```

**Full command list**: Run `sbx help`

## Client Setup

**Recommended clients**:
- **NekoRay/NekoBox** (Windows/Linux/Mac) - Native sing-box support
- **v2rayN** (Windows) - Switch core to sing-box: Settings → Core → VLESS → sing-box
- **Shadowrocket** (iOS)
- **sing-box official clients** (All platforms)

**Import methods**:
1. Copy URI from terminal output → Paste in client
2. Scan QR code: Run `sbx qr` → Scan with client camera
3. Use exported config: Run `sbx export v2rayn reality` → Import JSON file

## Troubleshooting

**Can't connect**
```bash
sbx status        # Check if service is running
sbx check         # Validate configuration
sbx log           # View error messages
```

**Installation issues - Enable debug logging**
```bash
# Run with detailed debug output and timestamps
DEBUG=1 LOG_TIMESTAMPS=1 bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)

# Save debug log to file for sharing
DEBUG=1 LOG_FILE=/tmp/install-debug.log bash <(curl -fsSL ...)
```

**v2rayN shows "connection failed"**
Switch VLESS core from Xray to sing-box in client settings.

**Need to reconfigure**
Re-run the installation command - it will detect existing installation and offer upgrade/reconfigure options.

**Port conflicts**
Script auto-selects alternative ports (24443, 24444, 24445) if defaults are occupied.

## Advanced Usage

**Debugging & Logging**
```bash
# Debug mode with timestamps (troubleshooting)
DEBUG=1 LOG_TIMESTAMPS=1 bash <(curl -fsSL ...)

# Save installation log to file
LOG_FILE=/var/log/sbx-install.log bash <(curl -fsSL ...)

# JSON format for log analysis tools
LOG_FORMAT=json bash <(curl -fsSL ...)

# Show only errors (silent mode)
LOG_LEVEL_FILTER=ERROR bash <(curl -fsSL ...) 2>/dev/null
```

**Backup and restore**
```bash
sbx backup create --encrypt     # Encrypted backup
sbx backup restore <file>       # Restore from backup
sbx backup cleanup              # Delete old backups
```

**Export configs for different clients**
```bash
sbx export v2rayn reality       # v2rayN JSON
sbx export clash                # Clash YAML
sbx export uri all              # All URIs
sbx export qr ./qr-codes/       # QR code images
```

**Version selection**
```bash
# Latest stable (default)
bash <(curl -fsSL ...)

# Specific version
SINGBOX_VERSION=v1.10.7 bash <(curl -fsSL ...)

# Latest including pre-releases
SINGBOX_VERSION=latest bash <(curl -fsSL ...)
```

## Reality Protocol Support

sbx-lite provides **fully compliant** VLESS + REALITY + Vision protocol implementation verified against sing-box 1.12.0+ official standards.

### Key Features

- ✅ **Zero Configuration**: No domain or certificate required for Reality-only mode
- ✅ **Auto IP Detection**: Automatically detects server public IP via multiple services
- ✅ **Modern Standards**: Full compliance with sing-box 1.12.0+ configuration format
- ✅ **Multi-Format Export**: v2rayN, Clash Meta, QR codes, subscription links
- ✅ **Production Grade**: SHA256 binary verification, comprehensive validation, automated testing
- ✅ **Verified Compliance**: [Independent audit](docs/REALITY_COMPLIANCE_REVIEW.md) confirms 100% compliance
- ✅ **Advanced Features** (Phase 4): JSON schema validation, version compatibility checks, integration testing

### Multi-Phase Development

sbx-lite has been systematically enhanced through a comprehensive improvement plan:

- ✅ **Phase 1**: Documentation & Knowledge Base - [Compliance review](docs/REALITY_COMPLIANCE_REVIEW.md), [sing-box vs Xray comparison](docs/SING_BOX_VS_XRAY.md)
- ✅ **Phase 2**: Testing Infrastructure - 23 unit tests covering validation, config generation, exports
- ✅ **Phase 3**: Code Enhancements - Transport pairing validation, extracted constants, enhanced error messages
- ✅ **Phase 4**: Advanced Features - JSON schema validation, version compatibility, 14 integration tests
- 📝 **Phase 5**: Documentation Finalization - Best practices guide, configuration examples (this release)

See [MULTI_PHASE_IMPROVEMENT_PLAN.md](docs/MULTI_PHASE_IMPROVEMENT_PLAN.md) for detailed roadmap.

### Configuration Validation

Every Reality configuration is validated through multiple layers:

1. **Pre-Generation Validation**: UUID, keypair, short_id format checks
2. **Structure Validation**: JSON schema compliance, proper `tls.reality` nesting
3. **Runtime Validation**: `sing-box check -c /etc/sing-box/config.json`
4. **Service Validation**: Port listening verification, log monitoring
5. **Schema Validation** (Phase 4): Automated JSON schema validation against sing-box 1.12.0+ standards
6. **Version Compatibility** (Phase 4): Ensures sing-box version meets Reality requirements (1.8.0+)

### sing-box vs Xray Differences

If migrating from Xray-based Reality setups, note these key differences:

| Feature | sing-box | Xray | Impact |
|---------|----------|------|---------|
| Short ID Length | 0-8 hex chars | 0-16 hex chars | Use `openssl rand -hex 4` (not `-hex 8`) |
| Config Structure | `tls.reality` | `streamSettings.realitySettings` | Different JSON paths |
| Client Core | sing-box required | Xray | **v2rayN users must switch core to sing-box** |

See [SING_BOX_VS_XRAY.md](docs/SING_BOX_VS_XRAY.md) for complete comparison and migration guide.

## Official Documentation Access

This project includes the official sing-box repository as a git submodule for easy access to the latest documentation and configuration examples.

### For Users (Quick Reference)

Browse official docs online:
- **VLESS Configuration**: https://sing-box.sagernet.org/configuration/inbound/vless/
- **Reality/TLS**: https://sing-box.sagernet.org/configuration/shared/tls/
- **Migration Guide**: https://sing-box.sagernet.org/migration/

### For Developers (Local Access)

**First-Time Setup:**
```bash
# Clone the repository with submodules
git clone --recursive https://github.com/xrf9268-hue/sbx.git
cd sbx

# Or if already cloned, initialize submodule
git submodule update --init --recursive
```

**Update to Latest Official Docs:**
```bash
git submodule update --remote docs/sing-box-official
```

**Key Documentation Paths:**
- VLESS inbound: `docs/sing-box-official/docs/configuration/inbound/vless.md`
- Reality/TLS fields: `docs/sing-box-official/docs/configuration/shared/tls.md`
- Migration guide: `docs/sing-box-official/docs/migration.md`
- Config examples: `docs/sing-box-official/test/config/`

## Documentation

### User Documentation
- **User Guide**: This README
- **Troubleshooting**: [REALITY_TROUBLESHOOTING.md](docs/REALITY_TROUBLESHOOTING.md) - Common issues and solutions
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) - Version history and migration notes

### Developer Documentation
- **Developer Guide**: [CLAUDE.md](CLAUDE.md) - Architecture, development workflow, coding standards
- **Compliance Review**: [REALITY_COMPLIANCE_REVIEW.md](docs/REALITY_COMPLIANCE_REVIEW.md) - Full audit vs official standards
- **Improvement Plan**: [MULTI_PHASE_IMPROVEMENT_PLAN.md](docs/MULTI_PHASE_IMPROVEMENT_PLAN.md) - Roadmap and enhancements
- **sing-box vs Xray**: [SING_BOX_VS_XRAY.md](docs/SING_BOX_VS_XRAY.md) - Differences and migration

### Testing

**Unit Tests** (Phase 2):
```bash
# Run Reality unit tests (23 test cases)
bash tests/test_reality.sh

# Or using make
make test
```

**Integration Tests** (Phase 4):
```bash
# Run comprehensive integration tests (requires installation)
bash tests/integration/test_reality_connection.sh

# Tests include:
# - sing-box binary and version verification
# - Configuration file validity and structure
# - Reality-specific compliance (nesting, short_id, flow)
# - Service status and port listening
# - Client export functionality
```

**Schema Validation** (Phase 4):
```bash
# Validate configuration against JSON schema
source lib/common.sh
source lib/schema_validator.sh
validate_reality_structure /etc/sing-box/config.json

# Check version compatibility
source lib/version.sh
validate_singbox_version
show_version_info
```

**Test Coverage**:
```bash
# Generate coverage report
make coverage

# Current coverage (as of Phase 4):
# - Unit tests: 23 test cases across 5 categories
# - Integration tests: 14 comprehensive checks
# - Phase 4 functions: 100% coverage
```

## System Requirements

- Linux (Debian/Ubuntu/CentOS/RHEL/Fedora)
- Port 443 available (or will use fallback port 24443)
- Root or sudo access
- curl or wget installed

## File Locations

- Configuration: `/etc/sing-box/config.json`
- Service: `/etc/systemd/system/sing-box.service`
- Backups: `/var/backups/sbx/`
- Manager: `/usr/local/bin/sbx`

## License

MIT License - Based on official [sing-box](https://github.com/SagerNet/sing-box)
