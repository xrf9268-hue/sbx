# Code Architecture

Technical architecture and module organization for sbx-lite.

## Modular Structure

**Main:** `install.sh` (~1,581 lines) - Orchestrates installation
**Library:** `lib/` directory (21 modules, ~7,969 lines total)

## Module List

| Module | Lines | Description |
|--------|-------|-------------|
| `lib/backup.sh` | 594 | Backup/restore operations |
| `lib/caddy_cleanup.sh` | 68 | Legacy Caddy uninstall (migration tool) |
| `lib/certificate.sh` | 126 | CERT_MODE resolution, ACME parameter validation |
| `lib/checksum.sh` | 189 | Binary SHA256 verification |
| `lib/colors.sh` | 66 | Terminal color definitions |
| `lib/common.sh` | 537 | Utilities, constants, temp file helpers |
| `lib/config.sh` | 668 | sing-box JSON config generation (ACME, Reality, WS, Hy2) |
| `lib/config_validator.sh` | 456 | Configuration validation rules |
| `lib/download.sh` | 396 | Binary download with retry logic |
| `lib/export.sh` | 411 | Client config export (URI, Clash, QR) |
| `lib/generators.sh` | 243 | UUID, keypair, short ID generation |
| `lib/logging.sh` | 284 | Structured logging framework |
| `lib/messages.sh` | 329 | User-facing message templates |
| `lib/network.sh` | 462 | IP detection, port allocation |
| `lib/retry.sh` | 359 | Retry logic with exponential backoff |
| `lib/schema_validator.sh` | 360 | JSON schema validation |
| `lib/service.sh` | 328 | systemd service management |
| `lib/tools.sh` | 432 | External tool detection and setup |
| `lib/ui.sh` | 326 | Interactive UI helpers |
| `lib/validation.sh` | 872 | Input sanitization, security validation |
| `lib/version.sh` | 463 | Version detection, comparison, upgrades |

## Security-Critical Functions

- `sanitize_input()` - Remove shell metacharacters (lib/validation.sh)
- `validate_short_id()` - Enforce 8-char limit (lib/validation.sh)
- `validate_cf_api_token()` - CF API token validation (lib/validation.sh)
- `verify_singbox_binary()` - SHA256 verification (lib/checksum.sh)
- `_build_tls_block()` - ACME/TLS config generation (lib/config.sh)
- `write_config()` - Atomic config writes (lib/config.sh)
- `cleanup()` - Secure temp file cleanup (lib/common.sh)

---

## Architecture Diagrams

### 1. Module Dependency Architecture

Module loading order and functional grouping. Modules are loaded sequentially
by `_load_modules()` in install.sh; earlier modules provide APIs to later ones.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         install.sh (entry point)                    │
│  • Early constants (readonly)                                       │
│  • Bootstrap helpers (get_file_size, create_temp_dir)               │
│  • _load_modules() → sources all lib/*.sh in order                  │
│  • _verify_module_apis() → validates function contracts             │
│  • install_flow() / uninstall_flow() / main()                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ source (in order)
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
┌─────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  Layer 1: Core  │ │  Layer 2: Infra  │ │  Layer 3: Logic  │
│  (loaded first) │ │  (mid loading)   │ │  (loaded last)   │
├─────────────────┤ ├──────────────────┤ ├──────────────────┤
│ colors.sh       │ │ retry.sh         │ │ config.sh        │
│ common.sh       │ │ download.sh      │ │ config_validator │
│ logging.sh      │ │ network.sh       │ │ schema_validator │
│ generators.sh   │ │ validation.sh    │ │ service.sh       │
│ tools.sh        │ │ checksum.sh      │ │ ui.sh            │
│                 │ │ version.sh       │ │ backup.sh        │
│                 │ │ certificate.sh   │ │ export.sh        │
│                 │ │ caddy_cleanup.sh │ │ messages.sh      │
└─────────────────┘ └──────────────────┘ └──────────────────┘
```

**Loading order** (exact sequence in `_load_modules()`):
```
colors → common → logging → generators → tools → retry → download →
network → validation → checksum → version → certificate →
caddy_cleanup → config → config_validator → schema_validator →
service → ui → backup → export → messages
```

**Key dependency chains:**
- `colors.sh` → `common.sh` → `logging.sh` (output infrastructure)
- `retry.sh` → `download.sh` (download with backoff)
- `validation.sh` → `config.sh` → `config_validator.sh` (validate → generate → verify)
- `generators.sh` → `config.sh` (UUID/keypair → config assembly)

---

### 2. Installation Flow

Complete flow from `bash install.sh` to running service.

```
bash install.sh
       │
       ▼
    main()
       │
       ├── arg == "uninstall"? ──Yes──► uninstall_flow()
       │                                     │
       No                              stop_service()
       │                              remove_service()
       ▼                              rm files & dirs
  install_flow()                           │
       │                                   ▼
       ▼                                 Done
  show_logo()
       │
       ▼
  need_root() ──── not root? ──► die("must be root")
       │
       ▼
  validate_env_vars() ◄── only if DOMAIN is set
       │
       ▼
  check_existing_installation()
       │
       ├── Not installed ──────────────────────────────────┐
       │                                                   │
       ├── Existing → Interactive menu:                    │
       │   ├── [1] Fresh install (backup old config)       │
       │   ├── [2] Upgrade binary (SKIP_CONFIG_GEN=1)      │
       │   ├── [3] Reconfigure (SKIP_BINARY_DOWNLOAD=1)    │
       │   ├── [4] Uninstall → uninstall_flow()            │
       │   ├── [5] Show config → display & exit            │
       │   └── [6] Exit                                    │
       │                                                   │
       ▼◄──────────────────────────────────────────────────┘
  ensure_tools() ── missing? ──► auto-install (apt/yum/dnf)
       │
       ▼
  download_singbox()
       │  detect_arch()        → amd64/arm64/armv7
       │  detect_libc()        → glibc or musl
       │  resolve_singbox_version() → tag (e.g. v1.13.0)
       │  safe_http_get()      → GitHub API → download URL
       │  verify_singbox_binary() → SHA256 checksum
       │  extract & install    → /usr/local/bin/sing-box
       │
       ▼
  ┌─ SKIP_CONFIG_GEN? ─┐
  │                     │
  No                   Yes
  │                     │
  ▼                     ▼
  gen_materials()    restart_service()
  │                     │
  │                     ▼
  │                   Done
  │
  ├── _configure_server_address()
  │     └── IP → REALITY_ONLY_MODE=1
  │     └── Domain → REALITY_ONLY_MODE=0
  │
  ├── _configure_cloudflare_mode()
  │     └── CF_MODE=1 → WS on 443, no Reality/Hy2
  │
  ├── _validate_protocol_config()
  │
  ├── _generate_credentials()
  │     ├── generate_uuid()            → UUID
  │     ├── generate_reality_keypair() → PRIV, PUB
  │     └── openssl rand -hex 4        → SID (8 chars)
  │
  └── _allocate_ports()
        ├── Reality → 443 (default)
        ├── WS-TLS  → 8444 (default)
        └── Hy2     → 8443/udp (default)
       │
       ▼
  maybe_issue_cert() ◄── only if REALITY_ONLY_MODE=0
       │
       ▼
  write_config()
       │  create_base_config()     → DNS + log skeleton
       │  _create_all_inbounds()   → Reality + WS + Hy2
       │  add_route_config()       → sniff + hijack-dns
       │  add_outbound_config()    → direct outbound
       │  validate_config_pipeline() → full validation
       │  atomic mv → /etc/sing-box/config.json
       │
       ▼
  setup_service()  → systemd unit → start → verify
       │
       ▼
  save_client_info() → /etc/sing-box/client-info.txt
       │
       ▼
  install_manager_script() → /usr/local/bin/sbx
       │
       ▼
  open_firewall() → iptables/ufw/firewalld rules
       │
       ▼
  print_summary() → connection URIs, QR code hints
```

---

### 3. Protocol Mode Decision Tree

How environment variables determine which protocols get enabled.

```
                    ┌─────────────────┐
                    │  bash install.sh │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  DOMAIN set?    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │ No / IP only │              │ Yes (domain)
              ▼              │              ▼
    ┌─────────────────┐      │    ┌─────────────────┐
    │ REALITY_ONLY=1  │      │    │ REALITY_ONLY=0  │
    │                 │      │    │                 │
    │ Reality: ON     │      │    │  CF_MODE=1?     │
    │ WS-TLS: OFF     │      │    └────────┬────────┘
    │ Hy2:    OFF     │      │             │
    └─────────────────┘      │    ┌────────┼────────┐
                             │    │ No     │        │ Yes
                             │    ▼        │        ▼
                             │ ┌──────────────┐ ┌──────────────────┐
                             │ │  Standard    │ │  Cloudflare Mode │
                             │ │              │ │                  │
                             │ │ Reality: ON  │ │ Reality: OFF     │
                             │ │ WS-TLS:  ON  │ │ WS-TLS:  ON     │
                             │ │ Hy2:     ON  │ │ Hy2:     OFF     │
                             │ │              │ │                  │
                             │ │ Ports:       │ │ Port:            │
                             │ │  443  Reality│ │  443 WS-TLS     │
                             │ │  8444 WS-TLS │ │                  │
                             │ │  8443 Hy2/UDP│ │ CF proxy (CDN)   │
                             │ └──────────────┘ └──────────────────┘
                             │
                             │   Certificate Modes (when domain set):
                             │   ┌───────────────────────────────────┐
                             │   │ CERT_MODE not set → native ACME  │
                             │   │   (sing-box built-in, HTTP-01)   │
                             │   │                                   │
                             │   │ CERT_MODE=cf_dns → DNS-01 ACME   │
                             │   │   (via CF API, no port 80 needed)│
                             │   └───────────────────────────────────┘
```

---

### 4. Configuration Generation Flow

How `write_config()` assembles the sing-box JSON configuration.

```
write_config()
       │
       ├── detect_ipv6_support() → true/false
       │     └── choose_listen_address() → "::" (dual-stack)
       │
       ├── validate_config_vars()
       │     └── check UUID, PRIV, SID, ports
       │
       ├── _validate_certificate_config()
       │
       ▼
  create_base_config(ipv6, log_level)
       │
       │  Output (jq -n):
       │  ┌──────────────────────────────────┐
       │  │ {                                │
       │  │   "log": { "level": "warn" },    │
       │  │   "dns": {                       │
       │  │     "servers": [...],            │
       │  │     "strategy": "ipv4_only"      │  ◄── if no IPv6
       │  │   },                             │
       │  │   "inbounds": [],                │  ◄── empty, filled next
       │  │   "outbounds": [],               │
       │  │   "route": {}                    │
       │  │ }                                │
       │  └──────────────────────────────────┘
       │
       ▼
  _create_all_inbounds(base_config, uuid, ...)
       │
       ├── ENABLE_REALITY=1?
       │     └── create_reality_inbound()
       │           │  type: vless
       │           │  listen: "::", port: 443
       │           │  users: [{ uuid, flow: "xtls-rprx-vision" }]
       │           │  tls.reality: { private_key, short_id: [...] }
       │           │  tls.reality.handshake: { server, port: 443 }
       │           └── jq: .inbounds += [$reality]
       │
       ├── TLS available? (certs or ACME mode)
       │     │
       │     ├── ENABLE_WS=1?
       │     │     ├── _build_tls_block(domain, alpn, certs/acme)
       │     │     └── create_ws_inbound(uuid, port, tls)
       │     │           │  type: vless, transport: ws
       │     │           └── jq: .inbounds += [$ws]
       │     │
       │     └── ENABLE_HY2=1?
       │           ├── _build_tls_block(domain, alpn, certs/acme)
       │           └── create_hysteria2_inbound(pass, port, tls)
       │                 │  type: hysteria2
       │                 └── jq: .inbounds += [$hy2]
       │
       ▼
  add_route_config(config, has_certs)
       │  rules: [{ action: "sniff" }, { action: "hijack-dns" }]
       │
       ▼
  add_outbound_config(config)
       │  outbounds: [{ type: "direct", tag: "direct" }]
       │
       ▼
  validate_config_pipeline(temp_conf)
       │  ├── JSON syntax check (jq)
       │  ├── Schema validation (schema_validator.sh)
       │  ├── Config rules check (config_validator.sh)
       │  └── sing-box check (if binary available)
       │
       ▼
  atomic mv → /etc/sing-box/config.json (permissions: 600)
```

---

### 5. Backup & Restore Flow

How `sbx backup` and `sbx restore` work.

```
  sbx backup create [--encrypt]
       │
       ▼
  backup_create()
       │
       ├── Collect files:
       │   ├── /etc/sing-box/config.json
       │   ├── /etc/sing-box/client-info.txt
       │   └── /usr/local/lib/sbx/*.sh (lib modules)
       │
       ├── Create tar.gz archive
       │     └── /var/backups/sbx/sbx-backup-YYYYMMDD-HHMMSS.tar.gz
       │
       ├── --encrypt flag?
       │     └── openssl enc → .tar.gz.enc (password prompt)
       │
       └── Verify archive integrity
             └── tar -tzf (list test)


  sbx backup restore <file>
       │
       ▼
  backup_restore()
       │
       ├── _validate_backup_archive()
       │     ├── File exists & readable?
       │     ├── Encrypted? → _decrypt_backup() (password prompt)
       │     └── Valid tar.gz?
       │
       ├── _prepare_rollback()
       │     └── Snapshot current config for rollback
       │
       ├── Extract archive → temp dir
       │
       ├── _apply_restored_config()
       │     ├── Validate extracted config (sing-box check)
       │     ├── Copy config to /etc/sing-box/
       │     └── Restore lib modules if present
       │
       ├── _restore_service_state()
       │     ├── systemctl restart sing-box
       │     └── Verify service is running
       │
       └── Failed? → Rollback to snapshot
```

---

### 6. Client Export Flow

How `sbx info` / `sbx export` generates client configurations.

```
  sbx info / sbx export
       │
       ▼
  load_client_info()
       │  Read /etc/sing-box/client-info.txt
       │  Parse: DOMAIN, UUID, PUB, SID, ports, protocols
       │
       ▼
  export_config(format)
       │
       ├── "uri" → export_uri()
       │     ├── Reality: vless://UUID@IP:443?security=reality&...
       │     ├── WS-TLS:  vless://UUID@DOMAIN:8444?type=ws&...
       │     └── Hy2:     hysteria2://PASS@DOMAIN:8443?...
       │
       ├── "clash" → export_clash_yaml()
       │     └── Generate Clash Meta YAML config
       │
       ├── "qr" → export_qr_codes()
       │     └── URI → qrencode → terminal QR display
       │
       └── "sub" → export_subscription()
             └── Base64-encoded URI list
```

---

### 7. Project File Structure

```
sbx/
├── install.sh                  # Main installer (entry point)
├── sbx-manager.sh              # Post-install management tool (sbx command)
├── CLAUDE.md                   # AI assistant instructions
├── CONTRIBUTING.md             # Developer guide
├── README.md                   # User documentation
├── LICENSE                     # MIT License
│
├── lib/                        # Library modules (21 files)
│   ├── colors.sh               #   Terminal color definitions
│   ├── common.sh               #   Utilities, constants, temp helpers
│   ├── logging.sh              #   Structured logging (msg/warn/err/debug)
│   ├── generators.sh           #   UUID, keypair, short ID generation
│   ├── tools.sh                #   External tool detection and setup
│   ├── retry.sh                #   Retry with exponential backoff
│   ├── download.sh             #   Binary download with verification
│   ├── network.sh              #   IP detection, port allocation
│   ├── validation.sh           #   Input sanitization, security checks
│   ├── checksum.sh             #   SHA256 binary verification
│   ├── version.sh              #   Version detection and comparison
│   ├── certificate.sh          #   CERT_MODE resolution, ACME params
│   ├── caddy_cleanup.sh        #   Legacy Caddy migration tool
│   ├── config.sh               #   sing-box JSON config generation
│   ├── config_validator.sh     #   Config validation rules
│   ├── schema_validator.sh     #   JSON schema validation
│   ├── service.sh              #   systemd service management
│   ├── ui.sh                   #   Interactive UI helpers
│   ├── backup.sh               #   Backup/restore operations
│   ├── export.sh               #   Client config export (URI/Clash/QR)
│   └── messages.sh             #   User-facing message templates
│
├── tests/                      # Test suite
│   ├── test-runner.sh          #   Test runner (unit/integration)
│   ├── test_framework.sh       #   Test assertion framework
│   ├── unit/                   #   Unit tests
│   │   ├── test_bootstrap_constants.sh
│   │   ├── test_validation.sh
│   │   └── ...
│   ├── integration/            #   Integration tests
│   └── mocks/                  #   Mock implementations for testing
│
├── examples/                   # Configuration examples
│   ├── reality-only/           #   Minimal Reality setup
│   ├── reality-with-ws/        #   Multi-protocol examples
│   ├── advanced/               #   Advanced configurations
│   └── troubleshooting/        #   Debug examples
│
├── docs/                       # Documentation
│   ├── ADVANCED.md             #   Environment variables & customization
│   ├── REALITY_BEST_PRACTICES.md   # Production deployment
│   ├── REALITY_TROUBLESHOOTING.md  # Connection/installation issues
│   └── SING_BOX_VS_XRAY.md        # Migration guide
│
├── hooks/                      # Git hooks & CI
│   └── install-hooks.sh        #   Pre-commit hook installer
│
└── .claude/                    # AI development context
    ├── ARCHITECTURE.md         #   This file
    ├── CODING_STANDARDS.md     #   Bash patterns & standards
    ├── CONSTANTS_REFERENCE.md  #   Constants lookup
    ├── REALITY_CONFIG.md       #   Protocol configuration rules
    ├── README.md               #   Hook configuration
    ├── WORKFLOWS.md            #   TDD & git workflows
    ├── plans/                  #   Project planning docs
    ├── scripts/                #   Automated hooks (SessionStart, etc.)
    └── handoffs/               #   Session continuity files
```

---

### 8. Runtime File Layout (After Installation)

```
Server filesystem after `bash install.sh`:

/usr/local/bin/
├── sing-box              # sing-box binary
└── sbx                   # Management CLI (symlink or script)

/usr/local/lib/sbx/
└── *.sh                  # Installed library modules (for sbx command)

/etc/sing-box/
├── config.json           # sing-box configuration (mode: 600)
└── client-info.txt       # Client connection parameters

/var/backups/sbx/
└── *.tar.gz[.enc]        # Backup archives (optional)

/var/lib/sing-box/acme/
└── ...                   # ACME certificate data (when using domain)

/etc/systemd/system/
└── sing-box.service      # systemd service unit
```

---

### 9. Module Loading & Bootstrap Sequence

Detailed view of the bootstrap phase before module loading begins.

```
  Script start (set -euo pipefail)
       │
       ▼
  ┌──────────────────────────────────────────┐
  │  Phase 1: Early Constants (readonly)     │
  │                                          │
  │  DOWNLOAD_CONNECT_TIMEOUT_SEC=10         │
  │  DOWNLOAD_MAX_TIMEOUT_SEC=30             │
  │  HTTP_DOWNLOAD_TIMEOUT_SEC=30            │
  │  REALITY_SHORT_ID_MIN_LENGTH=1           │
  │  REALITY_SHORT_ID_MAX_LENGTH=8           │
  │  REALITY_PORT_DEFAULT=443                │
  │  REALITY_FLOW_VISION="xtls-rprx-vision"  │
  │  ... (defined with readonly)             │
  └──────────────────────┬───────────────────┘
                         │
                         ▼
  ┌──────────────────────────────────────────┐
  │  Phase 2: Bootstrap Helpers              │
  │                                          │
  │  get_file_size()    ← overridden later   │
  │  create_temp_dir()  ← overridden later   │
  │  _print_help()                           │
  └──────────────────────┬───────────────────┘
                         │
                         ▼
  ┌──────────────────────────────────────────┐
  │  Phase 3: Module Loading                 │
  │                                          │
  │  _load_modules()                         │
  │    ├── lib/ exists locally?              │
  │    │   ├── Yes → source from local dir   │
  │    │   └── No (one-liner install):       │
  │    │       ├── Download modules (parallel)│
  │    │       └── Fallback to sequential    │
  │    │                                     │
  │    ├── Validate module names (whitelist) │
  │    ├── source each .sh in order          │
  │    └── _verify_module_apis()             │
  │          └── Check required functions    │
  │              exist per module contract   │
  └──────────────────────┬───────────────────┘
                         │
                         ▼
  ┌──────────────────────────────────────────┐
  │  Phase 4: Execution                      │
  │                                          │
  │  main() → install_flow() or              │
  │            uninstall_flow()              │
  └──────────────────────────────────────────┘
```

**Why bootstrap constants exist:**
Constants like `REALITY_SHORT_ID_MAX_LENGTH` are used by `lib/validation.sh`
which loads during Phase 3. If these were defined only in `lib/common.sh`,
they would be unavailable when validation functions are first parsed.
The bootstrap section in `install.sh` (lines 16-66) ensures these constants
are available before any module is sourced.

---

### 10. sing-box Configuration Structure

The JSON structure generated by `write_config()`.

```
/etc/sing-box/config.json
│
├── log
│   └── level: "warn"
│
├── dns
│   ├── servers: [{ type: "local", tag: "dns-local" }]
│   └── strategy: "ipv4_only"          ← if no IPv6
│
├── inbounds[]
│   │
│   ├── [0] VLESS-Reality              ← ENABLE_REALITY=1
│   │   ├── type: "vless"
│   │   ├── listen: "::", listen_port: 443
│   │   ├── users: [{ uuid, flow: "xtls-rprx-vision" }]
│   │   └── tls:
│   │       ├── enabled: true
│   │       ├── server_name: "www.microsoft.com"
│   │       └── reality:
│   │           ├── enabled: true
│   │           ├── private_key: "..."
│   │           ├── short_id: ["a1b2c3d4"]    ← 8 chars max
│   │           └── handshake: { server, port: 443 }
│   │
│   ├── [1] VLESS-WS-TLS              ← ENABLE_WS=1 + domain
│   │   ├── type: "vless"
│   │   ├── listen: "::", listen_port: 8444
│   │   ├── users: [{ uuid }]
│   │   ├── transport: { type: "ws", path: "/ws" }
│   │   └── tls:
│   │       ├── enabled: true
│   │       ├── server_name: "domain.com"
│   │       └── acme / certificate + key
│   │
│   └── [2] Hysteria2                  ← ENABLE_HY2=1 + domain
│       ├── type: "hysteria2"
│       ├── listen: "::", listen_port: 8443
│       ├── users: [{ password }]
│       └── tls:
│           ├── enabled: true
│           ├── alpn: ["h3"]
│           └── acme / certificate + key
│
├── outbounds[]
│   └── [0] { type: "direct", tag: "direct" }
│
└── route
    └── rules:
        ├── { action: "sniff" }
        └── { action: "hijack-dns" }
```
