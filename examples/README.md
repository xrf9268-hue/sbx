# Reality Configuration Examples

This directory contains practical sing-box Reality configuration examples for different use cases.

## Directory Structure

```
examples/
├── reality-only/           # Minimal Reality-only setup (no domain required)
│   ├── server-config.json  # Complete server configuration
│   ├── client-v2rayn.json  # v2rayN/v2rayNG client config
│   ├── client-clash.yaml   # Clash/Clash Meta client config
│   ├── share-uri.txt       # Share URI for easy import
│   └── README.md           # Setup guide
│
├── reality-with-ws/        # Reality + WebSocket TLS combo
│   ├── server-config.json  # Server with both protocols
│   ├── client-reality.json # Reality client config
│   ├── client-ws.json      # WebSocket client config
│   └── README.md           # Setup guide
│
├── advanced/               # Advanced configurations
│   ├── multiple-users.json # Multi-user setup
│   ├── custom-sni.json     # Custom SNI configuration
│   ├── fallback-config.json# Fallback handling
│   └── README.md           # Advanced usage guide
│
└── troubleshooting/        # Debugging examples
    ├── common-errors.md    # Common issues and solutions
    └── debug-configs/      # Test configurations
```

## Quick Start

### Reality-Only Example (Most Common)

The simplest setup - no domain or certificate required:

```bash
cd examples/reality-only/
cat README.md  # Read setup instructions
```

**What you get:**
- Minimal configuration that works out of the box
- Auto-detects server IP
- Client configurations for v2rayN and Clash
- Share URI for quick import

### Reality + WebSocket Example

For scenarios requiring domain-based setup:

```bash
cd examples/reality-with-ws/
cat README.md  # Read setup instructions
```

**What you get:**
- Reality for best performance
- WebSocket TLS as fallback
- Works with domains and certificates

### Advanced Examples

For power users and special scenarios:

```bash
cd examples/advanced/
cat README.md  # Read advanced guide
```

**Includes:**
- Multiple user management
- Custom SNI servers
- Fallback configurations
- Performance tuning

## Configuration Checklist

Before using any example configuration:

- [ ] Replace `REPLACE_WITH_YOUR_UUID` with actual UUID
  ```bash
  sing-box generate uuid
  ```

- [ ] Replace `REPLACE_WITH_YOUR_PRIVATE_KEY` / `REPLACE_WITH_YOUR_PUBLIC_KEY`
  ```bash
  sing-box generate reality-keypair
  ```

- [ ] Replace `REPLACE_WITH_YOUR_SHORT_ID` (8 hex characters)
  ```bash
  openssl rand -hex 4
  ```

- [ ] Replace `YOUR_SERVER_IP` with your actual server IP
  ```bash
  curl -4 ifconfig.me
  ```

- [ ] Validate configuration before deploying
  ```bash
  sing-box check -c server-config.json
  ```

## Validation Commands

**Always validate configurations before deployment:**

```bash
# JSON syntax check
jq empty server-config.json

# sing-box validation
sing-box check -c server-config.json

# Reality structure validation (if using sbx-lite)
source /path/to/sbx/lib/common.sh
source /path/to/sbx/lib/schema_validator.sh
validate_reality_structure server-config.json
```

## Common Mistakes to Avoid

### 1. Short ID Length
❌ **Wrong**: Using 16 characters (Xray format)
```bash
openssl rand -hex 8  # Produces 16 chars - TOO LONG for sing-box
```

✅ **Correct**: Using 8 characters (sing-box format)
```bash
openssl rand -hex 4  # Produces 8 chars - CORRECT
```

### 2. Reality Nesting
❌ **Wrong**: Reality at top level
```json
{
  "inbounds": [{
    "type": "vless",
    "reality": { ... }  // ERROR: Not under tls
  }]
}
```

✅ **Correct**: Reality under tls
```json
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "enabled": true,
      "reality": { ... }  // CORRECT: Under tls
    }
  }]
}
```

### 3. Short ID Type
❌ **Wrong**: String format
```json
"short_id": "a1b2c3d4"  // ERROR: String
```

✅ **Correct**: Array format
```json
"short_id": ["a1b2c3d4"]  // CORRECT: Array
```

### 4. Flow Field Location
❌ **Wrong**: At inbound level
```json
{
  "inbounds": [{
    "type": "vless",
    "flow": "xtls-rprx-vision",  // ERROR: Wrong location
    "users": [{ "uuid": "..." }]
  }]
}
```

✅ **Correct**: In users array
```json
{
  "inbounds": [{
    "type": "vless",
    "users": [{
      "uuid": "...",
      "flow": "xtls-rprx-vision"  // CORRECT: In users
    }]
  }]
}
```

## Getting Help

- **Troubleshooting**: See `troubleshooting/common-errors.md`
- **Reality Compliance**: See `../docs/REALITY_COMPLIANCE_REVIEW.md`
- **sing-box vs Xray**: See `../docs/SING_BOX_VS_XRAY.md`
- **Best Practices**: See `../docs/REALITY_BEST_PRACTICES.md`

## Contributing Examples

Have a useful configuration example? Contributions welcome!

1. Create a new directory under `examples/`
2. Include complete server and client configurations
3. Add README.md with setup instructions
4. Test the configuration before submitting
5. Submit pull request

## License

All examples are provided under MIT License, same as the main project.
