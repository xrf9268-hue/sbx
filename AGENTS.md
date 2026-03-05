# AGENTS.md

Single source of truth for coding-agent instructions in this repository.

## Scope

- Applies to the entire repository rooted at this file.
- If a deeper directory adds its own `AGENTS.md`, that closer file takes precedence for that subtree.

## Project Context

- **What**: Bash installer for sing-box with Reality protocol support and modular runtime libraries.
- **Primary entrypoint**: `install.sh`
- **Core validation path**: `bash tests/test-runner.sh unit`

## Setup Commands

```bash
# Install local git hooks (required)
bash hooks/install-hooks.sh

# Fast validation
bash tests/test-runner.sh unit
bash tests/unit/test_bootstrap_constants.sh

# Docker lifecycle smoke e2e
bash scripts/e2e/install-lifecycle-smoke.sh
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

- For changes in shell runtime code (`install.sh`, `lib/**`, `bin/**`), run:
  - `bash tests/test-runner.sh unit`
- For docker smoke changes, run:
  - `bash scripts/e2e/install-lifecycle-smoke.sh`
- For CI/workflow policy changes, run:
  - `bash tests/unit/test_ci_workflows.sh`
  - `bash tests/unit/test_coverage_suite_invocations.sh`

## Local Docker Smoke Policy

- Default base image: `ubuntu:24.04`
- Local fallback image (only when official pull fails): `docker.950288.xyz/library/ubuntu:24.04`
- In GitHub CI (`GITHUB_ACTIONS=true`), use official image only; do not force proxy-fallback images.
- Mirror fallback strategy for local apt bootstrap uses both HTTPS and HTTP mirrors.

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
- Troubleshooting: `docs/REALITY_TROUBLESHOOTING.md`
- Internal architecture and coding notes: `.claude/ARCHITECTURE.md`, `.claude/CODING_STANDARDS.md`

## Compatibility

- `CLAUDE.md` is retained as a compatibility entrypoint and should not diverge from this file.
