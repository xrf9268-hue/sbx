#!/usr/bin/env bash
# tests/unit/test_backup_restore_failure_safety.sh - Validate restore safety on corrupted backups

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Use test framework assertions
source "${PROJECT_ROOT}/tests/test_framework.sh"

# Keep certificates in a temp directory to avoid polluting /etc/ssl
TEST_CERT_DIR="$(mktemp -d /tmp/sbx-test-certs.XXXXXX)"
export CERT_DIR_BASE="$TEST_CERT_DIR"

# Load the backup module
source "${PROJECT_ROOT}/lib/backup.sh" 2>/dev/null || {
  echo "ERROR: Failed to load lib/backup.sh"
  exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
set +e

test_corrupted_archive_preserves_state() {
  echo ""
  echo "Test: corrupted archive does not change live state"

  local tmpdir
  tmpdir="$(create_test_tmpdir)"

  local systemctl_log="${tmpdir}/systemctl.log"
  mkdir -p "${tmpdir}/bin"
  cat > "${tmpdir}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${TMP_SYSTEMCTL_LOG}"
if [[ "$1" == "is-active" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${tmpdir}/bin/systemctl"
  export TMP_SYSTEMCTL_LOG="$systemctl_log"
  export PATH="${tmpdir}/bin:${PATH}"

  local conf_root="${tmpdir}/conf"
  local cert_root="${tmpdir}/certs"
  local service_root="${tmpdir}/service"
  mkdir -p "$conf_root" "$cert_root/example.com" "$service_root"

  local cleanup_symlink_conf=false
  local cleanup_symlink_certs=false
  local restore_conf_backup=""
  local restore_cert_backup=""
  local restore_service_backup=""

  if [[ -e /etc/sing-box ]]; then
    restore_conf_backup="${tmpdir}/conf-backup"
    cp -a /etc/sing-box "$restore_conf_backup"
    rm -rf /etc/sing-box
  fi

  if [[ -e /etc/ssl/sbx ]]; then
    restore_cert_backup="${tmpdir}/cert-backup"
    cp -a /etc/ssl/sbx "$restore_cert_backup"
    rm -rf /etc/ssl/sbx
  fi

  if [[ -e /etc/systemd/system/sing-box.service ]]; then
    restore_service_backup="${tmpdir}/service-backup"
    cp -a /etc/systemd/system/sing-box.service "$restore_service_backup"
    rm -f /etc/systemd/system/sing-box.service
  fi

  ln -s "$conf_root" /etc/sing-box
  cleanup_symlink_conf=true

  ln -s "$cert_root" /etc/ssl/sbx
  cleanup_symlink_certs=true

  ln -s "$service_root/sing-box.service" /etc/systemd/system/sing-box.service

  echo "original-config" > "$conf_root/config.json"
  echo "original-client" > "$conf_root/client-info.txt"
  echo "original-fullchain" > "$cert_root/example.com/fullchain.pem"
  echo "original-privkey" > "$cert_root/example.com/privkey.pem"
  echo "original-service" > "$service_root/sing-box.service"

  local corrupt_archive
  corrupt_archive="$(mktemp /tmp/sbx-corrupt-backup.XXXX)"
  echo "not-a-tarball" > "$corrupt_archive"

  local status=0
  (FORCE=1 TMP_SYSTEMCTL_LOG="$systemctl_log" backup_restore "$corrupt_archive") || status=$?

  assert_failure "[[ $status -eq 0 ]]" "Restore should fail for corrupted archive"
  assert_equals "original-config" "$(cat "$conf_root/config.json")" "Config unchanged after failed restore"
  assert_equals "original-client" "$(cat "$conf_root/client-info.txt")" "Client info unchanged after failed restore"
  assert_equals "original-fullchain" "$(cat "$cert_root/example.com/fullchain.pem")" "Certificate fullchain unchanged after failed restore"
  assert_equals "original-privkey" "$(cat "$cert_root/example.com/privkey.pem")" "Certificate privkey unchanged after failed restore"
  assert_equals "original-service" "$(cat "$service_root/sing-box.service")" "Service file unchanged after failed restore"
  assert_equals "" "$(cat "$systemctl_log" 2>/dev/null)" "Service state unchanged (no systemctl calls)"

  rm -f "$corrupt_archive"

  if [[ -n "$restore_service_backup" ]]; then
    mv "$restore_service_backup" /etc/systemd/system/sing-box.service
  else
    rm -f /etc/systemd/system/sing-box.service
  fi

  if $cleanup_symlink_conf; then
    rm -f /etc/sing-box
  fi
  if [[ -n "$restore_conf_backup" ]]; then
    mv "$restore_conf_backup" /etc/sing-box
  fi

  if $cleanup_symlink_certs; then
    rm -f /etc/ssl/sbx
  fi
  if [[ -n "$restore_cert_backup" ]]; then
    mv "$restore_cert_backup" /etc/ssl/sbx
  fi

  cleanup_test_tmpdir "$tmpdir"
  rm -rf "$TEST_CERT_DIR"
}

echo ""
echo "=========================================="
echo "Running test suite: backup_restore safety"
echo "=========================================="

test_corrupted_archive_preserves_state

print_test_summary
exit $?
