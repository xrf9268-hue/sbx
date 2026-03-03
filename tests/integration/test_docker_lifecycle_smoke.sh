#!/usr/bin/env bash
# tests/integration/test_docker_lifecycle_smoke.sh
# Validate installer lifecycle in Docker:
# - first install
# - overwrite reinstall
# - uninstall
# - reinstall after uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:24.04}"
CONTAINER_NAME="${CONTAINER_NAME:-sbx-lifecycle-smoke-$$}"
SINGBOX_VERSION="${SINGBOX_VERSION:-1.13.0}"
TEST_DOMAIN="${TEST_DOMAIN:-1.1.1.1}"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

info() {
  echo "[INFO] $*"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "[PASS] $*"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "[FAIL] $*" >&2
}

run_test() {
  local name="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@"; then
    pass "${name}"
  else
    fail "${name}"
  fi
}

docker_exec() {
  docker exec "${CONTAINER_NAME}" bash -lc "$*"
}

run_with_retries() {
  local max_attempts="$1"
  local delay_sec="$2"
  shift 2
  local attempt=1

  while true; do
    if "$@"; then
      return 0
    fi

    if [[ ${attempt} -ge ${max_attempts} ]]; then
      return 1
    fi

    warn_msg="Command failed (attempt ${attempt}/${max_attempts}), retrying in ${delay_sec}s..."
    info "${warn_msg}"
    sleep "${delay_sec}"
    attempt=$((attempt + 1))
    delay_sec=$((delay_sec * 2))
  done
}

setup_container() {
  info "Starting container: ${CONTAINER_NAME} (${DOCKER_IMAGE})"
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace \
    "${DOCKER_IMAGE}" \
    bash -lc "sleep infinity" > /dev/null

  info "Installing container dependencies"
  run_with_retries 3 2 docker_exec "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq"
  run_with_retries 3 2 docker_exec "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; \
    apt-get install -y -qq ca-certificates curl jq openssl iproute2 lsof procps tar gzip > /dev/null"

  info "Installing fake systemctl for non-systemd container"
  docker_exec "cat > /usr/local/bin/systemctl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE='/tmp/fake-systemctl-sing-box.state'
cmd=\"\${1:-}\"
unit=\"\${2:-}\"
case \"\${cmd}\" in
  daemon-reload|enable|disable|reload)
    exit 0
    ;;
  start|restart)
    if [[ \"\${unit}\" == 'sing-box' ]]; then
      echo 'active' > \"\${STATE_FILE}\"
    fi
    exit 0
    ;;
  stop)
    if [[ \"\${unit}\" == 'sing-box' ]]; then
      echo 'inactive' > \"\${STATE_FILE}\"
    fi
    exit 0
    ;;
  is-active)
    if [[ \"\${unit}\" == 'sing-box' && -f \"\${STATE_FILE}\" && \"\$(cat \"\${STATE_FILE}\")\" == 'active' ]]; then
      exit 0
    fi
    exit 3
    ;;
  is-enabled)
    exit 1
    ;;
  status)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x /usr/local/bin/systemctl"
}

run_install() {
  docker_exec "set -euo pipefail; cd /workspace; \
    AUTO_INSTALL=1 DOMAIN='${TEST_DOMAIN}' SINGBOX_VERSION='${SINGBOX_VERSION}' bash install.sh"
}

run_uninstall() {
  docker_exec "set -euo pipefail; cd /workspace; FORCE=1 bash install.sh uninstall"
}

assert_installed() {
  docker_exec "set -euo pipefail; \
    [[ -x /usr/local/bin/sing-box ]]; \
    [[ -x /usr/local/bin/sbx-manager ]]; \
    [[ -L /usr/local/bin/sbx ]]; \
    [[ -f /etc/sing-box/config.json ]]; \
    [[ -f /etc/sing-box/client-info.txt ]]; \
    [[ -f /etc/systemd/system/sing-box.service ]]; \
    [[ -d /usr/local/lib/sbx ]]"
}

assert_uninstalled() {
  docker_exec "set -euo pipefail; \
    [[ ! -e /usr/local/bin/sing-box ]]; \
    [[ ! -e /usr/local/bin/sbx-manager ]]; \
    [[ ! -e /usr/local/bin/sbx ]]; \
    [[ ! -e /etc/sing-box ]]; \
    [[ ! -e /etc/systemd/system/sing-box.service ]]; \
    [[ ! -e /usr/local/lib/sbx ]]"
}

assert_backup_created() {
  docker_exec "set -euo pipefail; \
    find /etc/sing-box -maxdepth 1 -type f -name 'config.json.backup.*' | grep -q ."
}

cleanup() {
  docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
}

main() {
  trap cleanup EXIT INT TERM

  setup_container

  info "Scenario 1: first install"
  run_test "First install completes" run_install
  run_test "First install artifacts exist" assert_installed

  info "Scenario 2: overwrite reinstall"
  run_test "Overwrite reinstall completes" run_install
  run_test "Reinstall keeps installation valid" assert_installed
  run_test "Reinstall creates config backup" assert_backup_created

  info "Scenario 3: uninstall"
  run_test "Uninstall completes" run_uninstall
  run_test "Uninstall removes artifacts" assert_uninstalled

  info "Scenario 4: reinstall after uninstall"
  run_test "Reinstall after uninstall completes" run_install
  run_test "Reinstall after uninstall restores artifacts" assert_installed

  echo
  echo "========================================"
  echo "Docker Lifecycle Smoke Summary"
  echo "========================================"
  echo "Total:  ${TESTS_RUN}"
  echo "Passed: ${TESTS_PASSED}"
  echo "Failed: ${TESTS_FAILED}"

  if [[ ${TESTS_FAILED} -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
