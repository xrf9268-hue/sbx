# 计划：sbx 适配 sing-box 1.13.0

## Context

sing-box 官方发布 1.13.0，sbx 当前以 1.12.0 为推荐版本、1.8.0 为最低版本。通过分析 1.13.0 源码 `deprecated/constants.go`，确认了多项废弃特性。同时 1.13.0 新增原生 ACME DNS-01 支持（Cloudflare/AliDNS/ACME-DNS），可完全替代当前的 Caddy 证书方案，大幅简化架构。

**目标**：
1. 最低版本提升至 1.13.0
2. 移除废弃特性（block outbound 等）
3. 用 sing-box 原生 ACME 替代 Caddy，消除外部依赖

**参考资料**：
- [sing-box 1.13.0 Release Notes](https://github.com/SagerNet/sing-box/releases/tag/v1.13.0)
- [sing-box Changelog](https://sing-box.sagernet.org/changelog/)
- [sing-box Migration Guide](https://sing-box.sagernet.org/migration/)
- [sing-box Deprecated Features](https://sing-box.sagernet.org/deprecated/)
- [sing-box DNS-01 Challenge Docs](https://sing-box.sagernet.org/configuration/shared/dns01_challenge/)
- [sing-box TLS Configuration](https://sing-box.sagernet.org/configuration/shared/tls/)

---

## 一、移除废弃特性

### 1.1 移除 `block` outbound

**问题**：`OptionSpecialOutbounds` 在 1.11.0 废弃，scheduled removal 1.13.0。使用时会产生告警日志。

**修改** `lib/config.sh:91-92`：
```bash
# 前：
outbounds: [
  { type: "direct", tag: "direct" },
  { type: "block", tag: "block" }      # ← 移除
]
# 后：
outbounds: [
  { type: "direct", tag: "direct" }
]
```

**涉及文件**：
- `lib/config.sh:92` — 移除 block outbound
- `tests/unit/test_config_validator.sh:314` — 更新测试

### 1.2 更新版本常量

**修改** `lib/version.sh:376-377`：
```bash
# 前：
local min_version="1.8.0"
local recommended_version="1.12.0"
# 后：
local min_version="1.13.0"
local recommended_version="1.13.0"
```

**涉及文件**：
- `lib/version.sh:376-377`
- `README.md` — badge 版本 `1.12.0+` → `1.13.0+`
- `CLAUDE.md` — 版本引用更新
- `.claude/REALITY_CONFIG.md` — "sing-box 1.12.0+" → "sing-box 1.13.0+"

### 1.3 清理 outbound 冗余字段

**修改** `lib/config.sh:343-349`：
```bash
# 前：包含 bind_interface:"", routing_mark:0, reuse_addr:false 等零值
# 后：仅保留有实际意义的字段
.outbounds[0] += {
  "connect_timeout": "5s",
  "tcp_fast_open": true,
  "udp_fragment": true
}
```

---

## 二、sing-box 原生 ACME 替代 Caddy（核心重构）

### 2.1 架构变更概览

**当前架构**（依赖 Caddy）：
```
Caddy 二进制下载/安装 → Caddy 监听 80 端口 → ACME HTTP-01/DNS-01
→ 证书同步到 /etc/ssl/sbx/{domain}/ → sing-box 读取文件路径
→ caddy-cert-sync.timer 定期续期
```

**新架构**（sing-box 原生）：
```
sing-box TLS inbound 配置 acme 块 → sing-box 内部处理 ACME
→ 证书自动管理（内存/data_directory）→ 无需外部依赖
```

### 2.2 配置生成变更

#### HTTP-01 模式（CERT_MODE=caddy → 重命名为 CERT_MODE=acme）

WS-TLS inbound TLS 配置从文件路径改为 ACME 块：
```json
"tls": {
  "enabled": true,
  "server_name": "your.domain.com",
  "alpn": ["h2", "http/1.1"],
  "acme": {
    "domain": ["your.domain.com"],
    "data_directory": "/var/lib/sing-box/acme",
    "email": "",
    "provider": "letsencrypt",
    "disable_tls_alpn_challenge": true
  }
}
```

#### DNS-01 模式（CERT_MODE=cf_dns）

```json
"tls": {
  "enabled": true,
  "server_name": "your.domain.com",
  "alpn": ["h2", "http/1.1"],
  "acme": {
    "domain": ["your.domain.com"],
    "data_directory": "/var/lib/sing-box/acme",
    "email": "",
    "provider": "letsencrypt",
    "disable_http_challenge": true,
    "disable_tls_alpn_challenge": true,
    "dns01_challenge": {
      "provider": "cloudflare",
      "api_token": "$CF_API_TOKEN"
    }
  }
}
```

#### Hysteria2 inbound

同样使用 ACME 块（sing-box 内部缓存证书，不会重复请求）：
```json
"tls": {
  "enabled": true,
  "alpn": ["h3"],
  "acme": {
    "domain": ["your.domain.com"],
    "data_directory": "/var/lib/sing-box/acme",
    "provider": "letsencrypt",
    "disable_http_challenge": true,
    "disable_tls_alpn_challenge": true,
    "dns01_challenge": { ... }
  }
}
```

### 2.3 需要修改的文件

| 文件 | 变更 | 复杂度 |
|------|------|--------|
| `lib/config.sh` | `create_ws_inbound()` 和 `create_hysteria2_inbound()` 改用 acme 块替代 cert_path/key_path | 高 |
| `lib/certificate.sh` | 大幅简化：移除 Caddy 调用，仅保留 cert_mode 解析和 ACME 参数传递 | 中 |
| `lib/caddy.sh` | **整个文件可移除**（790行） | 删除 |
| `install.sh` | 移除 Caddy bootstrap 常量（行49-52）、移除 caddy 模块加载、简化 install_flow | 中 |
| `lib/common.sh` | 移除 `CERT_DIR_BASE`、`CADDY_*` 常量 | 低 |
| `lib/validation.sh` | `validate_cf_api_token()` 保留，移除 Caddy 相关验证 | 低 |
| `tests/unit/test_caddy_*.sh` | **4个测试文件可移除**，新增 ACME 配置生成测试 | 中 |

### 2.4 环境变量变更

| 变量 | 变更 |
|------|------|
| `CERT_MODE=caddy` | 重命名为 `CERT_MODE=acme`（保持 `caddy` 为兼容别名并告警） |
| `CERT_MODE=cf_dns` | 保留，改为通过 sing-box dns01_challenge 实现 |
| `CF_API_TOKEN` | 保留，直接传入 sing-box ACME 配置 |
| `CERT_FULLCHAIN` / `CERT_KEY` | 仍支持手动指定证书路径（跳过 ACME） |
| `CADDY_HTTP_PORT_DEFAULT` 等 | **移除** |

### 2.5 向后兼容

- `CERT_MODE=caddy` 仍可工作（映射为 `acme` 并打印迁移告警）
- 手动指定 `CERT_FULLCHAIN` + `CERT_KEY` 的用户不受影响
- 已安装 Caddy 的系统：卸载流程保留 `caddy_uninstall()` 作为迁移工具

### 2.6 卸载考虑

保留一个精简的 Caddy 清理函数（可从 sbx 管理命令调用），用于升级时清理旧 Caddy 安装：
- 停止并移除 caddy.service
- 停止并移除 caddy-cert-sync.service/timer
- 移除 /usr/local/bin/caddy
- 移除 /usr/local/etc/caddy/

---

## 三、文档更新

### 3.1 版本引用

所有文档中的 `1.12.0+` 更新为 `1.13.0+`：
- `README.md` — badge、requirements
- `CLAUDE.md` — Reality protocol 部分
- `.claude/REALITY_CONFIG.md` — 全文
- `.claude/ARCHITECTURE.md` — 模块列表（移除 caddy.sh）
- `CONTRIBUTING.md` — 相关引用
- `docs/REALITY_TROUBLESHOOTING.md` — 版本引用

### 3.2 uTLS 安全告警

在 `docs/REALITY_BEST_PRACTICES.md` 添加：
> ⚠️ sing-box 1.13.0 官方警告：uTLS 存在反复发现的指纹漏洞，不推荐用于对抗深度审查。如需 TLS 指纹抗性，建议使用 NaiveProxy。Reality 协议本身的安全性不受影响。

### 3.3 ACME 文档

更新 `docs/ADVANCED.md`：
- 说明新的 ACME 原生方案（无需 Caddy）
- DNS-01 配置示例
- 支持的 DNS 提供商列表（Cloudflare、AliDNS、ACME-DNS）

---

## 四、实施步骤（按阶段）

### Phase 1: 基础兼容性（低风险，可独立完成）
1. 更新 `lib/version.sh` — min_version=1.13.0
2. 移除 `lib/config.sh` 中的 `block` outbound
3. 清理 outbound 冗余字段
4. 更新相关测试
5. 更新文档版本引用

**验证**：`bash tests/test-runner.sh unit` + ShellCheck

### Phase 2: ACME 重构（核心变更，需充分测试）
6. 修改 `lib/config.sh` — `create_ws_inbound()` 和 `create_hysteria2_inbound()` 支持 ACME 块
7. 重写 `lib/certificate.sh` — 移除 Caddy 调用，改为 ACME 参数解析
8. 创建 `lib/caddy_cleanup.sh`（精简版，仅保留卸载函数）
9. 移除 `lib/caddy.sh`（790行）
10. 更新 `install.sh` — 移除 Caddy 常量和模块引用

**验证**：生成配置 dry-run + `sing-box check` + 实际安装测试

### Phase 3: 测试完善
11. 新增 ACME 配置生成单元测试
12. 更新现有测试（bootstrap constants 等）
13. 移除旧 Caddy 测试文件

**验证**：全量单元测试通过

### Phase 4: 文档与清理
14. 更新 ADVANCED.md ACME 文档
15. 添加 uTLS 安全告警
16. 更新 ARCHITECTURE.md 模块列表
17. 清理临时兼容代码

---

## 五、验证方案

```bash
# 1. 单元测试
bash tests/test-runner.sh unit

# 2. Bootstrap 常量验证
bash tests/unit/test_bootstrap_constants.sh

# 3. 生成配置检查（dry-run）
# 验证生成的 JSON 包含 acme 块而非 certificate_path
DOMAIN=test.example.com DEBUG=1 bash install.sh 2>&1 | head -50

# 4. sing-box 配置语法验证
sing-box check -c /etc/sing-box/config.json

# 5. 验证无废弃告警
sing-box check -c /etc/sing-box/config.json 2>&1 | grep -i deprecat

# 6. 验证配置结构
jq '.outbounds | map(.type)' /etc/sing-box/config.json
# 期望: ["direct"]（不含 "block"）

jq '.inbounds[] | select(.tag == "in-ws") | .tls.acme' /etc/sing-box/config.json
# 期望: 包含 acme 配置

# 7. ShellCheck
shellcheck lib/config.sh lib/version.sh lib/certificate.sh

# 8. Strict mode
bash -u install.sh --help
```

---

## 六、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| sing-box ACME 行为与 Caddy 不同 | 证书签发失败 | 保留 CERT_FULLCHAIN/CERT_KEY 手动模式作为 fallback |
| 已安装用户升级 | Caddy 残留 | 提供 caddy_cleanup 迁移工具 |
| HTTP-01 端口冲突 | sing-box 占用 80 端口 | 使用 `alternative_http_port` 或推荐 DNS-01 |
| ACME data_directory 权限 | 证书存储失败 | install 时创建目录并设置权限 |

---

## 七、1.13.0 新特性总览

| 特性 | 说明 | 潜在价值 | 状态 |
|------|------|----------|------|
| kTLS (`kernel_tx`) | Linux 5.1+ TLS 1.3 内核级卸载 | 性能提升 | ✅ 已实施（auto-detect） |
| `bind_address_no_port` | 高并发场景端口复用 | 性能提升 | ✅ 已实施 |
| Chrome Root Store | `certificate.store: "chrome"` | 安全增强 | ✅ 已实施（ACME 模式） |
| `tcp_keep_alive` | 新增连接参数（默认 keep-alive 从 10m 改为 5m） | 连接优化 | ✅ 已实施（显式 5m） |
| NaiveProxy outbound | QUIC + ECH 支持 | 新协议选项 | 未实施 |
| ICMP echo proxy | ping 代理支持 | 功能扩展 | 未实施 |
| `preferred_by` rule item | 匹配 outbound 首选路由 | 路由灵活性 | 未实施 |
| Wi-Fi state 规则 | Linux 上的 wifi_ssid/wifi_bssid 匹配 | 条件路由 | 未实施 |
| CCM/OCM service | Claude Code / OpenAI Codex 远程复用 | 开发工具 | 未实施 |
