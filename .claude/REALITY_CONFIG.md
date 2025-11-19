# Reality Protocol Configuration

Detailed configuration rules for sing-box VLESS-REALITY protocol.

## sing-box 1.12.0+ Requirements

**MUST follow these requirements:**
- Short ID: `openssl rand -hex 4` (8 chars, NOT 16 like Xray)
- Short ID validation: `[[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]]` immediately after generation
- Reality MUST be nested under `tls.reality` (NOT top-level)
- Flow field: `"flow": "xtls-rprx-vision"` in users array (NOT at inbound level)
- Short ID type: Array format `["a1b2c3d4"]` (NOT string)
- Transport: Vision flow requires TCP with Reality security
- Keypair: Use `sing-box generate reality-keypair` (NOT openssl)

## Mandatory Post-Configuration Validation

```bash
# 1. Validate syntax
sing-box check -c /etc/sing-box/config.json || die "Config invalid"

# 2. Verify structure
jq -e '.inbounds[0].tls.reality' /etc/sing-box/config.json || die "Reality not nested"

# 3. Check short_id type
[[ $(jq -r '.inbounds[0].tls.reality.short_id | type' /etc/sing-box/config.json) == "array" ]] || die "Short ID must be array"

# 4. Restart service and verify
systemctl restart sing-box && sleep 3
systemctl is-active sing-box || die "Service failed"
```

## sing-box 1.12.0+ Compliance

**NEVER use deprecated fields:**
- ❌ `sniff`, `sniff_override_destination`, `domain_strategy` in inbounds
- ❌ `domain_strategy` in outbounds (causes IPv6 failures)

**ALWAYS use:**
- ✅ `dns.strategy: "ipv4_only"` for IPv4-only networks (global setting)
- ✅ `listen: "::"` for dual-stack (NEVER "0.0.0.0")
- ✅ Route configuration with `action: "sniff"` and `action: "hijack-dns"`

## Reality Configuration Checklist

**When creating/modifying Reality configs:**
1. Generate materials with proper tools: `UUID`, `KEYPAIR`, `SID`
2. Validate materials immediately (especially short_id length)
3. Build config with validated materials
4. Verify structure: `jq -e '.tls.reality'`
5. Write and validate: `sing-box check`
6. Apply and verify service starts
7. Monitor logs for 10-15 seconds

## Modifying Reality Configuration

1. Read current config structure
2. Generate materials with validation
3. Create config using jq (never string manipulation)
4. Validate: `sing-box check -c /etc/sing-box/config.json`
5. Verify structure (Reality nesting, short_id type, flow field)
6. Restart: `systemctl restart sing-box`
7. Monitor: `journalctl -u sing-box -f` for 10-15 seconds

## Debugging Installation

```bash
# Enable full debug logging
DEBUG=1 LOG_TIMESTAMPS=1 LOG_FILE=/tmp/debug.log bash install.sh

# Check for errors
grep -i error /tmp/debug.log

# Test in strict mode (like CI)
bash -e install.sh
```
