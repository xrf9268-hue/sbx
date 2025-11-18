# sbx-lite

> One-click deployment script for sing-box proxy server with VLESS-REALITY support

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![sing-box](https://img.shields.io/badge/sing--box-1.12.0+-orange.svg)](https://github.com/SagerNet/sing-box)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen.svg)](tests/)

## Features

- **Zero Configuration** - Auto-detects server IP, works immediately without domain or certificates
- **Multi-Protocol Support** - VLESS-REALITY (default), VLESS-WS-TLS, Hysteria2
- **Automatic Management** - Built-in backup, client export, QR codes, subscription links
- **Production Ready** - SHA256 binary verification, encrypted backups, automated testing
- **Enterprise Logging** - Debug mode, JSON output, file logging, structured timestamps
- **Easy Client Setup** - Generate configs for v2rayN, Clash, NekoRay, or scan QR codes

## Quick Start

### Basic Installation (Reality-only, no domain required)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

After installation, connection URIs are displayed automatically. Copy and paste them into your client.

### Advanced Installation (with domain for multi-protocol)

```bash
DOMAIN=your.domain.com bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

This enables VLESS-WS-TLS and Hysteria2 in addition to VLESS-REALITY.

## Management Commands

```bash
sbx info          # Show connection URIs and configuration
sbx qr            # Display QR codes for mobile import
sbx status        # Check service status
sbx restart       # Restart service
sbx check         # Validate configuration
sbx log           # View recent logs

# Backup operations
sbx backup create --encrypt    # Create encrypted backup
sbx backup restore <file>      # Restore from backup

# Export client configurations
sbx export v2rayn reality      # Export v2rayN JSON config
sbx export clash               # Export Clash YAML config
sbx export uri all             # Export all share URIs
sbx export qr ./qr-codes/      # Generate QR code images

# Management
sbx uninstall     # Remove everything
sbx help          # Show all commands
```

## Client Setup

### Recommended Clients

| Platform | Client | Notes |
|----------|--------|-------|
| Windows | NekoRay | Native sing-box support (recommended) |
| Windows | v2rayN | Requires switching core to sing-box |
| macOS | NekoBox | Native sing-box support |
| Linux | NekoRay | Native sing-box support |
| Android | v2rayNG | Requires switching core to sing-box |
| Android | NekoBox | Native sing-box support |
| iOS | Shadowrocket | Commercial app |
| iOS | sing-box | Official client (free) |

### Import Methods

**Method 1: Copy URI** (Easiest)
1. Copy the URI from installation output
2. Paste into your client's import dialog

**Method 2: Scan QR Code** (Mobile)
1. Run `sbx qr` on server
2. Scan with client app

**Method 3: Export Configuration File**
```bash
sbx export v2rayn reality > config.json
# Import config.json in your client
```

### Important: v2rayN/v2rayNG Users

If using v2rayN or v2rayNG, you **must** switch the core from Xray to sing-box:
- **v2rayN**: Settings → Core Type → VLESS → sing-box
- **v2rayNG**: Settings → Core → sing-box

## Troubleshooting

### Connection Issues

```bash
sbx status        # Check if service is running
sbx check         # Validate configuration
sbx log           # View error messages
```

### Installation Issues

Enable debug logging to diagnose problems:

```bash
# Debug mode with timestamps
DEBUG=1 LOG_TIMESTAMPS=1 bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)

# Save debug log to file
DEBUG=1 LOG_FILE=/tmp/install-debug.log bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

### Common Problems

**Problem**: v2rayN shows "connection failed"
**Solution**: Switch VLESS core from Xray to sing-box in client settings

**Problem**: Port conflicts during installation
**Solution**: Script automatically uses fallback ports (24443, 24444, 24445)

**Problem**: Need to reconfigure after installation
**Solution**: Re-run installation command - it will detect existing setup and offer options

**Problem**: Service fails to start
**Solution**: Check logs with `sbx log` and validate config with `sbx check`

For more solutions, see [REALITY_TROUBLESHOOTING.md](docs/REALITY_TROUBLESHOOTING.md)

## Advanced Usage

### Environment Variables

```bash
# Domain/IP configuration
DOMAIN=your.domain.com    # Enable full setup with automatic TLS
DOMAIN=1.2.3.4            # Reality-only with explicit IP

# Version selection
SINGBOX_VERSION=stable    # Latest stable (default)
SINGBOX_VERSION=v1.10.7   # Specific version
SINGBOX_VERSION=latest    # Including pre-releases

# Certificate management
CERT_MODE=caddy                      # Automatic TLS via Caddy (default)
CERT_FULLCHAIN=/path/to/fullchain.pem
CERT_KEY=/path/to/privkey.pem

# Logging options
DEBUG=1                              # Enable debug output
LOG_TIMESTAMPS=1                     # Add timestamps
LOG_FORMAT=json                      # JSON output
LOG_FILE=/var/log/sbx-install.log    # Log to file
LOG_LEVEL_FILTER=ERROR               # Filter by severity
```

### Version Selection Example

```bash
# Install latest stable version (default)
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)

# Install specific version
SINGBOX_VERSION=v1.10.7 bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)

# Install latest including pre-releases
SINGBOX_VERSION=latest bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
```

## System Requirements

- **OS**: Linux (Debian, Ubuntu, CentOS, RHEL, Fedora)
- **Network**: Port 443 available (or fallback port 24443)
- **Privileges**: Root or sudo access
- **Dependencies**: curl or wget (automatically detected)

## File Locations

- Configuration: `/etc/sing-box/config.json`
- Service: `/etc/systemd/system/sing-box.service`
- Backups: `/var/backups/sbx/`
- Manager: `/usr/local/bin/sbx`
- Certificates: `/etc/ssl/sbx/<domain>/`

## Reality Protocol

sbx-lite provides fully compliant VLESS + REALITY + Vision protocol implementation verified against [sing-box 1.12.0+ official standards](https://sing-box.sagernet.org/).

**Key advantages**:
- No domain or certificate required for Reality-only mode
- Automatic server IP detection via multiple fallback services
- Full compliance with sing-box 1.12.0+ configuration format
- Multi-format client config export (v2rayN, Clash, QR codes)
- Comprehensive validation and testing (23 unit tests, 14 integration tests)

**Migrating from Xray?** See [SING_BOX_VS_XRAY.md](docs/SING_BOX_VS_XRAY.md) for key differences.

## Documentation

- **User Guide**: This README
- **Troubleshooting**: [REALITY_TROUBLESHOOTING.md](docs/REALITY_TROUBLESHOOTING.md)
- **Best Practices**: [REALITY_BEST_PRACTICES.md](docs/REALITY_BEST_PRACTICES.md)
- **Developer Guide**: [CLAUDE.md](CLAUDE.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Official sing-box Docs**: https://sing-box.sagernet.org/

### Accessing Official sing-box Documentation Locally

This project includes the official sing-box repository as a git submodule for easy access to the latest documentation.

**First-Time Setup:**
```bash
git submodule update --init --recursive
```

**Update to Latest Official Docs:**
```bash
git submodule update --remote docs/sing-box-official
```

**Key Documentation Paths:**
- **VLESS Configuration**: `docs/sing-box-official/docs/configuration/inbound/vless.md`
- **Reality/TLS Configuration**: `docs/sing-box-official/docs/configuration/shared/tls.md`
- **Migration Guide**: `docs/sing-box-official/docs/migration.md`

## Contributing

Contributions are welcome! **Before you start:**

### 🚨 REQUIRED: Install Git Hooks

```bash
# One-time setup (MANDATORY)
bash hooks/install-hooks.sh
```

This installs pre-commit hooks that **automatically enforce code quality** and prevent recurring bugs. The hooks have prevented **6+ production failures** in the past.

### Development Workflow

1. **Fork the repository**
2. **Install git hooks** (see above - **REQUIRED**)
3. **Create feature branch**: `git checkout -b feature/amazing-feature`
4. **Make changes** following code standards
5. **Run tests**: `bash tests/test-runner.sh unit`
6. **Commit** (hooks run automatically): `git commit -m 'feat: add amazing feature'`
7. **Push**: `git push origin feature/amazing-feature`
8. **Open Pull Request**

### Documentation

- **Contributing Guide**: [CONTRIBUTING.md](CONTRIBUTING.md) - **Read this first!**
- **Developer Guide**: [CLAUDE.md](CLAUDE.md) - Detailed coding standards
- **Bootstrap Testing**: [tests/unit/README_BOOTSTRAP_TESTS.md](tests/unit/README_BOOTSTRAP_TESTS.md)

**⚠️ Note:** Pull requests without git hooks installed will likely fail CI checks.

### Code Quality

sbx-lite maintains high code quality standards through:

**Modular Architecture:**
- 18 library modules (11 core + 7 specialized)
- ~4,100 lines of production code
- Clear separation of concerns

**Code Quality Improvements (2025-11-17):**
- ✅ Helper functions reduce duplication:
  - `create_temp_dir()` / `create_temp_file()` - Secure temp file creation
  - `require()` / `require_all()` / `require_valid()` - Parameter validation
  - `validate_file_integrity()` - Certificate/key validation
  - `json_parse()` / `json_build()` - JSON operations with fallbacks
  - `crypto_random_hex()` / `crypto_sha256()` - Crypto operations
- ✅ Magic numbers extracted to named constants
- ✅ Consistent error messaging via centralized templates
- ✅ Comprehensive validation pipeline for configurations

**Testing:**
- 23 unit tests (100% pass rate)
- 14 integration tests
- CI/CD with ShellCheck validation
- Coverage tracking for critical functions

## License

MIT License - See [LICENSE](LICENSE) for details

Based on official [sing-box](https://github.com/SagerNet/sing-box) by SagerNet

## Acknowledgments

- [sing-box](https://github.com/SagerNet/sing-box) - Modern universal proxy platform
- [REALITY Protocol](https://github.com/XTLS/REALITY) - Anti-censorship technology
- All contributors and users of this project
