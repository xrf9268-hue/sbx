# Reality-Only Configuration Example

This example demonstrates a minimal Reality-only server configuration - the simplest and most common setup.

## Overview

**What you get:**
- **No domain required** - Works with IP address only
- **No certificate required** - Reality handles TLS
- **Auto IP detection** - Server detects its own public IP
- **Production ready** - Complete with all required settings

**Use case:**
- First-time Reality setup
- Testing and development
- Simple proxy server without domain
- Cost-effective deployment (no domain/certificate costs)

## Requirements

- Linux server with public IPv4 address
- sing-box 1.13.0+
- Port 443 available (or any port you specify)
- No domain or certificate required

## Setup Steps

### Step 1: Generate Materials

```bash
# 1. Generate UUID
UUID=$(sing-box generate uuid)
echo "UUID: $UUID"

# 2. Generate Reality keypair
KEYPAIR=$(sing-box generate reality-keypair)
echo "$KEYPAIR"
# Output:
# PrivateKey: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# PublicKey: YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY

# 3. Generate Short ID (8 hex characters)
SHORT_ID=$(openssl rand -hex 4)
echo "Short ID: $SHORT_ID"

# 4. Get server IP
SERVER_IP=$(curl -4 ifconfig.me)
echo "Server IP: $SERVER_IP"
```

### Step 2: Update Configuration

Edit `server-config.json` and replace these placeholders:

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `REPLACE_WITH_YOUR_UUID` | UUID from step 1 | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `REPLACE_WITH_YOUR_PRIVATE_KEY` | PrivateKey from step 1 | `UuMBgl7MXTPx...` |
| `REPLACE_WITH_YOUR_PUBLIC_KEY` | PublicKey from step 1 | `jNXHt1yRo0vD...` |
| `REPLACE_WITH_YOUR_SHORT_ID` | Short ID from step 1 | `a1b2c3d4` |
| `YOUR_SERVER_IP` | Server IP from step 1 | `1.2.3.4` |

### Step 3: Validate Configuration

```bash
# Check JSON syntax
jq empty server-config.json

# Validate with sing-box
sing-box check -c server-config.json

# Should output: configuration test passed
```

### Step 4: Deploy

**Option A: Using sbx-lite (Recommended)**

sbx-lite automatically generates all materials and configurations:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

**Option B: Manual Deployment**

```bash
# Copy configuration
sudo cp server-config.json /etc/sing-box/config.json

# Create systemd service
sudo nano /etc/systemd/system/sing-box.service
# (See server-config.json comments for service file)

# Start service
sudo systemctl daemon-reload
sudo systemctl enable sing-box
sudo systemctl start sing-box

# Check status
sudo systemctl status sing-box
```

### Step 5: Client Setup

#### v2rayN/v2rayNG (Windows/Android)

1. **Switch to sing-box core** (IMPORTANT!)
   - Settings → Core Type → VLESS → **sing-box**
   - Restart v2rayN

2. **Import configuration**:
   - **Option A**: Use share URI from `share-uri.txt`
     - Copy URI → Import from clipboard
   - **Option B**: Import JSON
     - Update `client-v2rayn.json` with your PublicKey and Short ID
     - Import → Import from file

#### Clash Meta (All platforms)

1. Update `client-clash.yaml`:
   - Replace `YOUR_SERVER_IP` with server IP
   - Replace `YOUR_PUBLIC_KEY` with PublicKey
   - Replace `YOUR_SHORT_ID` with Short ID

2. Import to Clash Meta:
   ```bash
   # Copy to Clash config directory
   cp client-clash.yaml ~/.config/clash-meta/config.yaml
   clash-meta -d ~/.config/clash-meta
   ```

#### v2rayN / Hiddify / sing-box App

1. Import share URI from `share-uri.txt`
2. Or manually create:
   - Protocol: VLESS
   - Address: YOUR_SERVER_IP
   - Port: 443
   - UUID: (your UUID)
   - Flow: xtls-rprx-vision
   - Security: reality
   - Public Key: (your public key)
   - Short ID: (your short ID)
   - SNI: www.microsoft.com

> **v2rayN users**: Switch core to sing-box in Settings → Core Type

## Testing

```bash
# On server - check service
sudo systemctl status sing-box
sudo journalctl -u sing-box -f

# On server - verify port listening
sudo ss -lntp | grep :443

# On client - test connection
curl --proxy socks5://127.0.0.1:10808 https://www.google.com
# Should show Google homepage HTML
```

## Troubleshooting

### Service fails to start

```bash
# Check configuration
sudo sing-box check -c /etc/sing-box/config.json

# Check logs
sudo journalctl -u sing-box -n 50 --no-pager
```

### Client can't connect

**Check server:**
```bash
# Verify port open
sudo ss -lntp | grep :443

# Check firewall
sudo ufw status  # Ubuntu
sudo firewall-cmd --list-all  # CentOS
```

**Check client:**
- Verify sing-box core selected (v2rayN users!)
- Confirm UUID, public key, short ID match server
- Check server IP is correct

### "Invalid short ID" error

- Short ID must be exactly 8 hex characters
- Generate with: `openssl rand -hex 4` (not `-hex 8`!)
- Ensure it's in array format in JSON: `["a1b2c3d4"]`

### "Reality handshake failed"

- Public/private key mismatch
- Regenerate keypair: `sing-box generate reality-keypair`
- Use private key on server, public key on client
- Both keys must be from the same generation

## Configuration Highlights

**Reality-specific features in this example:**

```json
"tls": {
  "enabled": true,  // TLS must be enabled for Reality
  "server_name": "www.microsoft.com",  // SNI for camouflage
  "reality": {
    "enabled": true,
    "handshake": {
      "server": "www.microsoft.com",  // Must match server_name
      "server_port": 443
    },
    "max_time_difference": "1m"  // Anti-replay protection
  }
}
```

**Flow field for Vision protocol:**

```json
"users": [{
  "uuid": "...",
  "flow": "xtls-rprx-vision"  // Required for Reality + Vision
}]
```

## Security Notes

1. **Never share private key** - Only public key goes to clients
2. **Use unique UUID per user** - For multi-user setups
3. **Rotate credentials** - Periodically regenerate keypairs
4. **Monitor logs** - Check for unauthorized connection attempts
5. **Keep updated** - Always use latest sing-box version

## Next Steps

- **Add more users**: See `../advanced/multiple-users.json`
- **Add WebSocket**: See `../reality-with-ws/`
- **Custom SNI**: See `../advanced/custom-sni.json`
- **Production deployment**: Use sbx-lite for automated management

## References

- [sing-box VLESS Documentation](https://sing-box.sagernet.org/configuration/inbound/vless/)
- [Reality TLS Configuration](https://sing-box.sagernet.org/configuration/shared/tls/)
- [sbx-lite Reality Compliance Review](../../docs/REALITY_COMPLIANCE_REVIEW.md)
- [sing-box vs Xray Differences](../../docs/SING_BOX_VS_XRAY.md)
