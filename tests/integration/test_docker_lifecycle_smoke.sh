#!/usr/bin/env bash
# tests/integration/test_docker_lifecycle_smoke.sh
# Compatibility wrapper for historical path. The main implementation lives in
# scripts/e2e/install-lifecycle-smoke.sh.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${PROJECT_ROOT}/scripts/e2e/install-lifecycle-smoke.sh" "$@"
