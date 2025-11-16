# Reality Protocol Troubleshooting Guide

**Last Updated:** 2025-11-16
**Applies to:** sbx-lite with sing-box 1.8.0+

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Configuration Issues](#configuration-issues)
3. [Client Connection Problems](#client-connection-problems)
4. [Service Startup Issues](#service-startup-issues)
5. [Network and Firewall Issues](#network-and-firewall-issues)
6. [Performance Issues](#performance-issues)
7. [Advanced Debugging](#advanced-debugging)

---

## Quick Diagnostics

**Run these commands first to identify the problem category:**

```bash
# 1. Check service status
systemctl status sing-box

# 2. Validate configuration
/usr/local/bin/sing-box check -c /etc/sing-box/config.json

# 3. Check logs for errors
journalctl -u sing-box -n 50 --no-pager

# 4. Verify ports are listening
ss -lntp | grep -E ':(443|8443|8444)'

# 5. Check Reality configuration structure
jq '.inbounds[0].tls.reality' /etc/sing-box/config.json
```

**Quick Decision Tree:**

```
Service not running?
  → See [Service Startup Issues](#service-startup-issues)

Service running but can't connect?
  → See [Client Connection Problems](#client-connection-problems)

Configuration validation fails?
  → See [Configuration Issues](#configuration-issues)

Ports not listening?
  → See [Network and Firewall Issues](#network-and-firewall-issues)
```

---

## Configuration Issues

### Issue 1: Short ID Validation Error

**Symptoms:**
```
Error: Short ID must be 1-8 hexadecimal characters, got: a1b2c3d4abcdef01
Error: Generated invalid short ID: gggg1234
```

**Root Cause:**
- Short ID exceeds 8 characters (sing-box limitation)
- Contains invalid characters (only 0-9, a-f, A-F allowed)
- Generated with wrong command

**Solution:**

```bash
# CORRECT: Generate 8-character short ID
SHORT_ID=$(openssl rand -hex 4)
echo "Generated: $SHORT_ID"

# Validate format (should match)
if [[ "$SHORT_ID" =~ ^[0-9a-fA-F]{1,8}$ ]]; then
  echo "✓ Valid short ID"
else
  echo "✗ Invalid short ID"
fi
```

**Common Mistakes:**
```bash
# ✗ WRONG: Produces 16 characters (Xray format, invalid for sing-box)
openssl rand -hex 8  # DON'T USE THIS

# ✓ CORRECT: Produces 8 characters (sing-box format)
openssl rand -hex 4  # USE THIS
```

**Manual Fix:**
```bash
# If you have an invalid short ID in config.json
sudo nano /etc/sing-box/config.json

# Find the short_id line (should be inside tls.reality)
# Change from:
#   "short_id": ["a1b2c3d4abcdef01"]  # 16 chars, INVALID
# To:
#   "short_id": ["a1b2c3d4"]  # 8 chars, VALID

# Validate the fix
sudo sing-box check -c /etc/sing-box/config.json

# Restart service
sudo systemctl restart sing-box
```

---

### Issue 2: Reality Not Nested Under TLS

**Symptoms:**
```
Error: unknown field 'reality' in inbound configuration
Warning: TLS not enabled but Reality configuration present
```

**Root Cause:**
Reality configuration is at the wrong level in JSON structure

**Incorrect Structure:**
```json
{
  "inbounds": [
    {
      "type": "vless",
      "reality": {  // ✗ WRONG: Top-level under inbound
        "enabled": true,
        "private_key": "..."
      }
    }
  ]
}
```

**Correct Structure:**
```json
{
  "inbounds": [
    {
      "type": "vless",
      "tls": {
        "enabled": true,
        "reality": {  // ✓ CORRECT: Nested under tls
          "enabled": true,
          "private_key": "..."
        }
      }
    }
  ]
}
```

**Fix:**
```bash
# Verify correct nesting
jq '.inbounds[0] | has("tls")' /etc/sing-box/config.json
# Output should be: true

jq '.inbounds[0].tls | has("reality")' /etc/sing-box/config.json
# Output should be: true

# If nested incorrectly, regenerate config:
sudo sbx reconfigure
```

---

### Issue 3: Short ID Wrong Format (String Instead of Array)

**Symptoms:**
```
Error: short_id must be an array
Type mismatch: expected array, got string
```

**Root Cause:**
Short ID stored as string instead of array in configuration

**Incorrect:**
```json
{
  "tls": {
    "reality": {
      "short_id": "a1b2c3d4"  // ✗ WRONG: String
    }
  }
}
```

**Correct:**
```json
{
  "tls": {
    "reality": {
      "short_id": ["a1b2c3d4"]  // ✓ CORRECT: Array
    }
  }
}
```

**Diagnostic:**
```bash
# Check if short_id is array
jq '.inbounds[0].tls.reality.short_id | type' /etc/sing-box/config.json
# Should output: "array" (not "string")

# Check array length
jq '.inbounds[0].tls.reality.short_id | length' /etc/sing-box/config.json
# Should output: 1 (or more)
```

**Fix:**
```bash
# Manual fix with jq
sudo jq '.inbounds[0].tls.reality.short_id = [.inbounds[0].tls.reality.short_id]' \
  /etc/sing-box/config.json > /tmp/config.json.fixed

sudo mv /tmp/config.json.fixed /etc/sing-box/config.json

# Validate and restart
sudo sing-box check -c /etc/sing-box/config.json
sudo systemctl restart sing-box
```

---

### Issue 4: Missing Required Fields

**Symptoms:**
```
Error: missing required field 'private_key' in reality configuration
Error: handshake server not specified
```

**Root Cause:**
Reality configuration incomplete

**Required Fields (Server-Side):**
```json
{
  "tls": {
    "enabled": true,  // Required
    "server_name": "www.microsoft.com",  // Required
    "reality": {
      "enabled": true,  // Required
      "private_key": "...",  // Required
      "short_id": ["..."],  // Required
      "handshake": {  // Required
        "server": "www.microsoft.com",  // Required
        "server_port": 443  // Required
      }
    }
  }
}
```

**Check for Missing Fields:**
```bash
# Verify all required fields present
CONFIG="/etc/sing-box/config.json"

jq -e '.inbounds[0].tls.enabled' $CONFIG || echo "✗ Missing: tls.enabled"
jq -e '.inbounds[0].tls.server_name' $CONFIG || echo "✗ Missing: tls.server_name"
jq -e '.inbounds[0].tls.reality.enabled' $CONFIG || echo "✗ Missing: reality.enabled"
jq -e '.inbounds[0].tls.reality.private_key' $CONFIG || echo "✗ Missing: reality.private_key"
jq -e '.inbounds[0].tls.reality.short_id' $CONFIG || echo "✗ Missing: reality.short_id"
jq -e '.inbounds[0].tls.reality.handshake.server' $CONFIG || echo "✗ Missing: handshake.server"
jq -e '.inbounds[0].tls.reality.handshake.server_port' $CONFIG || echo "✗ Missing: handshake.server_port"
```

**Fix:**
```bash
# Regenerate complete configuration
sudo sbx reconfigure
```

---

## Client Connection Problems

### Issue 5: "Network Unreachable" Error

**Symptoms:**
```
Client log: dial tcp [::1]:443: connect: network unreachable
Client log: no route to host
```

**Root Cause:**
IPv6 connection attempt on IPv4-only network

**Server-Side Diagnosis:**
```bash
# Check if server has IPv6 support
ip -6 addr show | grep "inet6" | grep -v "::1"

# If no output, server is IPv4-only

# Check DNS strategy
jq '.dns.strategy' /etc/sing-box/config.json
# Should be: "ipv4_only" for IPv4-only networks
```

**Solution:**

**For IPv4-Only Servers:**
```json
{
  "dns": {
    "servers": [{
      "type": "local",
      "tag": "dns-local"
    }],
    "strategy": "ipv4_only"  // Add this!
  }
}
```

**Apply Fix:**
```bash
# Update config with ipv4_only strategy
sudo jq '.dns.strategy = "ipv4_only"' /etc/sing-box/config.json > /tmp/config.json.fixed
sudo mv /tmp/config.json.fixed /etc/sing-box/config.json

# Validate and restart
sudo sing-box check -c /etc/sing-box/config.json
sudo systemctl restart sing-box

# Verify logs show no IPv6 errors
journalctl -u sing-box -f
```

---

### Issue 6: Handshake Timeout / Failed

**Symptoms:**
```
Client log: reality handshake timeout
Client log: tls: handshake failure
Server log: reality handshake failed
```

**Root Cause:**
- Public/private key mismatch
- Short ID mismatch between server and client
- Wrong SNI (server_name) on client

**Diagnosis:**

**1. Verify Keypair Match:**
```bash
# On server, get private key
SERVER_PRIV=$(jq -r '.inbounds[0].tls.reality.private_key' /etc/sing-box/config.json)

# Get public key from client-info
CLIENT_PUB=$(grep "PUBLIC_KEY=" /etc/sing-box/client-info.txt | cut -d'=' -f2)

echo "Server private key: $SERVER_PRIV"
echo "Client public key: $CLIENT_PUB"

# These should be a matching keypair!
# If unsure, regenerate:
sing-box generate reality-keypair
```

**2. Verify Short ID Match:**
```bash
# Server short ID
SERVER_SID=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/sing-box/config.json)

# Client short ID (from client-info.txt)
CLIENT_SID=$(grep "SHORT_ID=" /etc/sing-box/client-info.txt | cut -d'=' -f2)

echo "Server: $SERVER_SID"
echo "Client: $CLIENT_SID"

# These MUST match exactly!
```

**3. Verify SNI Match:**
```bash
# Server SNI
SERVER_SNI=$(jq -r '.inbounds[0].tls.server_name' /etc/sing-box/config.json)

# Client should use same SNI
echo "Client should use SNI: $SERVER_SNI"
```

**Solution:**
```bash
# If mismatch found, regenerate client info
sbx info

# Or export fresh client config
sbx export v2rayn reality > /tmp/client-reality.json

# Re-import on client device
```

---

### Issue 7: v2rayN "Connection Failed" (Xray Core Issue)

**Symptoms:**
```
v2rayN shows "Connection Failed"
Core type: Xray
Server type: sing-box
```

**Root Cause:**
v2rayN using Xray core with sing-box server

**Solution:**

**Switch v2rayN Core to sing-box:**

1. Open v2rayN
2. Go to **Settings** (设置)
3. Click **Core Settings** (核心设置)
4. Find **VLESS** protocol section
5. Change from `Xray-core` to `sing-box`
6. Click **OK**
7. **Restart v2rayN**
8. Re-import your Reality configuration

**Verification:**
```
After switching core and restarting:
- v2rayN should show "sing-box-core" in status bar
- Connection should succeed
- Traffic should flow
```

**Alternative:**
```bash
# If switching core doesn't work, try sing-box official client:
# Download from: https://github.com/SagerNet/sing-box/releases
# Install sing-box CLI client
# Use exported JSON config directly
```

---

## Service Startup Issues

### Issue 8: Service Fails to Start

**Symptoms:**
```bash
$ systemctl status sing-box
● sing-box.service - sing-box proxy server
   Active: failed (Result: exit-code)
   Process: 12345 exited with code=1
```

**Diagnosis:**
```bash
# Check detailed error message
journalctl -u sing-box -n 100 --no-pager | tail -20

# Common errors:
# - "configuration validation failed"
# - "port already in use"
# - "permission denied"
```

**Solution Path:**

**A. Configuration Validation Error:**
```bash
# Validate config manually
sudo sing-box check -c /etc/sing-box/config.json

# If validation fails, regenerate:
sudo sbx reconfigure
```

**B. Port Already in Use:**
```bash
# Find what's using the port
sudo ss -lntp | grep ':443'

# Example output:
# LISTEN 0 128 *:443 users:(("nginx",pid=1234))

# Solution 1: Stop conflicting service
sudo systemctl stop nginx

# Solution 2: Use alternative port
# Reinstall with fallback port (script auto-detects)
sudo sbx reconfigure
```

**C. Permission Denied:**
```bash
# Check file permissions
ls -la /etc/sing-box/config.json
# Should be: -rw------- (600) root root

# Fix permissions
sudo chmod 600 /etc/sing-box/config.json
sudo chown root:root /etc/sing-box/config.json

# Restart service
sudo systemctl restart sing-box
```

---

### Issue 9: Port Not Listening After Startup

**Symptoms:**
```bash
$ ss -lntp | grep ':443'
# (no output - port not listening)

$ systemctl status sing-box
Active: active (running)  # Service shows running!
```

**Root Cause:**
Service started but failed to bind port

**Diagnosis:**
```bash
# Check logs for bind errors
journalctl -u sing-box -n 50 | grep -i "bind\|listen\|port"

# Common messages:
# "bind: address already in use"
# "bind: permission denied"
# "listen tcp :443: bind: cannot assign requested address"
```

**Solutions:**

**A. Address Already in Use:**
```bash
# Find the conflicting process
sudo lsof -i :443

# Kill it or stop the service
sudo systemctl stop <conflicting-service>

# Restart sing-box
sudo systemctl restart sing-box
```

**B. IPv6 Bind Issue:**
```bash
# Check listen address in config
jq '.inbounds[0].listen' /etc/sing-box/config.json

# Should be: "::" (dual-stack) or "0.0.0.0" (IPv4-only)
# NOT: "::1" (localhost only) or "127.0.0.1" (localhost only)

# Fix if needed:
sudo jq '.inbounds[0].listen = "::"' /etc/sing-box/config.json > /tmp/config.json.fixed
sudo mv /tmp/config.json.fixed /etc/sing-box/config.json
sudo systemctl restart sing-box
```

---

## Network and Firewall Issues

### Issue 10: Firewall Blocking Connections

**Symptoms:**
```
Client: Connection timeout
Server: No connection attempts in logs
netstat: Port is listening
```

**Diagnosis:**
```bash
# Check if firewall is active
sudo systemctl status firewalld  # RHEL/CentOS/Fedora
sudo systemctl status ufw  # Debian/Ubuntu

# Check current rules
sudo iptables -L -n -v | grep 443
sudo firewall-cmd --list-all  # firewalld
sudo ufw status  # ufw
```

**Solutions:**

**For firewalld (RHEL/CentOS/Fedora):**
```bash
# Add Reality port
sudo firewall-cmd --permanent --add-port=443/tcp

# If using additional protocols
sudo firewall-cmd --permanent --add-port=8443/tcp  # Hysteria2
sudo firewall-cmd --permanent --add-port=8444/tcp  # WS-TLS

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

**For ufw (Debian/Ubuntu):**
```bash
# Add Reality port
sudo ufw allow 443/tcp

# If using additional protocols
sudo ufw allow 8443/tcp  # Hysteria2
sudo ufw allow 8444/tcp  # WS-TLS

# Enable firewall if not already
sudo ufw enable

# Verify
sudo ufw status
```

**For iptables (manual):**
```bash
# Add rule for Reality port
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT

# Save rules
sudo netfilter-persistent save  # Debian/Ubuntu
sudo service iptables save  # RHEL/CentOS
```

---

### Issue 11: Cloud Provider Firewall

**Symptoms:**
```
Firewall rules look correct
Port listening on server
Still can't connect from client
```

**Root Cause:**
Cloud provider (AWS, GCP, Azure, etc.) has separate firewall/security group

**Solutions:**

**AWS EC2 Security Groups:**
1. Go to EC2 Console
2. Select your instance
3. Click **Security** tab
4. Click the security group link
5. Click **Edit inbound rules**
6. Add rule:
   - Type: Custom TCP
   - Port: 443
   - Source: 0.0.0.0/0 (or your IP range)
7. Save rules

**Google Cloud Firewall:**
```bash
# Create firewall rule
gcloud compute firewall-rules create allow-reality \
  --allow tcp:443 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow Reality protocol"
```

**Azure Network Security Group:**
1. Go to Azure Portal
2. Find your VM's Network Security Group
3. Add inbound rule:
   - Service: Custom
   - Port: 443
   - Protocol: TCP
   - Action: Allow
4. Save

---

## Performance Issues

### Issue 12: Slow Connection Speed

**Symptoms:**
```
Connection works but slow speeds
High latency
Packet loss
```

**Diagnosis:**
```bash
# Check server load
top
uptime

# Check bandwidth usage
iftop  # Install with: sudo apt install iftop

# Check for packet loss
ping -c 100 8.8.8.8 | grep loss

# Check MTU issues
ip link show | grep mtu
```

**Solutions:**

**A. Enable TCP Fast Open:**
```bash
# Check if enabled in config
jq '.outbounds[0].tcp_fast_open' /etc/sing-box/config.json
# Should be: true

# If false, enable:
sudo jq '.outbounds[0].tcp_fast_open = true' /etc/sing-box/config.json > /tmp/config.json.fixed
sudo mv /tmp/config.json.fixed /etc/sing-box/config.json
sudo systemctl restart sing-box
```

**B. Optimize System TCP Settings:**
```bash
# Add to /etc/sysctl.conf
cat | sudo tee -a /etc/sysctl.conf <<'EOF'
# TCP optimization for proxy
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_congestion_control = bbr
EOF

# Apply settings
sudo sysctl -p
```

**C. Check Server Resources:**
```bash
# CPU usage
mpstat 1 5

# Memory usage
free -h

# Disk I/O
iostat -x 1 5

# If resources maxed out, upgrade server or reduce load
```

---

## Advanced Debugging

### Enable Debug Logging

**Temporary (current session only):**
```bash
# Stop service
sudo systemctl stop sing-box

# Run in foreground with debug logging
sudo /usr/local/bin/sing-box run -c /etc/sing-box/config.json -D

# Press Ctrl+C to stop
# Start service normally when done
sudo systemctl start sing-box
```

**Permanent:**
```bash
# Edit config to enable debug level
sudo jq '.log.level = "debug"' /etc/sing-box/config.json > /tmp/config.json.fixed
sudo mv /tmp/config.json.fixed /etc/sing-box/config.json

# Restart to apply
sudo systemctl restart sing-box

# Watch debug logs
journalctl -u sing-box -f

# Don't forget to change back to "warn" when done!
sudo jq '.log.level = "warn"' /etc/sing-box/config.json > /tmp/config.json.fixed
sudo mv /tmp/config.json.fixed /etc/sing-box/config.json
sudo systemctl restart sing-box
```

### Packet Capture

**Capture Reality handshake:**
```bash
# Install tcpdump
sudo apt install tcpdump  # Debian/Ubuntu
sudo yum install tcpdump  # RHEL/CentOS

# Capture port 443 traffic
sudo tcpdump -i any -w /tmp/reality-capture.pcap port 443

# Let it run during connection attempt
# Press Ctrl+C to stop

# Analyze with Wireshark locally
# Download /tmp/reality-capture.pcap
```

### Connection Test from Server

**Test Reality configuration locally:**
```bash
# Create test client config
cat > /tmp/test-client.json <<'EOF'
{
  "log": {"level": "debug"},
  "inbounds": [{
    "type": "mixed",
    "listen": "127.0.0.1",
    "listen_port": 1080
  }],
  "outbounds": [{
    "type": "vless",
    "server": "127.0.0.1",
    "server_port": 443,
    "uuid": "YOUR_UUID_HERE",
    "flow": "xtls-rprx-vision",
    "tls": {
      "enabled": true,
      "server_name": "www.microsoft.com",
      "reality": {
        "enabled": true,
        "public_key": "YOUR_PUBLIC_KEY_HERE",
        "short_id": "YOUR_SHORT_ID_HERE"
      }
    }
  }]
}
EOF

# Replace placeholders
sed -i "s/YOUR_UUID_HERE/$(jq -r '.inbounds[0].users[0].uuid' /etc/sing-box/config.json)/" /tmp/test-client.json
sed -i "s/YOUR_PUBLIC_KEY_HERE/$(grep PUBLIC_KEY= /etc/sing-box/client-info.txt | cut -d'=' -f2)/" /tmp/test-client.json
sed -i "s/YOUR_SHORT_ID_HERE/$(jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/sing-box/config.json)/" /tmp/test-client.json

# Run test client
sing-box run -c /tmp/test-client.json &
CLIENT_PID=$!

# Test connection
sleep 3
curl -x socks5://127.0.0.1:1080 https://www.google.com

# Cleanup
kill $CLIENT_PID
rm /tmp/test-client.json
```

---

## Getting Help

If you've tried all the above and still have issues:

1. **Gather information:**
   ```bash
   # System info
   uname -a
   sing-box version

   # Config validation
   sing-box check -c /etc/sing-box/config.json

   # Service status
   systemctl status sing-box

   # Recent logs
   journalctl -u sing-box -n 100 --no-pager

   # Network status
   ss -lntp | grep -E ':(443|8443|8444)'
   ```

2. **Check existing issues:**
   - sbx-lite: https://github.com/xrf9268-hue/sbx/issues
   - sing-box: https://github.com/SagerNet/sing-box/issues

3. **Create new issue:**
   Include:
   - Problem description
   - Steps to reproduce
   - System information (from step 1)
   - Configuration (sanitize keys/UUIDs!)
   - Logs (last 50 lines)

---

## Summary

**Most Common Issues:**
1. ✅ Short ID > 8 characters → Use `openssl rand -hex 4`
2. ✅ v2rayN connection failed → Switch core to sing-box
3. ✅ Network unreachable → Add `"strategy": "ipv4_only"` to DNS
4. ✅ Handshake timeout → Verify public/private key match
5. ✅ Service won't start → Check port conflicts and permissions

**Key Diagnostic Commands:**
```bash
systemctl status sing-box
sing-box check -c /etc/sing-box/config.json
journalctl -u sing-box -n 50
ss -lntp | grep 443
jq '.inbounds[0].tls.reality' /etc/sing-box/config.json
```

**Prevention:**
- ✅ Always validate config after changes: `sing-box check`
- ✅ Test locally before deploying: `sbx status`
- ✅ Keep backups: `sbx backup create --encrypt`
- ✅ Monitor logs: `journalctl -u sing-box -f`

---

**Document Version:** 1.0
**Last Updated:** 2025-11-16
**Status:** Complete
