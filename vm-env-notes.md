# VM Environment Notes

仅提供 sbx 远端测试环境信息，不作为开发流程或代码来源的唯一指引。

## 使用边界

- 这份文件只说明可用 VM 环境、远端连接方式和已知测试状态。
- 不要因为这份文件默认把本地工作区当作代码真源。
- 如无额外说明，优先直接使用上游仓库：
  `https://github.com/xrf9268-hue/sbx`
- 只有在用户明确要求时，才按本地工作区同步到远端。

## 远端测试机

- host: `admin@18.217.254.125`
- ssh key: `~/.ssh/ai-polling-proxy.pem`
- remote repo: `~/sbx`
- remote OS: Debian 12 x86_64
- instance id: `i-0e19b1fcd5b8ebfcc`

## 已知状态

- VM 已 ready
- `jq` / `rsync` / `git` / `curl` 已安装
- `en_US.UTF-8` 已生成
- Debian 12 上的 bash 版本为 `5.2.15`
- `tests/unit/test_module_download.sh` 可能因 bash `5.2.15` 与本地 bash `5.2.21` 的 `bash -n` 行为差异而失败

## 测试建议

- 涉及 `install.sh`、systemd、端口、网络、Docker、integration/smoke 的验证，优先在这台 VM 上做。
- 纯文本检查或本地快测可以在本机执行。
- 不要新建 AWS 资源，除非用户明确要求。
- 如果需要 AWS CLI 登录，优先用 `aws login --region us-east-2`。

## 基础连通性检查

```bash
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  'hostname && whoami && uname -a && test -d ~/sbx && echo repo_ok || echo repo_missing'
```
