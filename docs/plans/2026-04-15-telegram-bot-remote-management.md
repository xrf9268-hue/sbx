# 实现计划：issue xrf9268-hue/sbx#105 — Telegram Bot 远程管理

## Context（背景与目标）

**Issue**：xrf9268-hue/sbx#105（enhancement / priority: low）

**问题**：sing-box Reality 管理目前只能通过 SSH + `sbx` CLI 完成。issue 提出增加 Telegram Bot 守护进程，使运维人员可在移动端或远程场景下执行常用管理操作。参考实现为 reality-ezpz。

**期望达成**：提供 `bin/sbx-telegram-bot` 守护进程，以 Telegram Bot API 长轮询接收指令，支持 `/status`、`/users`、`/adduser`、`/removeuser`、`/restart`、`/help`；提供 `sbx telegram {setup,enable,disable,status,logs,admin}` 子命令；以独立 systemd unit 与 sing-box 并行运行；附完整单元测试。

**约束**：
- 严格遵守项目「纯 bash + curl + jq，无任何语言运行时」的依赖基线；
- 模块化风格与现有 `lib/cloudflare_tunnel.sh` 保持一致（最接近的参考实现）；
- 最小可行实现（YAGNI）：只做 issue 列出的命令集，不做 webhook、inline keyboard、事件告警；
- 复用现有 `lib/users.sh` 和 `lib/service.sh` 的函数，绝不重复实现用户 CRUD 或服务重启逻辑。

---

## 架构决策要点

| 决策 | 选择 | 理由 |
|------|------|------|
| 传输方式 | **长轮询**（`getUpdates?timeout=30`） | 无需公网 TLS 端点，不占用 443/8444，单 curl 连接，近零 CPU |
| 运行用户 | **root**（与 `sing-box.service` 一致） | 需要调用 `user_add` / 重启服务；改用非 root 需要 sudoers 策略，徒增复杂度 |
| Token 存储 | **state.json 明文 + `/etc/sing-box/telegram.env`（EnvironmentFile）** | state.json 已 chmod 600/root，与 Reality 私钥、Hy2 密码一致；EnvironmentFile 防止 token 出现在 `ps` 或 `journalctl` |
| 偏移量持久化 | `/var/lib/sbx-telegram-bot/offset`（独立文件） | 热路径写入，不污染 state.json；SIGTERM trap 最终写入一次 |
| 命令分发 | 纯 `case` 匹配固定 token，参数通过位置参数传递 | 绝不 `eval` 聊天输入 |
| 鉴权 | `admin_chat_ids` 白名单（存 state.json，空列表=拒绝所有） | 聊天 ID 比用户名稳定（用户名可改） |

---

## 关键文件与变更清单

### 新增

1. **`lib/telegram_bot.sh`**（主模块，仿 `lib/cloudflare_tunnel.sh`）
   - 文件头：`set -euo pipefail` + `_SBX_TELEGRAM_BOT_LOADED` 防重复 source 守卫
   - 依赖 source：`common.sh`、`users.sh`、`service.sh`、`validation.sh`
   - 可覆盖常量（测试友好）：
     ```bash
     : "${SBX_TG_BIN:=/usr/local/bin/sbx-telegram-bot}"
     : "${SBX_TG_SVC:=/etc/systemd/system/sbx-telegram-bot.service}"
     : "${SBX_TG_ENV_FILE:=/etc/sing-box/telegram.env}"
     : "${SBX_TG_OFFSET_FILE:=/var/lib/sbx-telegram-bot/offset}"
     : "${SBX_TG_API_BASE:=https://api.telegram.org}"
     : "${SBX_TG_POLL_TIMEOUT:=30}"
     ```
   - 公共函数（API 契约）：
     - `telegram_bot_setup` — 交互式引导；调用 `getMe` 校验 token，写 state.json 和 env 文件
     - `telegram_bot_enable` — 生成 systemd unit、daemon-reload、enable+start
     - `telegram_bot_disable` — stop、disable、删除 unit、更新 state
     - `telegram_bot_status` — 显示 systemd 状态 + 白名单数量
     - `telegram_bot_logs` — `journalctl -u sbx-telegram-bot`
     - `telegram_bot_admin_add <id>` / `_remove <id>` / `_list`
     - `telegram_bot_run` — systemd `ExecStart` 目标的主循环
   - 内部函数：
     - `_tg_validate_token <token>` — 正则 `^[0-9]{8,10}:[A-Za-z0-9_-]{35}$`
     - `_tg_verify_token_live <token>` — 调用 `getMe`，解析 `.ok`
     - `_tg_is_authorized <chat_id>` — 白名单查表
     - `_tg_load_offset` / `_tg_save_offset <n>` — 单行整数，原子 rename
     - `_tg_get_updates <offset>` — `curl --max-time 40` 写到 tmpfile，指数退避（1→2→4→…→30）
     - `_tg_send_message <chat_id> <text>` — 支持 Markdown；捕获 429 `retry_after`
     - `_tg_parse_command <text>` — 返回 `cmd` 和 `args...`
     - `_tg_dispatch_command <chat_id> <cmd> [args...]` — 纯 case 分发
     - `_tg_handle_status` / `_handle_users` / `_handle_adduser` / `_handle_removeuser` / `_handle_restart` / `_handle_help` — 格式化返回
     - `_tg_update_state <key>=<value>...` — 沿用 `cloudflare_update_state` 的 mktemp→jq→chmod→mv 原子模式（参照 `lib/cloudflare_tunnel.sh:337-358`）
   - 文件末尾：`export -f` 列出所有公共函数（参照 `cloudflare_tunnel.sh` 末段）

2. **`bin/sbx-telegram-bot`**（守护进程入口，极简）
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   LIB_DIR="${LIB_DIR:-/usr/local/lib/sbx}"
   # shellcheck source=/dev/null
   source "${LIB_DIR}/telegram_bot.sh"
   trap '_tg_save_offset "${TG_LAST_OFFSET:-0}"; exit 0' TERM INT
   telegram_bot_run
   ```

3. **`tests/unit/test_telegram_bot.sh`**（单元测试）
   - 使用 `tests/test_framework.sh` 断言；必须与 `tests/unit/test_cloudflare_tunnel.sh` 风格一致
   - 测试用例：
     - `_tg_validate_token`：合法 / 非法格式
     - `_tg_is_authorized`：命中 / 未命中 / 空白名单
     - `_tg_parse_command`：`/status` / `/adduser alice` / `/adduser` 无参 / `/unknown`
     - `_tg_load_offset` / `_tg_save_offset`：round-trip + 文件不存在默认 0
     - `_tg_update_state`：enable true→false 原子转换，chmod 600 保留
     - 分发测试：通过覆盖 `_tg_send_message`（shell 函数重定义）将调用捕获到临时文件，用固定的 getUpdates JSON fixture 驱动 `_tg_dispatch_command`，断言正确 handler 被调用
     - **模块注册断言**（照搬 `tests/unit/test_cloudflare_tunnel.sh:298-309` 模式）：
       - 断言 `install.sh:509` 的 `modules=(...)` 数组包含 `telegram_bot`
       - 断言 `install.sh:660` 附近的 `module_contracts` 映射包含 `["telegram_bot"]=...`

### 修改

4. **`install.sh:509`** — 将 `telegram_bot` 追加到模块加载数组末尾

5. **`install.sh:660` 附近** — 在 `module_contracts` 映射中增加一行：
   ```bash
   ["telegram_bot"]="telegram_bot_setup telegram_bot_enable telegram_bot_disable telegram_bot_status telegram_bot_run"
   ```

6. **`bin/sbx-manager.sh`**（参照现有 `tunnel)` 分支 @ `bin/sbx-manager.sh:1353-1384`）— 在 `tunnel)` 之后、`help)` 之前插入新 `telegram)` 分支：
   ```bash
   telegram)
     case "${2:-status}" in
       setup)   need_root || exit 1; telegram_bot_setup ;;
       enable)  need_root || exit 1; telegram_bot_enable ;;
       disable) need_root || exit 1; telegram_bot_disable ;;
       status|"") telegram_bot_status ;;
       logs)    telegram_bot_logs ;;
       admin)
         case "${3:-list}" in
           add)    need_root || exit 1; telegram_bot_admin_add "${4:?chat_id}" ;;
           remove) need_root || exit 1; telegram_bot_admin_remove "${4:?chat_id}" ;;
           list|"") telegram_bot_admin_list ;;
           *) echo "Usage: sbx telegram admin {add|remove|list} [chat_id]"; exit 1 ;;
         esac ;;
       *) echo "Usage: sbx telegram {setup|enable|disable|status|logs|admin ...}"; exit 1 ;;
     esac ;;
   ```
   并在 `show_usage` 函数中追加对应帮助行。

7. **`install.sh` 安装阶段（卸载路径）** — 如果 Telegram bot 曾启用，`uninstall` 时需要 `telegram_bot_disable` + 清理 `/var/lib/sbx-telegram-bot/` 和 `/etc/sing-box/telegram.env`。定位 `sbx-manager.sh:~1185` 的 `uninstall` 分支，增加清理调用。

---

## systemd Unit 模板（由 `telegram_bot_enable` 生成）

```
[Unit]
Description=sbx-lite Telegram Bot
After=network-online.target sing-box.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sbx-telegram-bot
EnvironmentFile=-/etc/sing-box/telegram.env
Restart=on-failure
RestartSec=5s
User=root
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/etc/sing-box /var/lib/sbx-telegram-bot

[Install]
WantedBy=multi-user.target
```

说明：
- `ProtectSystem=strict` 使 `/etc` 只读，故必须声明 `ReadWritePaths=/etc/sing-box`（`sync_users_to_config` 会写 `/etc/sing-box/config.json`）。
- `User=root` 与 `lib/cloudflare_tunnel.sh:295` 的 `User=nobody` 有意不同：cloudflared 只转发流量，本 bot 需要读写 sing-box 配置和 `systemctl restart`。

---

## 鲁棒性要点（生产风险防护）

1. **长轮询网络抖动**：`_tg_get_updates` 外包一层指数退避（1s→2s→4s…上限 30s），成功则重置；避免紧密循环。
2. **Token 防泄漏**：绝不 `echo $BOT_TOKEN`；curl 调用前 `set +x`；日志中对 token 做 `sed 's/bot[0-9]*:[^/]*/bot***/g'` 脱敏。
3. **curl 响应缓冲**：`curl ... -o "${tmpfile}"` 写盘后再 `jq -f`，不走管道（避免大消息时管道阻塞）。
4. **恢复备份场景**：启动时如果 offset 文件缺失或过旧，首次 `getUpdates?offset=-1` 只取最新 update 丢弃历史，避免重放攻击。
5. **Rate limit**：`sendMessage` 返回 429 时，读取 `parameters.retry_after` 并 `sleep`，避免继续刷被封。
6. **并发写 state.json**：`users.sh` 的 `_save_users` 已用 mktemp→mv 原子写（见 `lib/users.sh:93-107`），`restart_service` 用 `with_flock`（`lib/service.sh:247`）。bot 复用这些入口，无需额外锁。
7. **`/adduser` 参数校验**：`user_add` 内部已按 `^[a-zA-Z0-9_-]+$` 校验（`lib/users.sh:154`），但 bot 仍应在调用前 trim + 拒绝含空白/控制字符的输入，并把 `user_add` 的非零返回值和 stderr 回显到 Telegram 聊天窗。

---

## 可复用的现有实现（不得重写）

| 功能 | 复用点 |
|------|--------|
| 添加用户 | `user_add "$@"` @ `lib/users.sh` |
| 列出用户（JSON） | `user_list` @ `lib/users.sh` |
| 删除用户 | `user_remove <UUID\|NAME>` @ `lib/users.sh` |
| 同步到 config | `sync_users_to_config` @ `lib/users.sh` |
| 重启 sing-box | `restart_service` @ `lib/service.sh`（已带 flock） |
| 状态查询 | `check_service_status` @ `lib/service.sh` |
| 原子更新 state.json | 仿 `cloudflared_update_state` @ `lib/cloudflare_tunnel.sh:315-358` |
| systemd unit 模板写入 | 仿 `cloudflared_write_service_file` @ `lib/cloudflare_tunnel.sh:275-309` |
| CLI 子命令分发 | 仿 `tunnel)` 分支 @ `bin/sbx-manager.sh:1353-1384` |
| 测试框架 | `tests/test_framework.sh` 的 `assert_*` |
| 模块契约测试 | 仿 `tests/unit/test_cloudflare_tunnel.sh:298-309` |

---

## 实施顺序（增量交付、每步可 `bash tests/test-runner.sh unit` 通过）

1. 脚手架 `lib/telegram_bot.sh`（仅常量 + 防重复 source 守卫 + 空函数占位 + `export -f`）
2. 在 `install.sh` 模块数组和契约表中注册 `telegram_bot`；跑 `bash tests/test-runner.sh unit` 确保未破坏
3. **TDD 先写测试**：`tests/unit/test_telegram_bot.sh` 先写「纯函数」部分（validate_token / is_authorized / parse_command / load_save_offset），然后实现这些函数，红→绿
4. 实现 `_tg_get_updates` / `_tg_send_message`（带退避和 429 处理）
5. 实现 `_tg_dispatch_command` 和各 `_handle_*` — 测试用覆盖 `_tg_send_message` 技法驱动
6. 实现 `_tg_update_state`（仿 `cloudflared_update_state`）
7. 实现 `telegram_bot_setup`、`_enable`、`_disable`、`_status`、`_logs`、`_admin_*`
8. 编写 `bin/sbx-telegram-bot` 入口（极简）
9. `bin/sbx-manager.sh` 插入 `telegram)` 分支 + 更新 `show_usage`；扩展 `uninstall` 分支清理逻辑
10. 跑全部单元套件 + `bash tests/unit/test_bootstrap_constants.sh` + `bash -u install.sh --help`
11. 编写 `docs/TELEGRAM_BOT.md` 用户指南（token 获取、setup 步骤、支持命令列表、权限模型），README.md 链接指过去

---

## 端到端验证

**单元测试**（必须全绿）：
```bash
bash tests/test-runner.sh unit
bash tests/unit/test_telegram_bot.sh
bash tests/unit/test_bootstrap_constants.sh
bash -u install.sh --help   # 确认 strict mode 下 bootstrap 正常
```

**契约测试**：
```bash
bash tests/unit/test_coverage_suite_invocations.sh   # 检查新测试被 test-runner 收录
```

**Docker 冒烟**（本地）：
```bash
bash scripts/e2e/install-lifecycle-smoke.sh
# 在容器内：
sbx telegram setup           # 输入测试 bot token 和管理员 chat id
sbx telegram enable
sbx telegram status
systemctl status sbx-telegram-bot
journalctl -u sbx-telegram-bot -n 50
# 在 Telegram 客户端向 bot 发送 /status、/users、/adduser testuser、/removeuser testuser、/restart
sbx telegram disable
```

**人工验收标准**：
- 非白名单 chat_id 发送任何命令：bot 完全静默，不回复（避免探测）
- 错误 token：`setup` 阶段 `getMe` 失败即拒绝，不落盘
- `/adduser` 重名：Telegram 回复 `user_add` 的中文错误信息
- `sbx telegram disable` 后：systemd unit 被 stop+disable+删除，offset 文件保留以便下次 enable 衔接
- `sbx uninstall`：Telegram bot 一并清理，`/var/lib/sbx-telegram-bot` 和 `/etc/sing-box/telegram.env` 被移除
