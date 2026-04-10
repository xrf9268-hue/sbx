# GitHub Issues: Project Improvement Suggestions

> Generated from the [project comparison review](../docs/plans/) against community projects.
> Each section below is a self-contained GitHub Issue — copy the **Title** and **Body** into GitHub's issue form.

---

## High Priority

---

### Issue 1

**Title:** feat: Add TUIC V5 and Trojan protocol support

**Labels:** `enhancement`, `protocol`

**Body:**

#### Background

sbx currently supports 3 protocols (Reality, WS-TLS, Hysteria2), while comparable projects support 10+ protocols. TUIC V5 and Trojan are the most commonly used fallback protocols in the community.

#### Motivation

- Users in different network environments need alternative protocols when one is blocked
- TUIC V5 (QUIC-based) provides a UDP alternative to Hysteria2
- Trojan (TLS-based) is widely supported by clients and is a proven fallback option
- sing-box natively supports both protocols, making integration straightforward

#### Requirements

- [ ] Add TUIC V5 inbound configuration generation
- [ ] Add Trojan inbound configuration generation
- [ ] Support key/certificate management for Trojan
- [ ] Add corresponding client export formats (URI, Clash Meta YAML)
- [ ] Add unit tests for new protocol generators
- [ ] Update `sbx reconfigure` to handle new protocol options
- [ ] Update documentation and README

#### Reference

- [fscarmen/sing-box](https://github.com/fscarmen/sing-box) — supports 11+ protocols
- [233boy/sing-box](https://github.com/233boy/sing-box) — supports TUIC and Trojan
- [sing-box documentation: TUIC](https://sing-box.sagernet.org/configuration/inbound/tuic/)
- [sing-box documentation: Trojan](https://sing-box.sagernet.org/configuration/inbound/trojan/)

---

### Issue 2

**Title:** feat: Provide single-file distribution for remote installation

**Labels:** `enhancement`, `installer`

**Body:**

#### Background

The current `curl | bash` remote installation works by downloading 21 separate module files from GitHub (with parallel download + sequential fallback). While functional, this requires 21+ HTTP requests, which can be slow or fail in network-constrained environments.

#### Motivation

- Single-file scripts (like 233boy and fscarmen) are more resilient for one-shot remote installs
- Reduces failure points from 21 network requests to 1
- Users in restricted network environments benefit significantly
- Maintains modular source for development while offering a bundled artifact for deployment

#### Requirements

- [ ] Create a build script (`scripts/build-single-file.sh`) that concatenates all lib modules into a single `install-bundled.sh`
- [ ] Strip duplicate `set -euo pipefail` and module-loading logic in bundled output
- [ ] Add a CI step to generate the bundled file on each release/tag
- [ ] Publish the bundled file as a GitHub Release asset
- [ ] Update README with alternative install command using the bundled file
- [ ] Ensure bundled file passes all existing unit tests

#### Non-goals

- Replacing the modular source structure — this is a distribution optimization only

---

### Issue 3

**Title:** feat: Add multi-user UUID management

**Labels:** `enhancement`, `feature-request`

**Body:**

#### Background

sbx currently supports a single user per protocol. In production environments, multiple users sharing a single server is a basic requirement.

#### Motivation

- Sharing a server among multiple users is the most common deployment scenario
- Competing projects (reality-ezpz) support full user CRUD via CLI, TUI, and Telegram Bot
- Without multi-user support, operators must manually edit sing-box JSON configs

#### Requirements

- [ ] Add `sbx user add [--name NAME]` — generate a new UUID and add to active config
- [ ] Add `sbx user list` — show all users with names and UUIDs
- [ ] Add `sbx user remove <UUID|NAME>` — remove a user
- [ ] Add `sbx user reset <UUID|NAME>` — regenerate UUID for an existing user
- [ ] Persist user list in `state.json`
- [ ] Update all protocol generators to support multi-user inbounds
- [ ] Update client export to generate per-user configs
- [ ] Add unit tests for user CRUD operations

#### Reference

- [aleskxyz/reality-ezpz](https://github.com/aleskxyz/reality-ezpz) — full user management with CLI/TUI/Telegram Bot

---

### Issue 4

**Title:** feat: Add Docker deployment option (Dockerfile + docker-compose)

**Labels:** `enhancement`, `deployment`

**Body:**

#### Background

sbx currently only supports bare-metal installation. Docker/container-based deployment offers cleaner isolation, easier upgrades, and better reproducibility.

#### Motivation

- Docker deployments are cleaner and more reproducible than bare-metal installs
- Easier rollback (just switch container image tags)
- reality-ezpz is fully Docker-based and provides a smoother deployment experience
- The existing E2E Docker smoke tests already prove the concept works in containers

#### Requirements

- [ ] Create `Dockerfile` based on a minimal image (e.g., `alpine:latest` or `debian:slim`)
- [ ] Create `docker-compose.yml` with proper volume mounts for config persistence
- [ ] Support environment variables for initial configuration (domain, protocol, port)
- [ ] Ensure config and state survive container restarts via mounted volumes
- [ ] Add health check endpoint for Docker health monitoring
- [ ] Document Docker deployment in README
- [ ] Add Docker-specific section to troubleshooting guide

#### Reference

- [aleskxyz/reality-ezpz](https://github.com/aleskxyz/reality-ezpz) — fully Docker Compose based

---

## Medium Priority

---

### Issue 5

**Title:** feat: Add Hysteria2 port hopping support

**Labels:** `enhancement`, `protocol`

**Body:**

#### Background

Port hopping (periodically switching UDP ports) is a key anti-blocking technique for UDP-based protocols like Hysteria2. sbx currently does not implement this.

#### Motivation

- ISPs may throttle or block specific UDP ports; port hopping evades per-port blocking
- Hysteria2 natively supports port hopping via iptables/nftables DNAT rules
- This significantly improves Hysteria2 reliability in hostile network environments

#### Requirements

- [ ] Add iptables/nftables DNAT rules for UDP port range forwarding
- [ ] Make port range configurable (e.g., `--hy2-port-range 20000-40000`)
- [ ] Add `sbx hy2-ports` command to show/manage port hopping status
- [ ] Update client export to include port hopping parameters
- [ ] Persist port range in `state.json`
- [ ] Add cleanup logic on uninstall to remove DNAT rules
- [ ] Add unit tests

#### Reference

- [Hysteria2 documentation: Port Hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/)

---

### Issue 6

**Title:** feat: Add adaptive subscription endpoint

**Labels:** `enhancement`, `feature-request`

**Body:**

#### Background

Currently, users must manually copy URIs or config files for each client. An adaptive subscription endpoint would serve a single URL that auto-detects the client type (Clash, V2Ray, Shadowrocket, etc.) and returns the appropriate format.

#### Motivation

- Single URL simplifies client configuration — no manual format conversion
- Auto-updates when server config changes — clients fetch latest config on refresh
- Standard feature in competing projects (fscarmen, 233boy)

#### Requirements

- [ ] Implement a lightweight HTTP endpoint (e.g., using `sing-box` built-in API or a simple `socat`/`python3 -m http.server` wrapper)
- [ ] Detect client type from `User-Agent` header
- [ ] Return appropriate format: Base64 (V2Ray), YAML (Clash Meta), URI list (Shadowrocket)
- [ ] Support optional token-based access control
- [ ] Add `sbx subscription [on|off|status|url]` management commands
- [ ] Persist subscription config in `state.json`
- [ ] Add unit tests for format generation

---

### Issue 7

**Title:** feat: Add Chinese language (i18n) support

**Labels:** `enhancement`, `i18n`

**Body:**

#### Background

All user-facing output is currently English-only per coding standards. However, the target user base likely includes a significant number of Chinese-speaking users.

#### Motivation

- 233boy and fscarmen both support Chinese/English bilingual interfaces
- Lowering the language barrier increases adoption
- The project already uses structured message functions (`msg_info`, `msg_error`), making i18n integration feasible

#### Requirements

- [ ] Create a `lib/i18n.sh` module with message key lookups
- [ ] Add Chinese translation strings (`locale/zh.sh` or embedded in i18n module)
- [ ] Support `LANG=zh` or `--lang zh` to switch language
- [ ] Default to English; auto-detect from system locale as optional behavior
- [ ] Translate key user-facing messages (prompts, errors, success messages, help text)
- [ ] Add unit tests for i18n message resolution
- [ ] Update coding standards documentation

---

### Issue 8

**Title:** refactor: Consolidate small modules to reduce file count

**Labels:** `refactoring`, `maintenance`

**Body:**

#### Background

Some lib modules are very small (e.g., `colors.sh` ~66 lines, `caddy_cleanup.sh` ~68 lines) and could be merged into related modules to reduce the total module count and simplify the dependency chain.

#### Motivation

- Fewer modules = fewer HTTP requests during remote install
- Simpler dependency chain reduces failure surface
- Easier for contributors to navigate the codebase
- Some modules are too small to justify independent existence

#### Requirements

- [ ] Audit all modules under `lib/` by line count and dependency usage
- [ ] Merge `colors.sh` into `common.sh` (already a dependency)
- [ ] Merge `caddy_cleanup.sh` into the relevant deployment or cleanup module
- [ ] Identify and merge other sub-100-line modules where appropriate
- [ ] Update all `source` references and module loading order
- [ ] Ensure all unit tests pass after consolidation
- [ ] Update architecture documentation

#### Constraints

- Do not merge modules with different lifecycle concerns (e.g., don't merge install-time code with runtime management code)
- Maintain the three-tier loading order (Core -> Infrastructure -> Business Logic)

---

## Low Priority

---

### Issue 9

**Title:** feat: Add Cloudflare Argo Tunnel integration

**Labels:** `enhancement`, `feature-request`

**Body:**

#### Background

Cloudflare Argo Tunnel (now Cloudflare Tunnel) allows exposing services without a public IP or domain, using Cloudflare's network as a reverse proxy.

#### Motivation

- Enables deployment without owning a domain name — significant barrier reduction
- Provides CDN-level DDoS protection and IP hiding
- fscarmen and GFW4Fun both offer this as a differentiating feature
- Works well with WebSocket-based protocols (WS-TLS)

#### Requirements

- [ ] Integrate `cloudflared` binary download and installation
- [ ] Support both temporary tunnels (quick token) and named tunnels (persistent)
- [ ] Auto-configure sing-box inbound to listen on localhost when using tunnel
- [ ] Add `sbx tunnel [start|stop|status]` management commands
- [ ] Update client export with Argo tunnel hostnames
- [ ] Add documentation for Argo tunnel setup

#### Reference

- [fscarmen/sing-box](https://github.com/fscarmen/sing-box) — Argo tunnel integration
- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

---

### Issue 10

**Title:** feat: Add Telegram Bot for remote management

**Labels:** `enhancement`, `feature-request`

**Body:**

#### Background

A Telegram Bot interface allows remote server management without SSH access, which is convenient for mobile management and multi-server operators.

#### Motivation

- Manage server from mobile without SSH client
- reality-ezpz provides Telegram Bot for user management
- Useful for operators managing multiple servers
- Can serve as notification channel for server events (restart, errors)

#### Requirements

- [ ] Create a lightweight Telegram Bot daemon (`bin/sbx-telegram-bot`)
- [ ] Support commands: `/status`, `/users`, `/adduser`, `/removeuser`, `/restart`
- [ ] Support bot token configuration via `sbx telegram setup`
- [ ] Support admin chat ID whitelist for access control
- [ ] Run as a systemd service alongside sing-box
- [ ] Add unit tests for bot command parsing

#### Reference

- [aleskxyz/reality-ezpz](https://github.com/aleskxyz/reality-ezpz) — Telegram Bot management

---

### Issue 11

**Title:** feat: Add traffic statistics dashboard

**Labels:** `enhancement`, `feature-request`

**Body:**

#### Background

Currently there is no built-in way to monitor bandwidth usage, connection counts, or per-user traffic. This information is valuable for server operators.

#### Motivation

- Operators need visibility into server resource usage
- Helps identify abusive users or unusual traffic patterns
- sing-box has a built-in API (`experimental.clash_api`) that exposes traffic data
- Can be exposed via `sbx stats` command or a simple web dashboard

#### Requirements

- [ ] Enable sing-box Clash API in generated configs (with authentication)
- [ ] Add `sbx stats` command showing real-time traffic, connections, uptime
- [ ] Optionally add `sbx stats --json` for programmatic consumption
- [ ] If multi-user is implemented, show per-user traffic breakdown
- [ ] Consider a simple HTML dashboard served on a local port (optional)
- [ ] Add documentation for traffic monitoring

---

### Issue 12

**Title:** feat: Auto-rotate Reality Short ID on schedule

**Labels:** `enhancement`, `security`

**Body:**

#### Background

Reality protocol uses a Short ID as part of its handshake. Periodically rotating this value can reduce the window for traffic analysis and fingerprinting.

#### Motivation

- Enhances operational security by limiting the lifespan of any single Short ID
- Reduces risk if a Short ID is leaked or observed
- Can be implemented as a simple cron job or systemd timer
- Minimal disruption if clients are notified or auto-updated via subscription endpoint

#### Requirements

- [ ] Add `sbx rotate-shortid` command to generate and apply a new Short ID
- [ ] Add optional `--schedule` flag to set up automatic rotation (e.g., `--schedule weekly`)
- [ ] Implement as a systemd timer or cron job
- [ ] Automatically update client configs / subscription endpoint after rotation
- [ ] Log rotation events for audit trail
- [ ] Add `--dry-run` flag to preview changes without applying
- [ ] Persist rotation history in `state.json`
- [ ] Add unit tests

#### Dependencies

- Issue #6 (Subscription endpoint) — for automatic client config updates after rotation
