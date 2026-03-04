# sbx-lite Test Guide

This directory contains unit, integration, and CI helper tests for `sbx-lite`.

## Directory layout

```text
tests/
├── ci/           # CI helper scripts (coverage, integration checks, installers)
├── integration/  # Integration and lifecycle tests
├── unit/         # Fast unit-style shell tests
└── test-runner.sh
```

## Run tests locally

```bash
# Unit tests
bash tests/test-runner.sh unit

# Integration tests
bash tests/test-runner.sh integration

# Docker lifecycle smoke test (recommended local e2e path)
bash scripts/e2e/install-lifecycle-smoke.sh

# Compatibility path (calls the same e2e script)
bash tests/integration/test_docker_lifecycle_smoke.sh
```

## Docker lifecycle smoke (local e2e)

Main script: `scripts/e2e/install-lifecycle-smoke.sh`

Validated scenarios:

1. Fresh install
2. Reinstall over existing installation (with config backup)
3. Uninstall twice (idempotent)
4. Reinstall after uninstall

### Image and mirror behavior

- Default base image: `ubuntu:24.04`
- Local fallback image (when Docker Hub pull fails):
  `docker.950288.xyz/library/ubuntu:24.04`
- In GitHub Actions (`GITHUB_ACTIONS=true`), fallback image is disabled and only
  the official base image is used.
- Apt dependency install retries across mirrors. Local runs can fall back to
  Tsinghua/Aliyun/USTC mirrors when official mirrors are unstable.

### Environment variables

```bash
# Base image (preferred)
SBX_SMOKE_BASE_IMAGE=ubuntu:24.04

# Backward-compatible image override
DOCKER_IMAGE=ubuntu:24.04

# Local fallback image proxy
SBX_SMOKE_FALLBACK_IMAGE=docker.950288.xyz/library/ubuntu:24.04

# Keep failed container for debugging
SBX_SMOKE_KEEP_CONTAINER=1

# Optional scenario inputs
SINGBOX_VERSION=1.13.0
TEST_DOMAIN=1.1.1.1
SBX_SMOKE_CONTAINER_NAME=sbx-lifecycle-smoke-debug
```

## CI integration

- Workflow job: `.github/workflows/test.yml` -> `docker-lifecycle-smoke`
- Make target: `make test-docker-smoke`
- Coverage suite optional docker case:
  `bash tests/ci/coverage_suite.sh --include-docker`
