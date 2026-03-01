# Architecture Diagrams

Visual architecture reference for sbx-lite. All diagrams use Mermaid syntax
and render on GitHub.

**See also:** [.claude/ARCHITECTURE.md](../.claude/ARCHITECTURE.md) for the
complete module list and ASCII diagrams.

---

## Table of Contents

1. [Module Dependency Architecture](#1-module-dependency-architecture)
2. [Installation Flow](#2-installation-flow)
3. [Protocol Mode Decision Tree](#3-protocol-mode-decision-tree)
4. [Configuration Generation Flow](#4-configuration-generation-flow)
5. [Backup & Restore Flow](#5-backup--restore-flow)
6. [Client Export Flow](#6-client-export-flow)
7. [Module Loading & Bootstrap Sequence](#7-module-loading--bootstrap-sequence)
8. [sing-box Configuration Structure](#8-sing-box-configuration-structure)

---

## 1. Module Dependency Architecture

Module loading order and functional grouping. All 21 modules are loaded
sequentially by `_load_modules()` in `install.sh`.

```mermaid
graph TB
    subgraph Entry["install.sh (Entry Point)"]
        MAIN["main()"]
        BOOT["Early Constants<br/>Bootstrap Helpers"]
        LOAD["_load_modules()"]
        VERIFY["_verify_module_apis()"]
    end

    BOOT --> LOAD
    LOAD --> VERIFY
    VERIFY --> MAIN

    subgraph L1["Layer 1: Core (loaded first)"]
        colors["colors.sh<br/><i>Terminal colors</i>"]
        common["common.sh<br/><i>Utilities, constants</i>"]
        logging["logging.sh<br/><i>Structured logging</i>"]
        generators["generators.sh<br/><i>UUID, keypair, SID</i>"]
        tools["tools.sh<br/><i>Tool detection</i>"]
    end

    subgraph L2["Layer 2: Infrastructure"]
        retry["retry.sh<br/><i>Exponential backoff</i>"]
        download["download.sh<br/><i>Binary download</i>"]
        network["network.sh<br/><i>IP detect, ports</i>"]
        validation["validation.sh<br/><i>Input sanitization</i>"]
        checksum["checksum.sh<br/><i>SHA256 verify</i>"]
        version["version.sh<br/><i>Version compare</i>"]
        certificate["certificate.sh<br/><i>ACME params</i>"]
        caddy_cleanup["caddy_cleanup.sh<br/><i>Legacy migration</i>"]
    end

    subgraph L3["Layer 3: Business Logic (loaded last)"]
        config["config.sh<br/><i>JSON config gen</i>"]
        config_validator["config_validator.sh<br/><i>Config rules</i>"]
        schema_validator["schema_validator.sh<br/><i>JSON schema</i>"]
        service["service.sh<br/><i>systemd mgmt</i>"]
        ui["ui.sh<br/><i>Interactive UI</i>"]
        backup["backup.sh<br/><i>Backup/restore</i>"]
        export["export.sh<br/><i>URI/Clash/QR</i>"]
        messages["messages.sh<br/><i>Message templates</i>"]
    end

    LOAD --> colors
    colors --> common
    common --> logging
    logging --> generators
    generators --> tools
    tools --> retry
    retry --> download
    download --> network
    network --> validation
    validation --> checksum
    checksum --> version
    version --> certificate
    certificate --> caddy_cleanup
    caddy_cleanup --> config
    config --> config_validator
    config_validator --> schema_validator
    schema_validator --> service
    service --> ui
    ui --> backup
    backup --> export
    export --> messages

    %% Key dependency arrows
    colors -.->|"provides colors"| logging
    common -.->|"provides die/msg"| config
    retry -.->|"provides backoff"| download
    validation -.->|"provides checks"| config
    generators -.->|"provides UUID/keys"| config

    style L1 fill:#e8f5e9,stroke:#4caf50
    style L2 fill:#e3f2fd,stroke:#2196f3
    style L3 fill:#fff3e0,stroke:#ff9800
    style Entry fill:#f3e5f5,stroke:#9c27b0
```

---

## 2. Installation Flow

Complete flow from `bash install.sh` to running service.

```mermaid
flowchart TD
    START(["bash install.sh"]) --> MAIN["main()"]

    MAIN --> UNINSTALL_CHECK{"arg == uninstall?"}
    UNINSTALL_CHECK -->|Yes| UNINSTALL_FLOW
    UNINSTALL_CHECK -->|No| INSTALL_FLOW

    subgraph UNINSTALL_FLOW["Uninstall Flow"]
        U1["show_logo()"] --> U2["need_root()"]
        U2 --> U3["Confirm removal"]
        U3 --> U4["stop_service()"]
        U4 --> U5["remove_service()"]
        U5 --> U6["Remove files & dirs"]
        U6 --> U7["Remove legacy Caddy"]
    end

    subgraph INSTALL_FLOW["Install Flow"]
        direction TB
        I1["show_logo()"] --> I2["need_root()"]
        I2 --> I3{"DOMAIN set?"}
        I3 -->|Yes| I3a["validate_env_vars()"]
        I3 -->|No| I4
        I3a --> I4

        I4["check_existing_installation()"]
        I4 --> I4a{"Existing install?"}
        I4a -->|No| I5
        I4a -->|Yes| I4b["Interactive Menu"]
        I4b -->|"Fresh install"| I5
        I4b -->|"Upgrade binary"| I5_SKIP["SKIP_CONFIG_GEN=1"]
        I4b -->|"Reconfigure"| I5_RECONF["SKIP_BINARY=1"]
        I4b -->|"Uninstall"| UNINSTALL_FLOW

        I5["ensure_tools()"] --> I6["download_singbox()"]
        I5_SKIP --> I5
        I5_RECONF --> I5

        subgraph DL["Binary Download"]
            I6 --> I6a["detect_arch()"]
            I6a --> I6b["detect_libc()"]
            I6b --> I6c["resolve_singbox_version()"]
            I6c --> I6d["GitHub API → download"]
            I6d --> I6e["verify_singbox_binary()<br/>SHA256 checksum"]
            I6e --> I6f["Install to /usr/local/bin/"]
        end

        I6f --> I7{"SKIP_CONFIG_GEN?"}
        I7 -->|Yes| I7_RESTART["restart_service()"]
        I7 -->|No| GEN_MAT

        subgraph GEN_MAT["gen_materials()"]
            G1["_configure_server_address()"]
            G1 --> G2["_configure_cloudflare_mode()"]
            G2 --> G3["_validate_protocol_config()"]
            G3 --> G4["_generate_credentials()<br/>UUID + keypair + SID"]
            G4 --> G5["_allocate_ports()"]
        end

        GEN_MAT --> I8{"REALITY_ONLY?"}
        I8 -->|No| I8a["maybe_issue_cert()"]
        I8 -->|Yes| I9
        I8a --> I9

        I9["write_config()"] --> I10["setup_service()"]
        I10 --> I11["save_client_info()"]
        I11 --> I12["install_manager_script()"]
        I12 --> I13["open_firewall()"]
        I13 --> I14["print_summary()"]
    end

    I14 --> DONE(["Installation Complete"])
    I7_RESTART --> DONE
    U7 --> DONE_U(["Uninstall Complete"])

    style START fill:#4caf50,color:#fff
    style DONE fill:#4caf50,color:#fff
    style DONE_U fill:#f44336,color:#fff
    style DL fill:#e3f2fd,stroke:#2196f3
    style GEN_MAT fill:#fff3e0,stroke:#ff9800
```

---

## 3. Protocol Mode Decision Tree

How environment variables determine which protocols get enabled.

```mermaid
flowchart TD
    START(["bash install.sh"]) --> DOMAIN_CHECK{"DOMAIN set?"}

    DOMAIN_CHECK -->|"No / IP address"| REALITY_ONLY
    DOMAIN_CHECK -->|"Yes (domain name)"| CF_CHECK

    subgraph REALITY_ONLY["Reality-Only Mode"]
        R1["REALITY_ONLY_MODE=1"]
        R2["Reality: ON (port 443)"]
        R3["WS-TLS: OFF"]
        R4["Hy2: OFF"]
        R5["No certificates needed"]
        R1 --- R2 --- R3 --- R4 --- R5
    end

    CF_CHECK{"CF_MODE=1?"}
    CF_CHECK -->|No| STANDARD
    CF_CHECK -->|Yes| CF_MODE

    subgraph STANDARD["Standard Multi-Protocol"]
        S1["REALITY_ONLY_MODE=0"]
        S2["Reality: ON (port 443)"]
        S3["WS-TLS: ON (port 8444)"]
        S4["Hy2: ON (port 8443/UDP)"]
        S1 --- S2 --- S3 --- S4
    end

    subgraph CF_MODE["Cloudflare Proxy Mode"]
        C1["Reality: OFF"]
        C2["WS-TLS: ON (port 443)"]
        C3["Hy2: OFF"]
        C4["Traffic via CF CDN"]
        C1 --- C2 --- C3 --- C4
    end

    STANDARD --> CERT_CHECK{"CERT_MODE?"}
    CF_MODE --> CERT_CHECK

    CERT_CHECK -->|"not set"| ACME_HTTP["Native ACME (HTTP-01)<br/>Requires port 80"]
    CERT_CHECK -->|"cf_dns"| ACME_DNS["DNS-01 via CF API<br/>No port 80 needed"]

    style REALITY_ONLY fill:#e8f5e9,stroke:#4caf50
    style STANDARD fill:#e3f2fd,stroke:#2196f3
    style CF_MODE fill:#fff3e0,stroke:#ff9800
    style ACME_HTTP fill:#f3e5f5,stroke:#9c27b0
    style ACME_DNS fill:#fce4ec,stroke:#e91e63
```

---

## 4. Configuration Generation Flow

How `write_config()` assembles the sing-box JSON configuration.

```mermaid
flowchart TD
    WC(["write_config()"]) --> IPV6["detect_ipv6_support()"]
    IPV6 --> LISTEN["choose_listen_address()<br/>→ '::' (dual-stack)"]
    LISTEN --> VALIDATE["validate_config_vars()<br/>Check UUID, PRIV, SID, ports"]
    VALIDATE --> CERT_VAL["_validate_certificate_config()"]

    CERT_VAL --> BASE["create_base_config()"]

    subgraph BASE_CONFIG["Base Config (jq -n)"]
        BC1["log: { level: warn }"]
        BC2["dns: { servers, strategy }"]
        BC3["inbounds: [ ]"]
        BC4["outbounds: [ ]"]
        BC5["route: { }"]
    end
    BASE --> BASE_CONFIG

    BASE_CONFIG --> INBOUNDS["_create_all_inbounds()"]

    INBOUNDS --> REALITY_CHECK{"ENABLE_REALITY=1?"}
    REALITY_CHECK -->|Yes| REALITY_IN["create_reality_inbound()<br/>VLESS + Reality TLS"]
    REALITY_CHECK -->|No| TLS_CHECK

    REALITY_IN --> TLS_CHECK{"TLS available?<br/>(certs or ACME)"}

    TLS_CHECK -->|No| ROUTE
    TLS_CHECK -->|Yes| WS_CHECK

    WS_CHECK{"ENABLE_WS=1?"}
    WS_CHECK -->|Yes| WS_TLS["_build_tls_block()<br/>create_ws_inbound()"]
    WS_CHECK -->|No| HY2_CHECK

    WS_TLS --> HY2_CHECK{"ENABLE_HY2=1?"}
    HY2_CHECK -->|Yes| HY2["_build_tls_block()<br/>create_hysteria2_inbound()"]
    HY2_CHECK -->|No| ROUTE

    HY2 --> ROUTE["add_route_config()<br/>sniff + hijack-dns"]
    ROUTE --> OUTBOUND["add_outbound_config()<br/>direct outbound"]

    OUTBOUND --> PIPELINE["validate_config_pipeline()"]

    subgraph VALIDATION["Validation Pipeline"]
        V1["JSON syntax (jq)"]
        V2["Schema validation"]
        V3["Config rules check"]
        V4["sing-box check"]
        V1 --> V2 --> V3 --> V4
    end
    PIPELINE --> VALIDATION

    VALIDATION --> ATOMIC["Atomic mv →<br/>/etc/sing-box/config.json<br/>(permissions: 600)"]

    style WC fill:#4caf50,color:#fff
    style BASE_CONFIG fill:#e3f2fd,stroke:#2196f3
    style VALIDATION fill:#fff3e0,stroke:#ff9800
    style ATOMIC fill:#e8f5e9,stroke:#4caf50
```

---

## 5. Backup & Restore Flow

How `sbx backup create` and `sbx backup restore` work.

```mermaid
flowchart TD
    subgraph CREATE["sbx backup create [--encrypt]"]
        BC1["backup_create()"] --> BC2["Collect files"]

        subgraph FILES["Backup Contents"]
            F1["/etc/sing-box/config.json"]
            F2["/etc/sing-box/client-info.txt"]
            F3["/usr/local/lib/sbx/*.sh"]
        end
        BC2 --> FILES

        FILES --> BC3["Create tar.gz archive<br/>/var/backups/sbx/"]
        BC3 --> BC4{"--encrypt?"}
        BC4 -->|Yes| BC5["openssl enc -aes-256-cbc<br/>→ .tar.gz.enc"]
        BC4 -->|No| BC6["Verify archive integrity"]
        BC5 --> BC6
    end

    subgraph RESTORE["sbx backup restore <file>"]
        BR1["backup_restore()"] --> BR2["_validate_backup_archive()"]
        BR2 --> BR3{"Encrypted?"}
        BR3 -->|Yes| BR4["_decrypt_backup()<br/>(password prompt)"]
        BR3 -->|No| BR5
        BR4 --> BR5["_prepare_rollback()<br/>Snapshot current config"]
        BR5 --> BR6["Extract → temp dir"]
        BR6 --> BR7["_apply_restored_config()<br/>sing-box check + copy"]
        BR7 --> BR8["_restore_service_state()<br/>restart + verify"]
        BR8 --> BR9{"Success?"}
        BR9 -->|Yes| BR10(["Restore Complete"])
        BR9 -->|No| BR11["Rollback to snapshot"]
    end

    style CREATE fill:#e8f5e9,stroke:#4caf50
    style RESTORE fill:#e3f2fd,stroke:#2196f3
    style FILES fill:#fff3e0,stroke:#ff9800
```

---

## 6. Client Export Flow

How `sbx info` and `sbx export` generate client configurations.

```mermaid
flowchart LR
    CMD["sbx info / export"] --> LOAD["load_client_info()<br/>Parse client-info.txt"]

    LOAD --> FMT{"Export format?"}

    FMT -->|"info / uri"| URI["export_uri()"]
    FMT -->|"clash"| CLASH["export_clash_yaml()"]
    FMT -->|"qr"| QR["export_qr_codes()"]
    FMT -->|"sub"| SUB["export_subscription()"]

    subgraph URI_OUT["URI Output"]
        U1["vless://UUID@IP:443?<br/>security=reality&..."]
        U2["vless://UUID@DOMAIN:8444?<br/>type=ws&security=tls&..."]
        U3["hysteria2://PASS@DOMAIN:8443?<br/>..."]
    end

    URI --> URI_OUT
    CLASH --> CLASH_OUT["Clash Meta<br/>YAML config"]
    QR --> QR_OUT["Terminal<br/>QR codes"]
    SUB --> SUB_OUT["Base64-encoded<br/>URI list"]

    style CMD fill:#4caf50,color:#fff
    style URI_OUT fill:#e3f2fd,stroke:#2196f3
```

---

## 7. Module Loading & Bootstrap Sequence

Detailed view of the four-phase bootstrap process.

```mermaid
flowchart TD
    START(["Script Start<br/>set -euo pipefail"]) --> P1

    subgraph P1["Phase 1: Early Constants"]
        C1["readonly DOWNLOAD_CONNECT_TIMEOUT_SEC=10"]
        C2["readonly REALITY_SHORT_ID_MAX_LENGTH=8"]
        C3["readonly REALITY_PORT_DEFAULT=443"]
        C4["readonly REALITY_FLOW_VISION='xtls-rprx-vision'"]
        C5["... (defined before any module loads)"]
        C1 --- C2 --- C3 --- C4 --- C5
    end

    P1 --> P2

    subgraph P2["Phase 2: Bootstrap Helpers"]
        H1["get_file_size() ← overridden by common.sh"]
        H2["create_temp_dir() ← overridden by common.sh"]
        H3["_print_help()"]
        H1 --- H2 --- H3
    end

    P2 --> P3

    subgraph P3["Phase 3: Module Loading"]
        ML1{"lib/ exists locally?"}
        ML1 -->|Yes| ML4["Source from local dir"]
        ML1 -->|"No (one-liner)"| ML2["Download modules"]
        ML2 --> ML2a{"Parallel download?"}
        ML2a -->|Yes| ML2b["xargs -P 5"]
        ML2a -->|No| ML2c["Sequential download"]
        ML2b -->|Fail| ML2c
        ML2b -->|OK| ML3
        ML2c --> ML3["Validate module names<br/>(whitelist: a-z_)"]
        ML4 --> ML3
        ML3 --> ML5["source each .sh in order<br/>(20 modules)"]
        ML5 --> ML6["_verify_module_apis()<br/>Check function contracts"]
    end

    P3 --> P4

    subgraph P4["Phase 4: Execution"]
        E1["main() → install_flow()<br/>or uninstall_flow()"]
    end

    style P1 fill:#e8f5e9,stroke:#4caf50
    style P2 fill:#e3f2fd,stroke:#2196f3
    style P3 fill:#fff3e0,stroke:#ff9800
    style P4 fill:#f3e5f5,stroke:#9c27b0
```

---

## 8. sing-box Configuration Structure

The JSON structure generated by `write_config()`.

```mermaid
graph TD
    ROOT["config.json"] --> LOG["log"]
    ROOT --> DNS["dns"]
    ROOT --> INBOUNDS["inbounds[]"]
    ROOT --> OUTBOUNDS["outbounds[]"]
    ROOT --> ROUTE["route"]

    LOG --> LOG_LEVEL["level: 'warn'"]

    DNS --> DNS_SERVERS["servers: [local]"]
    DNS --> DNS_STRATEGY["strategy: 'ipv4_only'<br/><i>(if no IPv6)</i>"]

    INBOUNDS --> IN0["[0] VLESS-Reality"]
    INBOUNDS --> IN1["[1] VLESS-WS-TLS"]
    INBOUNDS --> IN2["[2] Hysteria2"]

    subgraph REALITY["VLESS-Reality Inbound"]
        IN0 --> R_TYPE["type: vless"]
        IN0 --> R_LISTEN["listen: '::', port: 443"]
        IN0 --> R_USERS["users: [{uuid, flow: xtls-rprx-vision}]"]
        IN0 --> R_TLS["tls"]
        R_TLS --> R_ENABLED["enabled: true"]
        R_TLS --> R_SNI["server_name: 'www.microsoft.com'"]
        R_TLS --> R_REALITY["reality"]
        R_REALITY --> RR_ENABLED["enabled: true"]
        R_REALITY --> RR_PRIV["private_key: '...'"]
        R_REALITY --> RR_SID["short_id: ['a1b2c3d4']<br/><i>(8 chars max)</i>"]
        R_REALITY --> RR_HS["handshake: {server, port: 443}"]
    end

    subgraph WS["VLESS-WS-TLS Inbound"]
        IN1 --> W_TYPE["type: vless"]
        IN1 --> W_LISTEN["listen: '::', port: 8444"]
        IN1 --> W_USERS["users: [{uuid}]"]
        IN1 --> W_TRANSPORT["transport: {type: ws, path: /ws}"]
        IN1 --> W_TLS["tls: {acme or cert paths}"]
    end

    subgraph HY2["Hysteria2 Inbound"]
        IN2 --> H_TYPE["type: hysteria2"]
        IN2 --> H_LISTEN["listen: '::', port: 8443"]
        IN2 --> H_USERS["users: [{password}]"]
        IN2 --> H_TLS["tls: {alpn: [h3], acme or certs}"]
    end

    OUTBOUNDS --> OUT0["[0] {type: direct, tag: direct}"]

    ROUTE --> RULES["rules"]
    RULES --> RULE1["action: sniff"]
    RULES --> RULE2["action: hijack-dns"]

    style REALITY fill:#e8f5e9,stroke:#4caf50
    style WS fill:#e3f2fd,stroke:#2196f3
    style HY2 fill:#fff3e0,stroke:#ff9800
```

---

## Quick Reference

| Diagram | Description |
|---------|-------------|
| [Module Architecture](#1-module-dependency-architecture) | 21 modules in 3 layers with load order |
| [Installation Flow](#2-installation-flow) | Full install path from start to running service |
| [Protocol Modes](#3-protocol-mode-decision-tree) | How DOMAIN/CF_MODE determine protocols |
| [Config Generation](#4-configuration-generation-flow) | How write_config() builds JSON |
| [Backup/Restore](#5-backup--restore-flow) | Backup creation and restore with rollback |
| [Client Export](#6-client-export-flow) | URI/Clash/QR code generation |
| [Bootstrap](#7-module-loading--bootstrap-sequence) | 4-phase startup sequence |
| [Config Structure](#8-sing-box-configuration-structure) | JSON layout of config.json |
