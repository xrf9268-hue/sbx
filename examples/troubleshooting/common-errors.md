# Common Reality Configuration Errors

This guide covers the most common errors when setting up Reality protocol and how to fix them.

## Table of Contents

- [Configuration Errors](#configuration-errors)
- [Connection Errors](#connection-errors)
- [Service Errors](#service-errors)
- [Client-Specific Errors](#client-specific-errors)

---

## Configuration Errors

### 1. Invalid Short ID Length

**Error Message:**
```
validation error: short_id must be 1-8 hexadecimal characters
```

**Cause:**
Using Xray's 16-character short ID format instead of sing-box's 8-character limit.

**Wrong:**
```bash
openssl rand -hex 8  # Produces 16 characters
```

**Correct:**
```bash
openssl rand -hex 4  # Produces 8 characters
```

**Configuration Check:**
```bash
# Verify short ID length
echo "YOUR_SHORT_ID" | wc -c
# Should output: 9 (8 characters + newline)
```

---

### 2. Reality Not Nested Under TLS

**Error Message:**
```
unknown field 'reality' in inbound configuration
```

**Cause:**
Reality configuration placed at top level instead of under `tls.reality`.

**Wrong:**
```json
{
  "inbounds": [{
    "type": "vless",
    "reality": {
      "enabled": true,
      ...
    }
  }]
}
```

**Correct:**
```json
{
  "inbounds": [{
    "type": "vless",
    "tls": {
      "enabled": true,
      "reality": {
        "enabled": true,
        ...
      }
    }
  }]
}
```

---

### 3. Short ID String Instead of Array

**Error Message:**
```
type error: expected array, got string
```

**Cause:**
Short ID defined as string instead of array.

**Wrong:**
```json
"short_id": "a1b2c3d4"
```

**Correct:**
```json
"short_id": ["a1b2c3d4"]
```

---

### 4. Flow Field in Wrong Location

**Error Message:**
```
flow field not recognized in inbound configuration
```

**Cause:**
Flow field placed at inbound level instead of in users array.

**Wrong:**
```json
{
  "inbounds": [{
    "type": "vless",
    "flow": "xtls-rprx-vision",
    "users": [{"uuid": "..."}]
  }]
}
```

**Correct:**
```json
{
  "inbounds": [{
    "type": "vless",
    "users": [{
      "uuid": "...",
      "flow": "xtls-rprx-vision"
    }]
  }]
}
```

---

## Connection Errors

### 5. Reality Handshake Failed

**Error Message:**
```
reality handshake failed: authentication failure
```

**Possible Causes:**

1. **Public/Private Key Mismatch**
   - Server uses private key
   - Client uses public key from SAME keypair

**Solution:**
```bash
# Regenerate keypair
sing-box generate reality-keypair
# Output:
# PrivateKey: XXX  ← Use on SERVER
# PublicKey: YYY   ← Use on CLIENT
```

2. **Short ID Mismatch**
   - Client short ID must match one in server's short_id array

**Check:**
```bash
# Server config
jq '.inbounds[0].tls.reality.short_id' /etc/sing-box/config.json

# Client config
# Verify short ID matches
```

3. **SNI Mismatch**
   - Server `tls.server_name` must match `reality.handshake.server`

**Verify:**
```json
{
  "tls": {
    "server_name": "www.microsoft.com",  // Must match below
    "reality": {
      "handshake": {
        "server": "www.microsoft.com"     // Must match above
      }
    }
  }
}
```

---

### 6. Network Unreachable (IPv6)

**Error Message:**
```
dial tcp [::1]:443: connect: network unreachable
```

**Cause:**
IPv4-only server trying to use IPv6 due to missing DNS strategy.

**Solution:**
Add DNS strategy to configuration:

```json
{
  "dns": {
    "servers": [...],
    "strategy": "ipv4_only"  // Add this line
  }
}
```

**Note:** This is a sing-box 1.12.0+ requirement. Do NOT use deprecated `domain_strategy` in outbounds.

---

### 7. Connection Timeout

**Error Message:**
```
dial tcp YOUR_IP:443: i/o timeout
```

**Diagnostic Steps:**

1. **Check server is running:**
```bash
sudo systemctl status sing-box
```

2. **Verify port is listening:**
```bash
sudo ss -lntp | grep :443
```

3. **Check firewall:**
```bash
# Ubuntu/Debian
sudo ufw status
sudo ufw allow 443/tcp

# CentOS/RHEL
sudo firewall-cmd --list-all
sudo firewall-cmd --add-port=443/tcp --permanent
sudo firewall-cmd --reload
```

4. **Test connectivity:**
```bash
# From client machine
telnet YOUR_SERVER_IP 443
# Should connect (then Ctrl+C to exit)
```

---

## Service Errors

### 8. Service Fails to Start

**Error Message:**
```
sing-box.service: Failed with result 'exit-code'
```

**Diagnostic Steps:**

1. **Check configuration syntax:**
```bash
sudo sing-box check -c /etc/sing-box/config.json
```

2. **View detailed logs:**
```bash
sudo journalctl -u sing-box -n 50 --no-pager
```

3. **Common issues in logs:**

**Port already in use:**
```
bind: address already in use
```
**Solution:** Change port or stop conflicting service:
```bash
# Find what's using the port
sudo lsof -i :443

# Change port in config or stop conflicting service
```

**Permission denied:**
```
listen tcp :443: bind: permission denied
```
**Solution:** Run as root or use port >1024:
```bash
# Run as service (automatically uses root)
sudo systemctl start sing-box

# Or change to port 8443 in config
```

---

### 9. Configuration Validation Errors

**Error Message:**
```
configuration validation failed: unknown field 'domain_strategy'
```

**Cause:**
Using deprecated sing-box 1.12.0 fields.

**Deprecated Fields (DO NOT USE):**
- `domain_strategy` in outbounds → Use `dns.strategy` instead
- `sniff` in inbound → Use `route.rules` with `action: "sniff"`
- `domain_strategy` in any location → Global DNS strategy only

**Migration:**
```json
// OLD (sing-box <1.12.0)
{
  "outbounds": [{
    "type": "direct",
    "domain_strategy": "ipv4_only"  // DEPRECATED
  }]
}

// NEW (sing-box 1.12.0+)
{
  "dns": {
    "strategy": "ipv4_only"  // Global DNS strategy
  },
  "outbounds": [{
    "type": "direct"  // No domain_strategy
  }]
}
```

---

## Client-Specific Errors

### 10. v2rayN Connection Failed

**Symptoms:**
- Other clients work
- v2rayN shows "connection failed" or "handshake timeout"

**Cause:**
v2rayN using Xray core instead of sing-box core.

**Solution:**
1. Open v2rayN settings
2. Go to: Settings → Core Type Settings  → VLESS
3. Change from "Xray" to "sing-box"
4. Restart v2rayN
5. Reconnect

**Verification:**
Check v2rayN logs - should show "sing-box" not "xray".

---

### 11. Clash Meta Parse Error

**Error Message:**
```
yaml: unmarshal errors: field reality-opts not found
```

**Cause:**
Using Clash (original) instead of Clash Meta.

**Solution:**
- Use Clash Meta (mihomo) - supports Reality
- Or use Clash Premium
- Regular Clash does not support Reality protocol

**Check version:**
```bash
clash -v
# Should show: Clash Meta or Clash Premium
```

---

### 12. NekoRay/NekoBox Import Failed

**Symptoms:**
- URI import shows error
- "Invalid configuration" message

**Common Causes:**

1. **Line breaks in URI**
```bash
# WRONG (line breaks)
vless://uuid@ip:443?
encryption=none&
flow=xtls-rprx-vision...

# CORRECT (single line)
vless://uuid@ip:443?encryption=none&flow=xtls-rprx-vision...
```

2. **Missing required parameters**
Required in URI:
- `flow=xtls-rprx-vision`
- `security=reality`
- `pbk=PUBLIC_KEY`
- `sid=SHORT_ID`

**Generate correct URI:**
```bash
# Use sbx-lite export
sbx export uri reality

# Or construct manually (see examples/reality-only/share-uri.txt)
```

---

## Diagnostic Commands

**Configuration:**
```bash
# Validate JSON syntax
jq empty /etc/sing-box/config.json

# Validate with sing-box
sing-box check -c /etc/sing-box/config.json

# Check Reality structure
jq '.inbounds[0].tls.reality' /etc/sing-box/config.json
```

**Service:**
```bash
# Status
systemctl status sing-box

# Logs (last 50 lines)
journalctl -u sing-box -n 50 --no-pager

# Logs (follow in real-time)
journalctl -u sing-box -f

# Restart
systemctl restart sing-box
```

**Network:**
```bash
# Check port listening
ss -lntp | grep :443

# Test connectivity
telnet YOUR_IP 443

# Check firewall
ufw status  # Ubuntu
firewall-cmd --list-all  # CentOS
```

**Client Testing:**
```bash
# Test SOCKS5 proxy
curl --proxy socks5://127.0.0.1:10808 https://www.google.com

# Test with specific DNS
curl --proxy socks5://127.0.0.1:10808 --dns-servers 1.1.1.1 https://www.google.com
```

---

## Still Having Issues?

1. **Enable debug logging:**
```json
{
  "log": {
    "level": "debug",  // Changed from "warn"
    "timestamp": true
  }
}
```

2. **Check official documentation:**
- [sing-box VLESS](https://sing-box.sagernet.org/configuration/inbound/vless/)
- [sing-box Reality](https://sing-box.sagernet.org/configuration/shared/tls/)

3. **Review compliance documentation:**
- [Reality Compliance Review](../../docs/REALITY_COMPLIANCE_REVIEW.md)
- [sing-box vs Xray](../../docs/SING_BOX_VS_XRAY.md)

4. **Test with minimal configuration:**
Use `examples/reality-only/server-config.json` as baseline.

5. **Verify sing-box version:**
```bash
sing-box version
# Should be 1.8.0+ (1.12.0+ recommended)
```

---

## Quick Checklist

Before asking for help, verify:

- [ ] Configuration validates: `sing-box check -c config.json`
- [ ] sing-box version is 1.8.0+ (1.12.0+ recommended)
- [ ] Short ID is exactly 8 hex characters
- [ ] Reality is nested under `tls.reality`
- [ ] Short ID is in array format: `["a1b2c3d4"]`
- [ ] Flow field is in users array
- [ ] TLS is enabled when using Reality
- [ ] Port is listening: `ss -lntp | grep :PORT`
- [ ] Firewall allows the port
- [ ] Client uses matching UUID, public key, short ID
- [ ] v2rayN users have switched to sing-box core
- [ ] No line breaks in share URIs

If all checked and still failing, include in your report:
- sing-box version (`sing-box version`)
- Configuration (with sensitive data removed)
- Full error message from logs
- Client type and version
