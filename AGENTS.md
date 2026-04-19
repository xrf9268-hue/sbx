# AGENTS.md

Single source of truth for coding-agent instructions in this repository.

## Scope

- Applies to the entire repository rooted at this file.
- If a deeper directory adds its own `AGENTS.md`, that closer file takes precedence for that subtree.

## Project Context

- **What**: Bash installer for sing-box with Reality protocol support and modular runtime libraries.
- **Primary entrypoint**: `install.sh`
- **Core validation path**: `bash tests/test-runner.sh unit`

## Default Development/Test Environment

- Use the existing AWS VM as the default environment for runtime validation and smoke testing.
- VM connection:
  - host: `admin@3.135.246.117`
  - ssh key: `~/.ssh/ai-polling-proxy.pem`
  - remote repo: prefer a fresh clone of `https://github.com/xrf9268-hue/sbx` in a temporary directory; do not assume `~/sbx` is a clean validation tree
  - remote OS: Debian 12 x86_64
- Default remote working copy should be a fresh clone of the upstream repository:
  `https://github.com/xrf9268-hue/sbx`
- Do not assume the local workspace is the source of truth unless the user explicitly says so.
- Do not create new AWS resources or use other machines unless the user explicitly requests it.
- Prefer the VM for changes involving `install.sh`, systemd, ports, networking, Docker, integration tests, or lifecycle/smoke behavior.
- Purely static inspection, documentation edits, and quick text-only checks can still run locally.

## Setup Commands

```bash
# Check VM connectivity
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@3.135.246.117 \
  'hostname && whoami && uname -a'

# Remote unit validation
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@3.135.246.117 \
  'workdir=$(mktemp -d /tmp/sbx-verify.XXXXXX) && trap "rm -rf \"$workdir\"" EXIT && git clone --branch main --single-branch https://github.com/xrf9268-hue/sbx "$workdir" >/dev/null 2>&1 && cd "$workdir" && bash tests/test-runner.sh unit'

ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@3.135.246.117 \
  'workdir=$(mktemp -d /tmp/sbx-verify.XXXXXX) && trap "rm -rf \"$workdir\"" EXIT && git clone --branch main --single-branch https://github.com/xrf9268-hue/sbx "$workdir" >/dev/null 2>&1 && cd "$workdir" && bash tests/unit/test_bootstrap_constants.sh'

# Remote Docker lifecycle smoke
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@3.135.246.117 \
  'workdir=$(mktemp -d /tmp/sbx-verify.XXXXXX) && trap "rm -rf \"$workdir\"" EXIT && git clone --branch main --single-branch https://github.com/xrf9268-hue/sbx "$workdir" >/dev/null 2>&1 && cd "$workdir" && bash scripts/e2e/install-lifecycle-smoke.sh'

# Install git hooks in the current working tree when editing locally
bash hooks/install-hooks.sh
```

## Code and Shell Standards

- Use strict mode in shell scripts: `set -euo pipefail`.
- Initialize locals at declaration (`local var=""`) to avoid unbound-usage branches.
- Quote variable expansions (`"${var}"`).
- Prefer repository patterns in `lib/*.sh` and keep changes minimal and targeted.
- For modules sourced during runtime, keep readonly declarations compatible with current module-loading behavior.

## Bootstrap and Strict-Mode Safety

- **Bootstrap constants** are defined in `install.sh` before module loading. Keep bootstrap-only constants in that early section.
- Always validate strict-mode safety for bootstrap paths. Regressions here usually show up as `unbound variable` failures.
- Before finalizing bootstrap-related changes:
  - `bash tests/unit/test_bootstrap_constants.sh`
  - `bash -u install.sh --help`

## Testing and Verification

- For changes in shell runtime code (`install.sh`, `lib/**`, `bin/**`), run on the VM:
  - `bash tests/test-runner.sh unit`
- For docker smoke or lifecycle changes, run on the VM:
  - `bash scripts/e2e/install-lifecycle-smoke.sh`
- For CI/workflow policy changes, run:
  - `bash tests/unit/test_ci_workflows.sh`
  - `bash tests/unit/test_coverage_suite_invocations.sh`

## Docker Smoke Policy

- Default base image: `ubuntu:24.04`
- Fallback image on non-CI hosts (only when official pull fails): `docker.950288.xyz/library/ubuntu:24.04`
- In GitHub CI (`GITHUB_ACTIONS=true`), use official image only; do not force proxy-fallback images.
- Mirror fallback strategy for non-CI apt bootstrap uses both HTTPS and HTTP mirrors.

Related environment variables:

```bash
SBX_SMOKE_BASE_IMAGE=ubuntu:24.04
SBX_SMOKE_FALLBACK_IMAGE=docker.950288.xyz/library/ubuntu:24.04
SBX_SMOKE_KEEP_CONTAINER=1
SBX_SMOKE_CONTAINER_NAME=sbx-lifecycle-smoke-debug
SINGBOX_VERSION=1.13.0
TEST_DOMAIN=1.1.1.1
```

## Reference Docs

- User guide: `README.md`
- Contributor process: `CONTRIBUTING.md`
- Test guide: `tests/README.md`
- VM environment notes: `vm-env-notes.md`
- Troubleshooting: `docs/REALITY_TROUBLESHOOTING.md`
- Cloudflare Tunnel: `docs/CLOUDFLARE_TUNNEL.md`
- Internal architecture and coding notes: `.claude/ARCHITECTURE.md`, `.claude/CODING_STANDARDS.md`

## Compatibility

- `CLAUDE.md` is retained as a compatibility entrypoint and should not diverge from this file.
