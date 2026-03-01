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

### Cloudflare Proxy Mode

When your server IP is blocked or network is restricted, use Cloudflare CDN to proxy traffic:

```bash
# Enable Cloudflare proxy mode (WS-TLS only on port 443)
sudo DOMAIN=your.domain.com CF_MODE=1 bash install.sh
```

**CF_MODE=1 behavior:**
- Disables Reality protocol (not compatible with CDN proxying)
- Disables Hysteria2 protocol (Cloudflare doesn't proxy UDP)
- Sets WS-TLS port to 443 (CF-supported HTTPS port)

**Required Cloudflare settings:**
- DNS Proxy Status: Orange cloud (Proxied)
- SSL/TLS Mode: Full

**Protocol control variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `CF_MODE` | 0 | Enable Cloudflare proxy mode |
| `ENABLE_REALITY` | 1 | Enable VLESS-Reality protocol |
| `ENABLE_WS` | 1 | Enable VLESS-WS-TLS protocol |
| `ENABLE_HY2` | 1 | Enable Hysteria2 protocol |
| `WS_PORT` | 8444 (443 in CF_MODE) | WebSocket TLS port |

**Cloudflare supported HTTPS ports:** 443, 2053, 2083, 2087, 2096, 8443

**Custom configuration example:**
```bash
# CF mode with Reality on fallback port for direct connection
sudo DOMAIN=your.domain.com CF_MODE=1 ENABLE_REALITY=1 REALITY_PORT=24443 bash install.sh

# CF mode with custom WS port (must be CF-supported)
sudo DOMAIN=your.domain.com CF_MODE=1 WS_PORT=2053 bash install.sh
```

### Version Selection

```bash
SINGBOX_VERSION=stable    # Latest stable (default)
SINGBOX_VERSION=v1.13.0   # Specific version
SINGBOX_VERSION=latest    # Including pre-releases
```

### Custom Certificates

```bash
CERT_MODE=caddy                        # Auto TLS via Caddy HTTP-01 (default)
CERT_MODE=cf_dns                       # DNS-01 via Cloudflare API (no port 80 needed)
CERT_FULLCHAIN=/path/to/fullchain.pem  # Custom certificate
CERT_KEY=/path/to/privkey.pem          # Custom private key
```

#### DNS-01 Challenge with Cloudflare

When port 80 is unavailable (blocked by firewall, in use, or restricted by cloud provider), use DNS-01 challenge:

```bash
# Set Cloudflare API token and enable DNS-01 mode
CF_API_TOKEN=your_cf_api_token CERT_MODE=cf_dns DOMAIN=your.domain.com bash install.sh
```

**Requirements:**
- Cloudflare API token with Zone:DNS:Edit permissions
- Domain managed by Cloudflare DNS

##### How to Create a Cloudflare API Token

1. **Log in to Cloudflare Dashboard**
   - Go to https://dash.cloudflare.com/
   - Sign in with your Cloudflare account

2. **Navigate to API Tokens**
   - Click your profile icon (top right)
   - Select **My Profile**
   - Click **API Tokens** tab

3. **Create Custom Token**
   - Click **Create Token**
   - Click **Get started** under "Create Custom Token"

4. **Configure Token Permissions**
   - **Token name**: `sbx-dns-01` (or any descriptive name)
   - **Permissions**:
     - Zone → DNS → Edit
   - **Zone Resources**:
     - Include → Specific zone → Select your domain
   - **Client IP Address Filtering** (optional but recommended):
     - Add your server's IP for extra security
   - **TTL** (optional):
     - Set expiration date if desired

5. **Create and Copy Token**
   - Click **Continue to summary**
   - Click **Create Token**
   - **Copy the token immediately** (it won't be shown again)

6. **Use the Token**
   ```bash
   CF_API_TOKEN=your_copied_token CERT_MODE=cf_dns DOMAIN=your.domain.com bash install.sh
   ```

**Token format:** Cloudflare API tokens are 40 alphanumeric characters (e.g., `abcdefghijklmnopqrstuvwxyz1234567890ABCD`).

**Security note:** The Caddy binary for DNS-01 mode is downloaded from caddyserver.com/api/download with dual-download integrity verification. For maximum security, build Caddy locally with xcaddy.

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
