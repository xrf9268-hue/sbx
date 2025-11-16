# sing-box vs Xray: Reality Protocol Differences

**Last Updated:** 2025-11-16
**Target Audience:** Users migrating from Xray to sing-box

---

## Executive Summary

Both sing-box and Xray support the Reality protocol, but they have important implementation differences that affect configuration, clients, and compatibility. This guide helps you understand these differences and migrate smoothly.

**Key Takeaway:** sing-box uses a **native configuration format** that differs from Xray's V2Ray-compatible format, and has **stricter constraints** (e.g., 8-char short IDs vs 16-char).

---

## Table of Contents

1. [Quick Comparison](#quick-comparison)
2. [Configuration Format Differences](#configuration-format-differences)
3. [Reality Implementation Differences](#reality-implementation-differences)
4. [Client Compatibility](#client-compatibility)
5. [Migration Guide](#migration-guide)
6. [Troubleshooting](#troubleshooting)

---

## Quick Comparison

| Aspect | sing-box | Xray | Winner |
|--------|----------|------|--------|
| **Configuration Format** | Native JSON (sing-box) | V2Ray JSON | - |
| **Reality Short ID** | 0-8 hex chars | 0-16 hex chars | Xray (more flexible) |
| **Keypair Generation** | `sing-box generate reality-keypair` | `xray x25519` | - |
| **Config Structure** | `tls.reality` | `streamSettings.realitySettings` | - |
| **Performance** | Go native | Go native | Tie |
| **Client Ecosystem** | Growing | Mature | Xray |
| **Modern Features** | 1.12.0+ (Route actions, new DNS) | Stable | sing-box |
| **Update Frequency** | Active | Active | Tie |
| **Production Stability** | Stable (1.8.0+) | Very stable | Tie |

**Verdict:** Choose based on your needs:
- **sing-box**: Modern features, active development, official Reality support
- **Xray**: Mature ecosystem, wider client compatibility, more flexible constraints

---

## Configuration Format Differences

### Server-Side Configuration

#### sing-box Format (Native)

```json
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-local"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "private_key": "PRIV_KEY_HERE",
          "short_id": ["a1b2c3d4"],
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "max_time_difference": "1m"
        },
        "alpn": ["h2", "http/1.1"]
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
```

**Key Characteristics:**
- ✅ Top-level structure: `log`, `dns`, `inbounds`, `outbounds`
- ✅ Field names: `type`, `listen_port`, `users`
- ✅ Reality nested under: `tls.reality`
- ✅ Short ID: **Array format** `["a1b2c3d4"]`
- ✅ DNS: Modern 1.12.0+ format with `type: "local"`

#### Xray Format (V2Ray-compatible)

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": ["www.microsoft.com"],
          "privateKey": "PRIV_KEY_HERE",
          "shortIds": ["a1b2c3d4abcdef01"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
```

**Key Characteristics:**
- ✅ Top-level structure: `log`, `inbounds`, `outbounds`
- ✅ Field names: `protocol`, `port`, `settings.clients`
- ✅ Reality nested under: `streamSettings.realitySettings`
- ✅ Short ID: **Array format** `["a1b2c3d4abcdef01"]` (up to 16 hex chars)
- ✅ Legacy field names: `loglevel`, `decryption`, `freedom`

---

## Reality Implementation Differences

### 1. Short ID Length Constraint

**Critical Difference!**

| Implementation | Min Length | Max Length | Example | Generation |
|----------------|------------|------------|---------|------------|
| **sing-box** | 0 chars | **8 chars** | `a1b2c3d4` | `openssl rand -hex 4` |
| **Xray** | 0 chars | **16 chars** | `a1b2c3d4abcdef01` | `openssl rand -hex 8` |

**Impact:**
- ❌ Xray 16-char short IDs are **INVALID** for sing-box
- ✅ sing-box 8-char short IDs are **VALID** for Xray (subset)
- ⚠️ Migration: Truncate Xray short IDs to 8 chars or regenerate

**Why the Difference?**
- sing-box enforces stricter validation for Reality spec compliance
- Xray allows longer IDs for flexibility

**Migration Example:**
```bash
# Xray short ID (16 chars)
OLD_SID="a1b2c3d4abcdef01"

# Truncate to 8 chars for sing-box
NEW_SID="${OLD_SID:0:8}"  # Result: "a1b2c3d4"

# Or regenerate (recommended)
NEW_SID=$(openssl rand -hex 4)  # Fresh 8-char ID
```

### 2. Keypair Generation Commands

| Tool | Command | Output Format |
|------|---------|---------------|
| **sing-box** | `sing-box generate reality-keypair` | `PrivateKey: xxx\nPublicKey: yyy` |
| **Xray** | `xray x25519` | `Private key: xxx\nPublic key: yyy` |

**Both tools generate compatible X25519 keypairs**, so keys are **interchangeable** between platforms.

**Example:**
```bash
# sing-box
$ sing-box generate reality-keypair
PrivateKey: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc
PublicKey: jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0

# Xray
$ xray x25519
Private key: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc
Public key: jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0
```

### 3. Configuration Structure Mapping

#### Server-Side Fields

| Concept | sing-box Path | Xray Path |
|---------|---------------|-----------|
| Protocol type | `inbounds[].type` | `inbounds[].protocol` |
| Listen address | `inbounds[].listen` | `inbounds[].listen` |
| Listen port | `inbounds[].listen_port` | `inbounds[].port` |
| Users/Clients | `inbounds[].users[]` | `inbounds[].settings.clients[]` |
| User UUID | `users[].uuid` | `clients[].id` |
| Flow field | `users[].flow` | `clients[].flow` |
| TLS/Reality | `inbounds[].tls.reality` | `inbounds[].streamSettings.realitySettings` |
| Private key | `tls.reality.private_key` | `realitySettings.privateKey` |
| Short IDs | `tls.reality.short_id[]` | `realitySettings.shortIds[]` |
| Handshake server | `tls.reality.handshake.server` | `realitySettings.dest` (combined with port) |
| Handshake port | `tls.reality.handshake.server_port` | `realitySettings.dest` (`:443` suffix) |
| Server names (SNI) | `tls.server_name` | `realitySettings.serverNames[]` |

#### Client-Side Fields

| Concept | sing-box (v2rayN with sing-box core) | Xray (v2rayN with Xray core) |
|---------|--------------------------------------|------------------------------|
| Public key | `realitySettings.publicKey` | `realitySettings.publicKey` |
| Short ID | `realitySettings.shortId` | `realitySettings.shortId` |
| Server name | `realitySettings.serverName` | `realitySettings.serverName` |
| Fingerprint | `realitySettings.fingerprint` | `realitySettings.fingerprint` |

**Note:** Client configurations are similar, but **core selection matters**!

### 4. Flow Field Usage

| Flow Value | sing-box | Xray | Purpose |
|------------|----------|------|---------|
| `""` (empty) | ✅ Supported | ✅ Supported | Standard VLESS (no XTLS) |
| `"xtls-rprx-vision"` | ✅ Supported | ✅ Supported | Reality with Vision protocol |

**Both implementations support Vision identically.**

### 5. DNS Configuration

**sing-box 1.12.0+ (Modern)**
```json
{
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-local"
      }
    ],
    "strategy": "ipv4_only"
  }
}
```

**Xray (Traditional)**
```json
{
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"]
  }
}
```

**Impact:** sing-box has more advanced DNS routing and strategy options.

---

## Client Compatibility

### Client Matrix

| Client | sing-box Core | Xray Core | Notes |
|--------|---------------|-----------|-------|
| **v2rayN** (Windows) | ✅ Supported | ✅ Supported | **Must manually switch core!** |
| **v2rayNG** (Android) | ✅ Supported | ✅ Supported | **Must manually switch core!** |
| **NekoRay/NekoBox** | ✅ Native | ✅ Supported | Detects automatically |
| **Clash Meta** | ✅ Supported | ✅ Supported | Auto-detects based on config |
| **sing-box official** | ✅ Native | ❌ N/A | iOS, Android, CLI |
| **Shadowrocket** (iOS) | ✅ Supported | ⚠️ Limited | Prefers sing-box format |
| **Surge** (iOS/Mac) | ❌ Limited | ❌ Limited | Proprietary format |

### How to Switch Core in v2rayN

**CRITICAL:** v2rayN defaults to Xray core. For sing-box servers, you **MUST** switch the core.

**Steps:**
1. Open v2rayN
2. Go to **Settings** → **Core Settings** (设置 → 核心设置)
3. Find **VLESS** protocol section
4. Change core from `Xray-core` to `sing-box`
5. Restart v2rayN
6. Re-import your Reality configuration

**Screenshot Location:** Settings → Core → VLESS → sing-box

**Common Mistake:**
```
Error: "connection failed" or "handshake timeout"
Cause: Using Xray core with sing-box server configuration
Fix: Switch core to sing-box as described above
```

---

## Migration Guide

### Scenario 1: Xray Server → sing-box Server

**Goal:** Migrate your Xray Reality server to sing-box

**Steps:**

1. **Export Current Configuration**
   ```bash
   # Save your current Xray config
   cp /usr/local/etc/xray/config.json /backup/xray-config.json

   # Note down your keys and UUIDs
   cat /usr/local/etc/xray/config.json | jq '.inbounds[0].streamSettings.realitySettings'
   ```

2. **Extract Key Parameters**
   ```bash
   # From Xray config.json
   UUID="..." # From settings.clients[].id
   PRIVATE_KEY="..." # From realitySettings.privateKey
   PUBLIC_KEY="..." # From realitySettings.publicKey
   SHORT_ID="..." # From realitySettings.shortIds[0]
   ```

3. **Validate/Adjust Short ID**
   ```bash
   # Check length
   echo -n "$SHORT_ID" | wc -c

   # If > 8 chars, truncate or regenerate
   if [ ${#SHORT_ID} -gt 8 ]; then
     echo "Short ID too long for sing-box!"
     echo "Old: $SHORT_ID"
     SHORT_ID="${SHORT_ID:0:8}"  # Truncate to 8 chars
     echo "New: $SHORT_ID"
   fi
   ```

4. **Install sbx-lite**
   ```bash
   # This will prompt for configuration
   bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
   ```

5. **Update Client-Info with Your Keys**
   ```bash
   # Edit the generated config to use your existing keys
   sudo nano /etc/sing-box/client-info.txt

   # Update these values:
   UUID=your-existing-uuid
   PUBLIC_KEY=your-existing-public-key
   SHORT_ID=your-truncated-short-id
   ```

6. **Regenerate Configuration**
   ```bash
   # This preserves your keys while using sing-box format
   sudo sbx reconfigure
   ```

7. **Update Clients**
   - Switch v2rayN core to sing-box
   - Update short_id if you truncated it
   - Re-import configuration

**Verification:**
```bash
# Check sing-box config structure
sudo jq '.inbounds[0].tls.reality' /etc/sing-box/config.json

# Verify short_id is 8 chars or less
sudo jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/sing-box/config.json | wc -c
```

### Scenario 2: Keep Xray Server, Update Clients Only

**Goal:** Server stays on Xray, but use sing-box-aware clients

**Steps:**

1. **No server changes needed** - Xray server stays as-is

2. **For v2rayN users:**
   - Option A: Switch core to sing-box (works with both)
   - Option B: Keep Xray core (no changes needed)

3. **Export Xray config in sing-box format** (if needed):
   ```bash
   # Manually create sing-box client config
   cat > client-reality-singbox.json <<'EOF'
   {
     "log": { "loglevel": "warning" },
     "inbounds": [
       {
         "port": 10808,
         "protocol": "socks",
         "settings": { "udp": true }
       }
     ],
     "outbounds": [
       {
         "protocol": "vless",
         "settings": {
           "vnext": [
             {
               "address": "YOUR_SERVER_IP",
               "port": 443,
               "users": [
                 {
                   "id": "YOUR_UUID",
                   "encryption": "none",
                   "flow": "xtls-rprx-vision"
                 }
               ]
             }
           ]
         },
         "streamSettings": {
           "network": "tcp",
           "security": "reality",
           "realitySettings": {
             "serverName": "www.microsoft.com",
             "publicKey": "YOUR_PUBLIC_KEY",
             "shortId": "YOUR_SHORT_ID",
             "fingerprint": "chrome"
           }
         }
       }
     ]
   }
   EOF
   ```

### Scenario 3: Clean Installation (Recommended)

**Goal:** Start fresh with sing-box

**Steps:**

1. **Backup Xray (if migrating)**
   ```bash
   sudo systemctl stop xray
   sudo cp -r /usr/local/etc/xray /backup/xray-backup
   ```

2. **Install sbx-lite**
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)
   ```

3. **Get connection info**
   ```bash
   sbx info  # Shows all URIs and configs
   ```

4. **Import to clients** (v2rayN, Clash, etc.)
   - **Remember to switch v2rayN core to sing-box!**

---

## Troubleshooting

### Issue: "connection failed" with v2rayN

**Symptoms:**
- v2rayN shows "connection failed"
- Logs show "handshake timeout" or "unknown protocol"

**Root Cause:**
Using Xray core with sing-box server configuration (or vice versa)

**Solution:**
```
v2rayN → Settings → Core Settings → VLESS → Change to sing-box
Restart v2rayN
```

### Issue: Short ID validation error

**Symptoms:**
```
Short ID must be 1-8 hexadecimal characters, got: a1b2c3d4abcdef01
```

**Root Cause:**
Xray short ID (16 chars) used with sing-box (max 8 chars)

**Solution:**
```bash
# Truncate to 8 chars
SHORT_ID="a1b2c3d4abcdef01"
NEW_SID="${SHORT_ID:0:8}"  # = "a1b2c3d4"

# Or regenerate
NEW_SID=$(openssl rand -hex 4)

# Update server config
sudo nano /etc/sing-box/config.json
# Update: "short_id": ["NEW_SID_HERE"]

# Update client config with same NEW_SID
```

### Issue: Keypair mismatch between server and client

**Symptoms:**
- Client shows "handshake failed"
- Server logs show "Reality handshake error"

**Root Cause:**
Public key on client doesn't match private key on server

**Solution:**
```bash
# Regenerate matching keypair
sing-box generate reality-keypair

# Output:
# PrivateKey: xxx (put on SERVER)
# PublicKey: yyy (put on CLIENT)

# Verify they match
# Server should have PrivateKey in config.json
# Client should have PublicKey (the matching counterpart)
```

### Issue: Configuration format confusion

**Symptoms:**
- Config validation fails
- Fields not recognized

**Root Cause:**
Mixing Xray field names in sing-box config (or vice versa)

**Solution:**
Use the correct format for your platform:

**sing-box:**
```json
{
  "inbounds": [{
    "type": "vless",
    "listen_port": 443,
    "users": [{"uuid": "...", "flow": "xtls-rprx-vision"}],
    "tls": {"reality": {...}}
  }]
}
```

**Xray:**
```json
{
  "inbounds": [{
    "protocol": "vless",
    "port": 443,
    "settings": {"clients": [{"id": "...", "flow": "xtls-rprx-vision"}]},
    "streamSettings": {"realitySettings": {...}}
  }]
}
```

### Issue: DNS resolution problems

**Symptoms:**
- Clients can't resolve domains
- Slow connection establishment

**Root Cause:**
DNS misconfiguration or missing strategy

**sing-box Solution:**
```json
{
  "dns": {
    "servers": [{"type": "local", "tag": "dns-local"}],
    "strategy": "ipv4_only"  // For IPv4-only networks
  }
}
```

**Xray Solution:**
```json
{
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"]
  }
}
```

---

## Field Name Mapping Cheat Sheet

Quick reference for converting between formats:

### Server Configuration

| Concept | sing-box | Xray |
|---------|----------|------|
| Inbound type | `"type": "vless"` | `"protocol": "vless"` |
| Port | `"listen_port": 443` | `"port": 443` |
| Users | `"users": [...]` | `"settings": {"clients": [...]}` |
| UUID | `"uuid": "..."` | `"id": "..."` |
| Flow | `"flow": "xtls-rprx-vision"` | `"flow": "xtls-rprx-vision"` |
| Reality section | `"tls": {"reality": {...}}` | `"streamSettings": {"realitySettings": {...}}` |
| Private key | `"private_key": "..."` | `"privateKey": "..."` |
| Short IDs | `"short_id": ["..."]` | `"shortIds": ["..."]` |
| Handshake | `"handshake": {"server": "x", "server_port": 443}` | `"dest": "x:443"` |
| Outbound | `"type": "direct"` | `"protocol": "freedom"` |

### Client Configuration

| Concept | sing-box (v2rayN JSON) | Xray (v2rayN JSON) |
|---------|------------------------|---------------------|
| Same! | `"realitySettings": {"publicKey": "..."}` | `"realitySettings": {"publicKey": "..."}` |

**Note:** Client configs are nearly identical, but **core selection** is critical!

---

## Frequently Asked Questions

### Q: Can I use the same keypair for both sing-box and Xray?

**A:** Yes! Both use X25519 keypairs. Keys generated with `sing-box generate reality-keypair` work with Xray, and vice versa.

### Q: Will my Xray clients work with sing-box server?

**A:** Yes, **IF** you:
1. Switch v2rayN core to sing-box (if using v2rayN)
2. Use a short_id ≤ 8 characters
3. Update client config to use the correct public key

### Q: Can I run both sing-box and Xray on the same server?

**A:** Yes, on different ports:
```bash
# sing-box on port 443
# Xray on port 8443
```

Just ensure they use different ports and don't conflict.

### Q: Which one is faster?

**A:** Performance is nearly identical. Both use Go's native implementation. Choose based on features and ecosystem.

### Q: Should I migrate from Xray to sing-box?

**A:** Consider migrating if you:
- ✅ Want modern DNS routing features
- ✅ Prefer native sing-box configuration format
- ✅ Need latest protocol updates
- ✅ Value active development

Stay with Xray if you:
- ✅ Have a stable setup working well
- ✅ Prefer mature, battle-tested codebase
- ✅ Use Xray-specific features
- ✅ Have many clients already configured

---

## Additional Resources

### Official Documentation

- **sing-box**: https://sing-box.sagernet.org/
- **Xray**: https://xtls.github.io/

### Reality Protocol

- **Original Spec**: https://github.com/XTLS/Reality
- **sing-box Implementation**: https://sing-box.sagernet.org/configuration/shared/tls/#reality-fields
- **Xray Implementation**: https://xtls.github.io/config/transport/reality.html

### Tools

- **Keypair Generation**: `sing-box generate reality-keypair` or `xray x25519`
- **Config Validation**: `sing-box check -c config.json`
- **Online Converters**: (None available - manual conversion required)

---

## Conclusion

Both sing-box and Xray are excellent choices for Reality protocol deployment. The key differences are:

1. **Configuration format** - Native vs V2Ray-compatible
2. **Short ID length** - 8 chars (sing-box) vs 16 chars (Xray)
3. **Client compatibility** - sing-box requires core switching in v2rayN
4. **Modern features** - sing-box has newer DNS and routing options

**Migration is straightforward** if you follow the steps in this guide. The most common pitfall is forgetting to switch the core in v2rayN when using a sing-box server.

**When in doubt:**
- Use sing-box for new deployments (modern, actively developed)
- Use Xray for compatibility with existing infrastructure
- Both are production-ready and perform well

---

**Document Version:** 1.0
**Last Updated:** 2025-11-16
**Maintained by:** sbx-lite project
