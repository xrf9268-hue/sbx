#!/usr/bin/env bash
# tests/unit/test_install_dry_run.sh - Validate install.sh --dry-run preview mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

run_install_dry_run() {
    local output=''
    set +e
    output=$(bash "$PROJECT_ROOT/install.sh" --dry-run 2>&1)
    local rc=$?
    set -e
    echo "$rc"$'\n'"$output"
}

run_install_dry_run_with_env() {
    local env_args=("$@")
    local output=''
    set +e
    output=$(env "${env_args[@]}" bash "$PROJECT_ROOT/install.sh" --dry-run 2>&1)
    local rc=$?
    set -e
    echo "$rc"$'\n'"$output"
}

test_dry_run_default_preview() {
    echo "Testing default --dry-run output..."

    local result rc output
    result=$(run_install_dry_run)
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    assert_equals "0" "$rc" "--dry-run exits successfully"
    assert_contains "$output" "sbx dry-run preview" "--dry-run shows preview header"
    assert_contains "$output" "No changes made." "--dry-run confirms no changes"
}

test_dry_run_domain_mode_preview() {
    echo "Testing domain-mode --dry-run output..."

    local result rc output
    result=$(run_install_dry_run_with_env "DOMAIN=example.com")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    assert_equals "0" "$rc" "DOMAIN + --dry-run exits successfully"
    assert_contains "$output" "Mode: Multi-protocol" "dry-run reports multi-protocol mode"
    assert_contains "$output" "VLESS-REALITY" "dry-run includes Reality protocol"
    assert_contains "$output" "VLESS-WS-TLS" "dry-run includes WS protocol"
    assert_contains "$output" "Hysteria2" "dry-run includes Hysteria2 protocol"
}

test_dry_run_cf_mode_preview() {
    echo "Testing CF_MODE --dry-run output..."

    local result rc output
    result=$(run_install_dry_run_with_env "DOMAIN=example.com" "CF_MODE=1")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    assert_equals "0" "$rc" "CF_MODE + --dry-run exits successfully"
    assert_contains "$output" "Cloudflare proxy mode enabled" "dry-run reports CF mode"
    assert_contains "$output" "VLESS-WS-TLS on port 443/tcp" "dry-run reflects CF WS port"
}

main() {
    set +e
    run_test_suite "install.sh --dry-run preview mode" true test_dry_run_default_preview true
    run_test_suite "install.sh --dry-run with DOMAIN" true test_dry_run_domain_mode_preview true
    run_test_suite "install.sh --dry-run with CF_MODE" true test_dry_run_cf_mode_preview true
    print_test_summary
}

main "$@"
