# Cloudflare Tunnel (Argo) Integration

`sbx` ships with first-class support for [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
(the rebranded Argo Tunnel). When tunnel mode is enabled, sing-box's
WebSocket inbound is bound to `127.0.0.1` and Cloudflare's edge fronts all
public traffic — so you can deploy without owning a domain name, without
exposing any inbound port, and with Cloudflare's DDoS protection on top.

> **Tracking issue:** [#104](https://github.com/xrf9268-hue/sbx/issues/104)

## Protocol compatibility

| Inbound          | Tunnel-compatible? | Why |
|------------------|--------------------|-----|
| **VLESS+WS+TLS** | ✅ Yes             | WebSocket — what cloudflared was built for |
| VLESS-Reality    | ❌ No              | Raw TCP + custom TLS handshake; cloudflared terminates TLS |
| Hysteria2        | ❌ No              | QUIC/UDP; cloudflared only proxies HTTP/WS |
| TUIC             | ❌ No              | QUIC/UDP |
| Trojan (TCP+TLS) | ❌ No              | Custom TLS handshake; not HTTP-framed |

When you enable tunnel mode, only the **WS-TLS VLESS** URI will be valid —
direct-connect protocols still listen on their normal addresses but cannot be
reached from the Internet unless your firewall allows them.

## Quickstart — named tunnel via Zero Trust token

This is the recommended mode for production. Hostnames persist across
reboots and you can manage everything from the Cloudflare dashboard.

1. **Create a tunnel** in the Cloudflare Zero Trust dashboard:
   *Networks → Tunnels → Create a tunnel → Cloudflared*. Copy the **token**
   (a long base64 string starting with `ey...`).
2. **Add a public hostname** to the tunnel pointing at
   `http://localhost:8444` (or whichever port your sing-box WS inbound uses).
   Choose any hostname under a domain you've added to Cloudflare, e.g.
   `vpn.example.com`.
3. **Enable the tunnel on the server**:

   ```bash
   sudo sbx tunnel install
   sudo sbx tunnel enable <TOKEN> vpn.example.com
   ```

4. **Verify**:

   ```bash
   sbx tunnel status
   #   Binary   : /usr/local/bin/cloudflared (cloudflared version 2024.x)
   #   Service  : active
   #   Hostname : vpn.example.com

   sbx info        # WS-TLS URI now points at vpn.example.com:443
   ```

5. **Import** the WS URI into your client (v2rayN/NekoBox/Clash/etc.). Done.

## Quickstart — quick tunnel (no Cloudflare account)

For testing only. The hostname is ephemeral (`*.trycloudflare.com`),
randomly assigned at start, and disappears the moment cloudflared restarts.

```bash
sudo sbx tunnel install
# Run cloudflared in the foreground to capture the trycloudflare.com URL
cloudflared --no-autoupdate tunnel --url http://127.0.0.1:8444
```

Copy the printed `https://*.trycloudflare.com` hostname and use it manually
for testing. For persistent deployments, switch to the token mode above.

## Files installed

| Path                                    | Purpose |
|-----------------------------------------|---------|
| `/usr/local/bin/cloudflared`            | Official Cloudflare binary |
| `/etc/systemd/system/cloudflared.service` | systemd unit (hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`) |
| `/etc/cloudflared/config.yml`           | Ingress map: `<hostname> → http://127.0.0.1:<WS_PORT>` |
| `/etc/cloudflared/tunnel.env`           | `TUNNEL_TOKEN=...` (mode `600`, root-only) — referenced by the unit's `EnvironmentFile` so the token never appears on the command line |

The tunnel state is persisted under `.tunnel` in
`/etc/sing-box/state.json` and read by `sbx info` / `sbx export` so URIs
automatically reflect the active hostname.

## CLI reference

```
sbx tunnel install [version]        Download/install cloudflared
sbx tunnel enable <token> <host>    Enable named tunnel via Zero Trust token
sbx tunnel disable                  Stop service and scrub the token file
sbx tunnel status                   Show binary, service and hostname
sbx tunnel hostname                 Print just the active tunnel hostname
```

## Rotating the token

If a token is compromised, rotate it from the Zero Trust dashboard
(*Tunnels → … → Refresh token*), then re-run:

```bash
sudo sbx tunnel enable <NEW_TOKEN> vpn.example.com
```

`tunnel.env` is rewritten atomically and the systemd service restarts.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `sbx tunnel status` shows `inactive` | `journalctl -u cloudflared -n 80 --no-pager` |
| Connection times out from client | Confirm the tunnel public hostname routes to `http://localhost:<WS_PORT>` in the Cloudflare dashboard, and that sing-box is listening: `ss -tlnp \| grep <WS_PORT>` |
| `cloudflared` complains about token | Ensure the token wasn't truncated; the file at `/etc/cloudflared/tunnel.env` should contain a single line `TUNNEL_TOKEN=ey...` |
| Reality / Hy2 / TUIC URIs no longer work | Expected — those protocols cannot be tunneled. Use the WS URI when tunnel mode is on, or expose those ports directly through the firewall. |
| Want to fall back to direct connect | `sudo sbx tunnel disable` — sing-box keeps running and Reality/Hy2/TUIC remain reachable on the host's public IP |

## See also

- [Cloudflare Tunnel architecture](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)
- [cloudflared releases](https://github.com/cloudflare/cloudflared/releases)
- Issue [#104](https://github.com/xrf9268-hue/sbx/issues/104)
