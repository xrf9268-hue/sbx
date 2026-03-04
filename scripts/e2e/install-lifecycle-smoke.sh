#!/usr/bin/env bash
# scripts/e2e/install-lifecycle-smoke.sh
# Validate installer lifecycle in Docker:
# - first install
# - overwrite reinstall
# - uninstall (idempotent)
# - reinstall after uninstall

set -eEuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER_NAME="${SBX_SMOKE_CONTAINER_NAME:-sbx-lifecycle-smoke-$(date +%s)-$$-${RANDOM}}"
CURRENT_SCENARIO="setup"

# Keep DOCKER_IMAGE for backward compatibility with existing local usage.
DEFAULT_BASE_IMAGE="${SBX_SMOKE_BASE_IMAGE:-${DOCKER_IMAGE:-ubuntu:24.04}}"
LOCAL_FALLBACK_IMAGE="${SBX_SMOKE_FALLBACK_IMAGE:-docker.950288.xyz/library/ubuntu:24.04}"
SINGBOX_VERSION="${SINGBOX_VERSION:-1.13.0}"
TEST_DOMAIN="${TEST_DOMAIN:-1.1.1.1}"

log() {
  printf '[smoke] %s\n' "$*"
}

run_in_container() {
  docker exec "${CONTAINER_NAME}" bash -lc "$1"
}

run_in_container_retry() {
  local cmd="$1"
  local attempts="${2:-5}"
  local delay_sec=2
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if run_in_container "${cmd}"; then
      return 0
    fi

    if ((attempt == attempts)); then
      return 1
    fi

    log "command failed (attempt ${attempt}/${attempts}), retrying in ${delay_sec}s"
    sleep "${delay_sec}"
    delay_sec=$((delay_sec * 2))
  done
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fx -- "${CONTAINER_NAME}" > /dev/null 2>&1
}

dump_failure_logs() {
  local rc="$1"
  log "failed during ${CURRENT_SCENARIO} (exit ${rc})"
  if container_exists; then
    docker exec "${CONTAINER_NAME}" bash -lc '
      shopt -s nullglob
      for f in /tmp/scenario*.log /tmp/apt-*.log; do
        printf "===== %s =====\n" "${f}"
        tail -n 120 "${f}" || true
      done
    ' || true
  fi
}

on_error() {
  local rc="$?"
  dump_failure_logs "${rc}"
  exit "${rc}"
}

cleanup() {
  if [[ "${SBX_SMOKE_KEEP_CONTAINER:-0}" == "1" ]]; then
    log "keeping container ${CONTAINER_NAME} (SBX_SMOKE_KEEP_CONTAINER=1)"
    return 0
  fi
  docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
}

set_apt_mirror() {
  local base_url="$1"
  run_in_container "if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then sed -E -i 's|https?://[^/ ]+|${base_url}|g' /etc/apt/sources.list.d/ubuntu.sources; fi; if [ -f /etc/apt/sources.list ]; then sed -E -i 's|https?://[^/ ]+|${base_url}|g' /etc/apt/sources.list; fi"
}

install_test_dependencies() {
  local -a mirrors=()
  local mirror

  if run_in_container_retry "export DEBIAN_FRONTEND=noninteractive; apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update > /tmp/apt-update.log 2>&1 && apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install -y --no-install-recommends ca-certificates curl jq openssl iproute2 lsof procps tar gzip > /tmp/apt-install.log 2>&1" 3; then
    log "dependency install succeeded via default apt sources"
    return 0
  fi

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    mirrors=(
      "http://archive.ubuntu.com"
      "http://ports.ubuntu.com"
    )
  else
    mirrors=(
      "http://archive.ubuntu.com"
      "http://ports.ubuntu.com"
      "http://mirrors.tuna.tsinghua.edu.cn"
      "http://mirrors.aliyun.com"
      "http://mirrors.ustc.edu.cn"
    )
  fi

  for mirror in "${mirrors[@]}"; do
    log "trying apt mirror ${mirror}"
    set_apt_mirror "${mirror}"
    run_in_container "rm -rf /var/lib/apt/lists/*"
    if run_in_container_retry "export DEBIAN_FRONTEND=noninteractive; apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update > /tmp/apt-update.log 2>&1 && apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install -y --no-install-recommends ca-certificates curl jq openssl iproute2 lsof procps tar gzip > /tmp/apt-install.log 2>&1" 3; then
      log "dependency install succeeded via ${mirror}"
      return 0
    fi
  done

  log "failed to install test dependencies from all mirrors"
  return 1
}

install_systemctl_mock() {
  run_in_container "cat > /usr/local/bin/systemctl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE='/tmp/fake-systemctl-sing-box.state'
cmd=\"\${1:-}\"
unit=\"\${2:-}\"

case \"\${cmd}\" in
  daemon-reload|enable|disable|reload|reset-failed)
    exit 0
    ;;
  start|restart)
    if [[ \"\${unit}\" == 'sing-box' || \"\${unit}\" == 'sing-box.service' ]]; then
      echo 'active' > \"\${STATE_FILE}\"
    fi
    exit 0
    ;;
  stop)
    if [[ \"\${unit}\" == 'sing-box' || \"\${unit}\" == 'sing-box.service' ]]; then
      echo 'inactive' > \"\${STATE_FILE}\"
    fi
    exit 0
    ;;
  is-active)
    if [[ \"\${unit}\" == 'sing-box' || \"\${unit}\" == 'sing-box.service' ]]; then
      if [[ -f \"\${STATE_FILE}\" ]] && [[ \"\$(cat \"\${STATE_FILE}\")\" == 'active' ]]; then
        exit 0
      fi
      exit 3
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
chmod 0755 /usr/local/bin/systemctl"
}

select_base_image() {
  local selected="${DEFAULT_BASE_IMAGE}"
  SELECTED_BASE_IMAGE=""

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    log "GitHub Actions detected; using official image only: ${selected}"
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  if docker image inspect "${selected}" > /dev/null 2>&1; then
    log "using locally cached base image ${selected}"
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  log "pulling base image ${selected}"
  if docker pull "${selected}" > /dev/null 2>&1; then
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  if docker image inspect "${LOCAL_FALLBACK_IMAGE}" > /dev/null 2>&1; then
    log "using locally cached fallback image ${LOCAL_FALLBACK_IMAGE}"
    SELECTED_BASE_IMAGE="${LOCAL_FALLBACK_IMAGE}"
    return 0
  fi

  log "official image pull failed, falling back to ${LOCAL_FALLBACK_IMAGE}"
  if docker pull "${LOCAL_FALLBACK_IMAGE}" > /dev/null 2>&1; then
    SELECTED_BASE_IMAGE="${LOCAL_FALLBACK_IMAGE}"
    return 0
  fi

  log "failed to pull both ${selected} and ${LOCAL_FALLBACK_IMAGE}"
  return 1
}

assert_installed() {
  run_in_container "set -euo pipefail; \
    [[ -x /usr/local/bin/sing-box ]]; \
    [[ -x /usr/local/bin/sbx-manager ]]; \
    [[ -L /usr/local/bin/sbx ]]; \
    [[ -f /etc/sing-box/config.json ]]; \
    [[ -f /etc/sing-box/client-info.txt ]]; \
    [[ -f /etc/sing-box/state.json ]]; \
    [[ -f /etc/systemd/system/sing-box.service ]]; \
    [[ -d /usr/local/lib/sbx ]]"
}

assert_uninstalled() {
  run_in_container "set -euo pipefail; \
    [[ ! -e /usr/local/bin/sing-box ]]; \
    [[ ! -e /usr/local/bin/sbx-manager ]]; \
    [[ ! -e /usr/local/bin/sbx ]]; \
    [[ ! -e /etc/sing-box ]]; \
    [[ ! -e /etc/systemd/system/sing-box.service ]]; \
    [[ ! -e /usr/local/lib/sbx ]]"
}

assert_backup_created() {
  run_in_container "set -euo pipefail; \
    find /etc/sing-box -maxdepth 1 -type f -name 'config.json.backup.*' | grep -q ."
}

main() {
  trap on_error ERR
  trap cleanup EXIT INT TERM

  if ! command -v docker > /dev/null 2>&1; then
    log "docker is required"
    exit 1
  fi

  log "selecting base image"
  select_base_image
  BASE_IMAGE="${SELECTED_BASE_IMAGE}"
  log "starting container ${CONTAINER_NAME} with image ${BASE_IMAGE}"
  CURRENT_SCENARIO="start container"
  docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE}" sleep infinity > /dev/null

  log "installing test dependencies"
  CURRENT_SCENARIO="dependency install"
  install_test_dependencies

  log "copying workspace"
  CURRENT_SCENARIO="copy workspace"
  run_in_container "mkdir -p /workspace"
  docker cp "${ROOT_DIR}/." "${CONTAINER_NAME}:/workspace/sbx"

  log "installing systemctl mock for containerized test"
  CURRENT_SCENARIO="install systemctl mock"
  install_systemctl_mock

  log "scenario 1: first install"
  CURRENT_SCENARIO="scenario 1 first install"
  run_in_container_retry "set -euo pipefail; cd /workspace/sbx; AUTO_INSTALL=1 DOMAIN='${TEST_DOMAIN}' SINGBOX_VERSION='${SINGBOX_VERSION}' bash install.sh > /tmp/scenario1.log 2>&1" 2
  assert_installed

  log "scenario 2: overwrite reinstall creates backup"
  CURRENT_SCENARIO="scenario 2 overwrite reinstall"
  run_in_container_retry "set -euo pipefail; cd /workspace/sbx; AUTO_INSTALL=1 DOMAIN='${TEST_DOMAIN}' SINGBOX_VERSION='${SINGBOX_VERSION}' bash install.sh > /tmp/scenario2.log 2>&1" 2
  assert_installed
  assert_backup_created

  log "scenario 3: uninstall is idempotent"
  CURRENT_SCENARIO="scenario 3 uninstall idempotent"
  run_in_container "set -euo pipefail; cd /workspace/sbx; FORCE=1 bash install.sh uninstall > /tmp/scenario3-uninstall1.log 2>&1"
  run_in_container "set -euo pipefail; cd /workspace/sbx; FORCE=1 bash install.sh uninstall > /tmp/scenario3-uninstall2.log 2>&1"
  assert_uninstalled

  log "scenario 4: reinstall after uninstall"
  CURRENT_SCENARIO="scenario 4 reinstall"
  run_in_container_retry "set -euo pipefail; cd /workspace/sbx; AUTO_INSTALL=1 DOMAIN='${TEST_DOMAIN}' SINGBOX_VERSION='${SINGBOX_VERSION}' bash install.sh > /tmp/scenario4-reinstall.log 2>&1" 2
  assert_installed

  log "all lifecycle smoke scenarios passed"
}

main "$@"
