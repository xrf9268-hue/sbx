# sbx-lite

One-click sing-box proxy deployment with VLESS-REALITY support.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![sing-box](https://img.shields.io/badge/sing--box-1.12.0+-orange.svg)](https://github.com/SagerNet/sing-box)

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

Done! Connection URIs are displayed after installation. Copy them to your client.

**With domain** (enables multi-protocol):
```bash
DOMAIN=your.domain.com bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

**Cloudflare proxy mode** (when server IP is blocked):
```bash
DOMAIN=your.domain.com CF_MODE=1 bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

**DNS-01 challenge** (when port 80 is blocked):
```bash
CF_API_TOKEN=your_token CERT_MODE=cf_dns DOMAIN=your.domain.com bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

## Features

- **Zero config** - Auto-detects IP, no domain/certs needed
- **Multi-protocol** - VLESS-REALITY, VLESS-WS-TLS, Hysteria2
- **Cloudflare support** - CF_MODE for CDN proxying when IP is blocked
- **DNS-01 challenge** - Certificate issuance without port 80 via Cloudflare API
- **Easy export** - QR codes, v2rayN/Clash configs, share URIs

## Usage

```bash
sbx info      # Show connection URIs
sbx qr        # QR codes for mobile
sbx status    # Service status
sbx check     # Validate config
sbx help      # All commands
```

## Client Setup

| Platform | Recommended Client |
|----------|-------------------|
| Windows/Linux | [NekoRay](https://github.com/MatsuriDayo/nekoray) |
| macOS | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) |
| Android | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) |
| iOS | [sing-box](https://apps.apple.com/app/sing-box/id6451272673) (free) |

**Import**: Copy URI → Paste in client → Connect

> **v2rayN/v2rayNG users**: Switch core to sing-box in Settings → Core Type

## Troubleshooting

```bash
sbx status    # Is service running?
sbx check     # Config valid?
sbx log       # Error messages?
```

**Common fix**: v2rayN "connection failed" → Switch core from Xray to sing-box

See [REALITY_TROUBLESHOOTING.md](docs/REALITY_TROUBLESHOOTING.md) for more solutions.

## Requirements

- Linux (Debian, Ubuntu, CentOS, Fedora, RHEL)
- Root access
- Ports available (default mode):
  - **443/tcp** - VLESS-Reality
  - **80/tcp** - ACME HTTP-01 challenge (certificate issuance, with domain)
  - **8444/tcp** - VLESS-WS-TLS (with domain)
  - **8443/udp** - Hysteria2 (with domain)
- Ports available (CF_MODE=1):
  - **443/tcp** - VLESS-WS-TLS only (through Cloudflare CDN)
- Ports available (CERT_MODE=cf_dns):
  - **443/tcp** - VLESS-Reality + WS-TLS (no port 80 needed)

## Documentation

| Doc | Description |
|-----|-------------|
| [Troubleshooting](docs/REALITY_TROUBLESHOOTING.md) | Connection & installation issues |
| [Best Practices](docs/REALITY_BEST_PRACTICES.md) | Security & performance tips |
| [Advanced Options](docs/ADVANCED.md) | Environment variables & customization |
| [Contributing](CONTRIBUTING.md) | Developer setup & guidelines |

## License

MIT License - Based on [sing-box](https://github.com/SagerNet/sing-box) by SagerNet
