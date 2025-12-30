# Advanced Options

Environment variables and customization options for sbx-lite.

## Environment Variables

### Domain & Protocol

```bash
# Reality-only (default, no domain needed)
bash install.sh

# Multi-protocol with domain (VLESS-WS-TLS + Hysteria2)
DOMAIN=your.domain.com bash install.sh

# Reality-only with explicit IP
DOMAIN=1.2.3.4 bash install.sh
```

### Version Selection

```bash
SINGBOX_VERSION=stable    # Latest stable (default)
SINGBOX_VERSION=v1.12.0   # Specific version
SINGBOX_VERSION=latest    # Including pre-releases
```

### Custom Certificates

```bash
CERT_MODE=caddy                        # Auto TLS via Caddy (default)
CERT_FULLCHAIN=/path/to/fullchain.pem  # Custom certificate
CERT_KEY=/path/to/privkey.pem          # Custom private key
```

### Debugging

```bash
DEBUG=1                   # Enable debug output
LOG_TIMESTAMPS=1          # Add timestamps
LOG_FILE=/tmp/debug.log   # Log to file
LOG_FORMAT=json           # JSON output format
```

## File Locations

| File | Path |
|------|------|
| Config | `/etc/sing-box/config.json` |
| Service | `/etc/systemd/system/sing-box.service` |
| Manager | `/usr/local/bin/sbx` |
| Backups | `/var/backups/sbx/` |
| Certificates | `/etc/ssl/sbx/<domain>/` |

## Backup & Restore

```bash
# Create encrypted backup
sbx backup create --encrypt

# List backups
sbx backup list

# Restore from backup
sbx backup restore /var/backups/sbx/sbx-backup-20250101-120000.tar.gz.enc
```

## Export Formats

```bash
sbx export v2rayn reality    # v2rayN JSON config
sbx export clash             # Clash YAML config
sbx export uri all           # Share URIs (all protocols)
sbx export qr ./output/      # QR code images
```

## sing-box Submodule

Access official sing-box documentation locally:

```bash
# First-time setup
git submodule update --init --recursive

# Update to latest
git submodule update --remote docs/sing-box-official
```

Key paths:
- VLESS: `docs/sing-box-official/docs/configuration/inbound/vless.md`
- TLS/Reality: `docs/sing-box-official/docs/configuration/shared/tls.md`
