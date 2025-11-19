# Reality Protocol Best Practices

**Version:** 1.0.0
**Last Updated:** 2025-11-17
**Applies to:** sing-box 1.12.0+

This guide documents production-grade best practices for deploying and maintaining VLESS + REALITY + Vision protocol with sing-box.

## Table of Contents

- [Security Best Practices](#security-best-practices)
- [Performance Optimization](#performance-optimization)
- [Deployment Patterns](#deployment-patterns)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Client Configuration](#client-configuration)

---

## Security Best Practices

### 1. Key Generation and Storage

#### Generate Cryptographically Secure Keys

**Always use official tools:**
```bash
# Reality keypair
sing-box generate reality-keypair

# UUID
sing-box generate uuid

# Short ID (8 hex characters)
openssl rand -hex 4
```

**Never:**
- ❌ Reuse keys across multiple servers
- ❌ Use predictable UUIDs (like all zeros)
- ❌ Generate short IDs manually
- ❌ Share private keys with anyone

**Best Practice:**
```bash
# Generate unique credentials for each deployment
UUID=$(sing-box generate uuid)
KEYPAIR=$(sing-box generate reality-keypair)
SHORT_ID=$(openssl rand -hex 4)

# Store securely with restricted permissions
echo "$KEYPAIR" > /root/reality-keys.txt
chmod 600 /root/reality-keys.txt
```

---

### 2. Short ID Randomness

**Importance:** Short IDs provide connection authentication and prevent probing attacks.

**Good Short IDs** (high entropy):
```bash
openssl rand -hex 4
# Examples: a7f3c2d1, 9b4e8f2a, 3c7d1e5b
```

**Bad Short IDs** (predictable):
```
00000000  # All zeros
12345678  # Sequential
aaaaaaaa  # Repeating pattern
```

**Multiple Short IDs (Advanced):**
```json
{
  "reality": {
    "short_id": [
      "a7f3c2d1",  // Primary
      "9b4e8f2a",  // Backup
      "3c7d1e5b"   // Legacy (for migration)
    ]
  }
}
```

**Use case:** Gradual key rotation without downtime.

---

### 3. SNI Selection Criteria

**Choose SNI (Server Name Indication) wisely:**

**Good SNI Choices:**
- ✅ High-traffic websites (microsoft.com, apple.com, amazon.com)
- ✅ CDN-backed sites (cloudflare.com, fastly.net)
- ✅ Websites with TLS 1.3 support
- ✅ Sites that match your geographic region

**Poor SNI Choices:**
- ❌ Government websites
- ❌ Censored websites
- ❌ Low-traffic sites
- ❌ Sites with unusual TLS configurations

**Recommended SNIs for Reality:**
```json
// General purpose
"server_name": "www.microsoft.com"

// For specific regions
"server_name": "www.samsung.com"       // Asia
"server_name": "www.amazon.com"        // Americas
"server_name": "www.bmw.com"           // Europe
```

**Verify SNI compatibility:**
```bash
# Test TLS handshake
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com

# Should show TLS 1.3 and successful handshake
```

---

### 4. Certificate Management

**Reality Advantage:** No certificates required for basic setup!

**When you DO need certificates:**
- Using WebSocket TLS fallback
- Domain-based deployments
- Enterprise environments requiring TLS inspection bypass

**Certificate Best Practices:**
```bash
# Use Let's Encrypt with automatic renewal
# sbx-lite does this automatically with Caddy

# Manual certificate management
certbot certonly --standalone -d yourdomain.com

# Set proper permissions
chmod 600 /etc/letsencrypt/live/yourdomain.com/privkey.pem
chmod 644 /etc/letsencrypt/live/yourdomain.com/fullchain.pem
```

**Certificate Rotation:**
- Certificates expire every 90 days (Let's Encrypt)
- Set up automatic renewal (sbx-lite does this)
- Test renewal process before expiration

**Monitor expiry:**
```bash
# Check certificate expiration
openssl x509 -in /path/to/cert.pem -noout -dates

# Should show:
# notBefore=...
# notAfter=...
```

---

### 5. Access Control

**Limit access to configuration files:**
```bash
# Secure permissions
chmod 600 /etc/sing-box/config.json
chown root:root /etc/sing-box/config.json

# Secure backup directory
chmod 700 /var/backups/sbx/
chown root:root /var/backups/sbx/
```

**Multi-User Management:**
```json
{
  "users": [
    {"uuid": "user1-uuid", "flow": "xtls-rprx-vision"},
    {"uuid": "user2-uuid", "flow": "xtls-rprx-vision"},
    {"uuid": "user3-uuid", "flow": "xtls-rprx-vision"}
  ]
}
```

**Best practices:**
- One UUID per user/device
- Document who has which UUID
- Rotate UUIDs periodically
- Remove unused UUIDs immediately

---

## Performance Optimization

### 1. TCP Fast Open Configuration

**Enable for reduced latency (~5-10% improvement):**

```json
{
  "outbounds": [{
    "type": "direct",
    "tcp_fast_open": true  // Enable TFO
  }]
}
```

**System-level TFO:**
```bash
# Enable TCP Fast Open on Linux
echo 3 | sudo tee /proc/sys/net/ipv4/tcp_fastopen

# Make permanent
echo "net.ipv4.tcp_fastopen = 3" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Verify:**
```bash
cat /proc/sys/net/ipv4/tcp_fastopen
# Should show: 3
```

---

### 2. Multiplex Settings

**For high-latency connections:**

```json
{
  "inbounds": [{
    "multiplex": {
      "enabled": true,
      "protocol": "smux",
      "max_connections": 4,
      "min_streams": 4,
      "max_streams": 0
    }
  }]
}
```

**When to use:**
- High-latency networks (>100ms)
- Unreliable connections
- Mobile networks

**When NOT to use:**
- Low-latency networks (<50ms)
- Reality-only mode (Vision handles this)
- Maximum performance needed

---

### 3. DNS Caching

**Reduce DNS lookup overhead:**

```json
{
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-local",
        "detour": "direct"
      }
    ],
    "strategy": "ipv4_only",
    "disable_cache": false,  // Enable caching
    "disable_expire": false
  }
}
```

**External DNS for better performance:**
```json
{
  "dns": {
    "servers": [
      {
        "address": "1.1.1.1",
        "address_resolver": "dns-local"
      },
      {
        "address": "8.8.8.8",
        "address_resolver": "dns-local"
      }
    ]
  }
}
```

---

### 4. Connection Pooling

**Reuse connections for better performance:**

```json
{
  "outbounds": [{
    "type": "direct",
    "tcp_fast_open": true,
    "tcp_multi_path": false,
    "udp_fragment": true
  }]
}
```

**System-level optimizations:**
```bash
# Increase connection limits
echo "net.core.somaxconn = 4096" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 4096" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog = 4096" >> /etc/sysctl.conf

# Apply
sudo sysctl -p
```

---

## Deployment Patterns

### 1. Single-Protocol (Reality-Only)

**Use case:** Simple deployment, maximum compatibility

**Advantages:**
- No domain required
- No certificate management
- Lowest maintenance
- Best performance with Vision

**Configuration:**
```json
{
  "inbounds": [{
    "type": "vless",
    "tag": "in-reality",
    "listen": "::",
    "listen_port": 443,
    "users": [{"uuid": "...", "flow": "xtls-rprx-vision"}],
    "tls": {
      "enabled": true,
      "reality": { "enabled": true, ... }
    }
  }]
}
```

**Deployment:**
```bash
# Using sbx-lite
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install.sh)
```

---

### 2. Multi-Protocol (Reality + WS + Hysteria2)

**Use case:** Maximum fallback options, enterprise environments

**Advantages:**
- Multiple protocols for different scenarios
- WebSocket works through restrictive firewalls
- Hysteria2 for lossy networks
- Reality for maximum performance

**Configuration:**
```json
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen_port": 443,
      "tls": {"reality": {...}}
    },
    {
      "type": "vless",
      "tag": "in-ws",
      "listen_port": 8444,
      "transport": {"type": "ws"},
      "tls": {"enabled": true}
    },
    {
      "type": "hysteria2",
      "tag": "in-hy2",
      "listen_port": 8443
    }
  ]
}
```

**Deployment:**
```bash
# Using sbx-lite with domain
DOMAIN=your.domain.com bash <(curl -fsSL ...)
```

---

### 3. High-Availability Setup

**Use case:** Production environments, critical services

**Architecture:**
```
       ┌──────────────┐
       │  DNS Round   │
       │    Robin     │
       └──────┬───────┘
              │
      ┌───────┴────────┐
      ├────────────────┤
┌─────▼─────┐    ┌────▼──────┐
│  Server 1 │    │ Server 2  │
│  Reality  │    │  Reality  │
└───────────┘    └───────────┘
```

**Key points:**
- Use different short IDs per server
- Share same UUID across servers (for same user)
- Monitor both servers independently
- Use health checks

**Client configuration:**
```json
{
  "outbounds": [{
    "type": "vless",
    "tag": "proxy",
    "server": "server1.example.com",  // Primary
    "server_port": 443
  }, {
    "type": "vless",
    "tag": "backup",
    "server": "server2.example.com",  // Backup
    "server_port": 443
  }]
}
```

---

### 4. Load Balancing

**Use case:** High-traffic scenarios

**HAProxy configuration:**
```
frontend reality_frontend
    bind *:443
    mode tcp
    default_backend reality_backend

backend reality_backend
    mode tcp
    balance roundrobin
    server reality1 10.0.0.1:443 check
    server reality2 10.0.0.2:443 check
    server reality3 10.0.0.3:443 check
```

**sing-box routing (client-side):**
```json
{
  "route": {
    "rules": [{
      "outbound_group": ["server1", "server2", "server3"],
      "type": "urltest",
      "url": "http://www.gstatic.com/generate_204",
      "interval": "300s"
    }]
  }
}
```

---

## Monitoring and Maintenance

### 1. Log Analysis

**Configure appropriate log level:**
```json
{
  "log": {
    "level": "warn",      // Production: warn or info
    "timestamp": true,
    "output": "/var/log/sing-box/sing-box.log"
  }
}
```

**Log rotation:**
```bash
# /etc/logrotate.d/sing-box
/var/log/sing-box/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    postrotate
        systemctl reload sing-box
    endscript
}
```

**Monitor logs:**
```bash
# Real-time monitoring
journalctl -u sing-box -f

# Search for errors
journalctl -u sing-box | grep -i error

# Connection statistics
journalctl -u sing-box | grep "accepted connection"
```

---

### 2. Performance Metrics

**Key metrics to monitor:**

1. **Connection Count**
```bash
# Active connections
ss -tn | grep :443 | wc -l
```

2. **Bandwidth Usage**
```bash
# Install vnstat
sudo apt install vnstat

# View statistics
vnstat -l  # Live
vnstat -d  # Daily
vnstat -m  # Monthly
```

3. **CPU and Memory**
```bash
# sing-box resource usage
ps aux | grep sing-box

# Detailed monitoring
top -p $(pgrep sing-box)
```

4. **Disk I/O**
```bash
# Check if logging is causing I/O issues
iotop -p $(pgrep sing-box)
```

---

### 3. Update Procedures

**Stay current with sing-box releases:**

**Check for updates:**
```bash
# Current version
sing-box version

# Latest version
curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name'
```

**Update process:**
```bash
# Using sbx-lite
bash <(curl -fsSL ...) # Choose option 1) Upgrade binary

# Manual update
sudo systemctl stop sing-box
# Download new binary
wget https://github.com/SagerNet/sing-box/releases/download/vX.Y.Z/...
sudo mv sing-box /usr/local/bin/
sudo systemctl start sing-box
```

**Post-update validation:**
```bash
# Verify version
sing-box version

# Check configuration compatibility
sing-box check -c /etc/sing-box/config.json

# Monitor logs
journalctl -u sing-box -f
```

---

### 4. Backup Strategies

**Regular backups:**
```bash
# Using sbx-lite (automated)
sbx backup create --encrypt

# Manual backup
tar -czf /root/sbx-backup-$(date +%Y%m%d).tar.gz \
  /etc/sing-box/ \
  /var/backups/sbx/ \
  /root/reality-keys.txt
```

**Backup schedule:**
- **Daily:** Automated encrypted backups
- **Weekly:** Off-site backup copy
- **Pre-update:** Manual backup before changes

**Test restores regularly:**
```bash
# Verify backup integrity
tar -tzf backup-file.tar.gz

# Test restore (on test server)
sbx backup restore backup-file.tar.gz.enc
```

---

## Client Configuration

### 1. Client Selection Guide

**Recommended clients by platform:**

| Platform | Client | sing-box Support | Notes |
|----------|--------|------------------|-------|
| Windows | NekoRay | ✅ Native | Best choice |
| Windows | v2rayN | ✅ Switch core | Requires core switch |
| macOS | NekoBox | ✅ Native | Recommended |
| Linux | NekoRay | ✅ Native | Full support |
| Android | v2rayNG | ✅ Switch core | Requires core switch |
| Android | NekoBox | ✅ Native | Recommended |
| iOS | Shadowrocket | ✅ Native | Commercial |
| iOS | sing-box | ✅ Official | Free, open source |

**Key consideration:** Native sing-box support > Core switching required

---

### 2. Configuration Import Methods

**Method 1: Share URI** (Easiest)
```bash
# Generate URI
sbx export uri reality

# Import in client
# - v2rayN: Import → From Clipboard
# - NekoRay: Add → Import from Clipboard
```

**Method 2: JSON Configuration**
```bash
# Export client config
sbx export v2rayn reality > reality-client.json

# Import in client
# - v2rayN: Import → Custom config
# - NekoRay: Import → From file
```

**Method 3: QR Code**
```bash
# Generate QR code
sbx qr

# Scan with mobile client
```

**Method 4: Subscription** (Multi-user)
```bash
# Generate subscription link
sbx export subscription

# Add to client as subscription URL
```

---

### 3. Troubleshooting Client Issues

**v2rayN connection failed:**
1. Settings → Core Type → VLESS → **sing-box**
2. Restart v2rayN
3. Reconnect

**Clash Meta parse error:**
- Ensure using Clash Meta (not regular Clash)
- Check YAML syntax
- Verify all required fields present

**NekoRay import failed:**
- Remove line breaks from URI
- Verify all parameters present
- Check for typos in UUID/keys

---

### 4. Performance Tuning

**Client-side optimizations:**

**1. Enable multiplexing (high latency):**
```json
{
  "multiplex": {
    "enabled": true,
    "protocol": "smux"
  }
}
```

**2. Adjust buffer sizes:**
```json
{
  "inbound": {
    "sniff_override_destination": true
  }
}
```

**3. DNS optimization:**
```json
{
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"],
    "disable_cache": false
  }
}
```

---

## Production Checklist

Before going to production:

**Security:**
- [ ] Unique UUID per user
- [ ] Strong short ID (random 8 hex chars)
- [ ] Private key never shared
- [ ] Configuration file permissions: 600
- [ ] Firewall configured
- [ ] Regular backups enabled

**Performance:**
- [ ] TCP Fast Open enabled
- [ ] DNS caching enabled
- [ ] Log level appropriate (warn/info)
- [ ] System limits increased (if needed)

**Monitoring:**
- [ ] Log rotation configured
- [ ] Monitoring alerts set up
- [ ] Backup verification scheduled
- [ ] Update procedure documented

**Testing:**
- [ ] Configuration validated
- [ ] Service starts successfully
- [ ] Client can connect
- [ ] Performance acceptable
- [ ] Failover tested (if HA)

---

## References

- **sing-box Official Docs**: https://sing-box.sagernet.org/
- **Reality Protocol Spec**: https://github.com/XTLS/REALITY
- **sbx-lite Compliance Review**: [REALITY_COMPLIANCE_REVIEW.md](./REALITY_COMPLIANCE_REVIEW.md)
- **Troubleshooting Guide**: [../examples/troubleshooting/common-errors.md](../examples/troubleshooting/common-errors.md)

---

**Document Version:** 1.0.0
**Maintained by:** sbx-lite project
**License:** MIT
