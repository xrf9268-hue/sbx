#!/usr/bin/env bash
# tests/unit/test_sbx_manager_status.sh - Validate sbx-manager status handling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

setup_status_mock() {
    MOCK_DIR=$(mktemp -d /tmp/sbx-test-status.XXXXXX)
    cat >"$MOCK_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash

if [[ "$1" == "is-active" ]]; then
    # Inactive service should return non-zero (exit code 3 in systemd)
    exit 3
fi

if [[ "$1" == "show" ]]; then
    echo "0"
    exit 0
fi

if [[ "$1" == "status" ]]; then
    echo "sing-box.service - sing-box"
    echo "Loaded: loaded (/etc/systemd/system/sing-box.service; enabled)"
    echo "Active: inactive (dead) since Tue 2024-01-02 12:00:00 UTC; 1s ago"
    exit 3
fi

echo "Unexpected arguments: $*" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/systemctl"
}

teardown_status_mock() {
    [[ -n "${MOCK_DIR:-}" && -d "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"
}

test_status_handles_inactive_service() {
    echo "Testing sbx-manager status with inactive service..."

    set +e
    output=$(PATH="$MOCK_DIR:$PATH" "$PROJECT_ROOT/bin/sbx-manager.sh" status 2>&1)
    exit_code=$?

    assert_equals "0" "$exit_code" "status should not exit non-zero for inactive service"
    assert_contains "$output" "Stopped" "Status output should indicate service is stopped"
    assert_contains "$output" "sing-box.service - sing-box" "Status output should include systemctl status text"
}

main() {
    # Disable strict mode to allow assertion tracking
    set +e

    run_test_suite "sbx-manager status handles inactive service" setup_status_mock test_status_handles_inactive_service teardown_status_mock
    print_test_summary
}

main "$@"
