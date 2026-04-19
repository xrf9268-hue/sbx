# Reality Short ID Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `sbx rotate-shortid` so the installed app can rotate Reality short IDs manually or on a `systemd` schedule, update all live server-side artifacts, refresh subscription output, and keep structured audit history without adding compatibility debt.

**Architecture:** Add `lib/reality_rotation.sh` as the single owner of rotation and timer logic. `bin/sbx-manager.sh` only parses CLI flags and delegates. `install.sh` only registers the module and removes the timer units during uninstall. The rotation path writes a candidate config, validates it with `sing-box check`, atomically swaps `config.json`, `client-info.txt`, and `state.json`, restarts `sing-box`, then refreshes subscription cache if enabled.

**Tech Stack:** Bash, jq, systemd, existing `lib/common.sh` locking helpers, `lib/service.sh`, `lib/subscription.sh`, unit tests in `tests/unit`, runtime verification on the existing Debian 12 AWS VM.

---

## File Structure

- Create: `lib/reality_rotation.sh`
  - Public API for `reality_rotate_shortid`, `reality_rotation_schedule`, and uninstall cleanup.
  - Owns state mutation, candidate config validation, timer unit install/remove, and audit history trimming.

- Create: `tests/unit/test_reality_rotation.sh`
  - Fixture-driven tests for manual rotation, dry-run, rollback, schedule state, timer units, and history trimming.

- Create: `tests/unit/test_sbx_manager_rotate_shortid.sh`
  - CLI help, routing, and invalid flag combination tests using stub libraries.

- Create: `tests/unit/test_reality_rotation_installation.sh`
  - Static assertions for install-time module registration, API contract registration, and uninstall cleanup hooks.

- Modify: `bin/sbx-manager.sh`
  - Source the new module, expose help text, validate flags, and route the `rotate-shortid` command.

- Modify: `install.sh`
  - Register `reality_rotation` in the module download/load list and API contract map.
  - Remove `sbx-shortid-rotate.service` and `sbx-shortid-rotate.timer` during uninstall.

## Spec Input

- Design spec: `docs/superpowers/specs/2026-04-18-rotate-shortid-design.md`

## Task 1: Build the Core Rotation Module With Red-Green Tests

**Files:**
- Create: `tests/unit/test_reality_rotation.sh`
- Create: `lib/reality_rotation.sh`
- Test: `bash tests/unit/test_reality_rotation.sh`

- [ ] **Step 1: Write failing fixture tests for the manual rotation path**

Create `tests/unit/test_reality_rotation.sh` with a temp fixture containing:

- `state.json` with `.protocols.reality.short_id = "abcd1234"`
- `client-info.txt` with `SHORT_ID="abcd1234"`
- `config.json` with one Reality inbound containing `"short_id": ["abcd1234"]`
- optional subscription state enabled for cache refresh assertions

Include failing tests shaped like:

```bash
test_manual_rotation_updates_live_files() {
  _run_rotation "reality_rotate_shortid" >/dev/null
  new_sid=$(jq -r '.protocols.reality.short_id' "${STATE_FILE}")
  assert_matches "${new_sid}" '^[0-9a-f]{8}$' "state.json stores an 8-char hex short ID"
  assert_failure "[[ '${new_sid}' == 'abcd1234' ]]" "short ID must change"
  assert_equals "${new_sid}" \
    "$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${CONFIG_FILE}")" \
    "config.json uses the new short ID"
  assert_contains "$(cat "${CLIENT_INFO_FILE}")" "SHORT_ID=\"${new_sid}\"" \
    "client-info.txt uses the new short ID"
}

test_dry_run_leaves_live_files_untouched() {
  before_state=$(sha256sum "${STATE_FILE}" | awk '{print $1}')
  before_client=$(sha256sum "${CLIENT_INFO_FILE}" | awk '{print $1}')
  before_config=$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')
  _run_rotation "reality_rotate_shortid --dry-run" >/dev/null
  assert_equals "${before_state}" "$(sha256sum "${STATE_FILE}" | awk '{print $1}')" \
    "dry-run does not rewrite state.json"
  assert_equals "${before_client}" "$(sha256sum "${CLIENT_INFO_FILE}" | awk '{print $1}')" \
    "dry-run does not rewrite client-info.txt"
  assert_equals "${before_config}" "$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')" \
    "dry-run does not rewrite config.json"
}

test_restart_failure_rolls_back_files() {
  ROTATION_FORCE_RESTART_FAILURE=1 _run_rotation "reality_rotate_shortid" >/dev/null 2>&1
  assert_equals "abcd1234" "$(jq -r '.protocols.reality.short_id' "${STATE_FILE}")" \
    "rollback restores state.json"
}
```

- [ ] **Step 2: Run the new unit test to verify it fails**

Run:

```bash
bash tests/unit/test_reality_rotation.sh
```

Expected:

- FAIL because `lib/reality_rotation.sh` does not exist yet, or
- FAIL because `reality_rotate_shortid` is undefined

- [ ] **Step 3: Implement the minimal core module**

Create `lib/reality_rotation.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${_SBX_REALITY_ROTATION_LOADED:-}" ]] && return 0
readonly _SBX_REALITY_ROTATION_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/common.sh"
source "${_LIB_DIR}/validation.sh"
source "${_LIB_DIR}/service.sh"

: "${ROTATION_SERVICE_NAME:=sbx-shortid-rotate.service}"
: "${ROTATION_TIMER_NAME:=sbx-shortid-rotate.timer}"
: "${ROTATION_HISTORY_LIMIT:=20}"

reality_rotate_shortid() {
  local trigger="manual"
  local dry_run=0
  local arg=''
  for arg in "$@"; do
    case "${arg}" in
      --dry-run) dry_run=1 ;;
      --scheduled-run) trigger="timer" ;;
      *) err "Unknown option: ${arg}"; return 1 ;;
    esac
  done
  with_state_lock "${SBX_LOCK_TIMEOUT_SEC:-30}" \
    _reality_rotate_shortid_locked "${trigger}" "${dry_run}"
}
```

Inside `_reality_rotate_shortid_locked` implement the minimum green path:

- resolve current `state.json`, `client-info.txt`, `config.json`
- read current short ID from `state.json`
- generate a new value with `openssl rand -hex 4`
- reject equal-to-old values in a small retry loop
- write a candidate config using `jq '(.inbounds[] | select(.tls.reality) | .tls.reality.short_id) = [$sid]'`
- validate with `"${SB_BIN}" check -c "${tmp_config}"`
- if `dry_run=1`, print the preview and exit success
- backup the three live files
- atomically replace `config.json`, `client-info.txt`, and `state.json`
- call `restart_service`
- call `subscription_refresh_cache` only when available and enabled

- [ ] **Step 4: Run the core module test until it passes**

Run:

```bash
bash tests/unit/test_reality_rotation.sh
```

Expected:

- PASS for manual rotate
- PASS for dry-run
- PASS for rollback-on-restart-failure

- [ ] **Step 5: Commit the core module**

Run:

```bash
git add lib/reality_rotation.sh tests/unit/test_reality_rotation.sh
git commit -m "feat: add core reality short id rotation"
```

## Task 2: Add Audit History and `systemd` Schedule Management

**Files:**
- Modify: `lib/reality_rotation.sh`
- Modify: `tests/unit/test_reality_rotation.sh`
- Test: `bash tests/unit/test_reality_rotation.sh`

- [ ] **Step 1: Extend the module test with schedule and history cases**

Add failing tests:

```bash
test_schedule_weekly_installs_units_and_updates_state() {
  _run_rotation "reality_rotation_schedule weekly" >/dev/null
  assert_equals "weekly" \
    "$(jq -r '.protocols.reality.short_id_rotation.schedule' "${STATE_FILE}")" \
    "state.json records the schedule"
  assert_file_exists "${UNIT_DIR}/sbx-shortid-rotate.service" \
    "service unit is rendered"
  assert_file_exists "${UNIT_DIR}/sbx-shortid-rotate.timer" \
    "timer unit is rendered"
  assert_contains "$(cat "${UNIT_DIR}/sbx-shortid-rotate.timer")" "OnCalendar=weekly" \
    "timer uses weekly cadence"
}

test_schedule_off_removes_units() {
  _run_rotation "reality_rotation_schedule off" >/dev/null
  assert_success "jq -e '.protocols.reality.short_id_rotation.enabled == false' '${STATE_FILE}' >/dev/null" \
    "state disables scheduling"
}

test_history_trim_keeps_20_entries() {
  seed_history_entries 25
  _run_rotation "reality_rotate_shortid" >/dev/null
  assert_equals "20" \
    "$(jq -r '.protocols.reality.short_id_rotation.history | length' "${STATE_FILE}")" \
    "history is trimmed to 20 entries"
}
```

Stub `install_systemd_unit`, `remove_systemd_unit`, and `systemctl` inside the test harness so the test never touches `/etc/systemd/system`.

- [ ] **Step 2: Run the module test again to capture the red state**

Run:

```bash
bash tests/unit/test_reality_rotation.sh
```

Expected:

- FAIL because schedule helpers and history trimming do not exist yet

- [ ] **Step 3: Implement schedule and audit helpers in the module**

Add these public and private helpers to `lib/reality_rotation.sh`:

```bash
_rotation_schedule_to_oncalendar() {
  case "${1:-}" in
    daily|weekly|monthly) printf '%s\n' "$1" ;;
    off) printf '\n' ;;
    *) return 1 ;;
  esac
}

reality_rotation_schedule() {
  local schedule="${1:-}"
  local on_calendar=''
  on_calendar=$(_rotation_schedule_to_oncalendar "${schedule}") || {
    err "Invalid schedule: ${schedule}"
    return 1
  }
  if [[ "${schedule}" == "off" ]]; then
    reality_rotation_remove_units || return 1
  else
    _rotation_install_units "${on_calendar}" || return 1
  fi
  _rotation_write_schedule_state "${schedule}" "${on_calendar}"
}

reality_rotation_remove_units() {
  remove_systemd_unit "${ROTATION_SERVICE_NAME}" "/etc/systemd/system/${ROTATION_SERVICE_NAME}" "best_effort" || true
  remove_systemd_unit "${ROTATION_TIMER_NAME}" "/etc/systemd/system/${ROTATION_TIMER_NAME}" "best_effort" || true
}
```

Also add:

- `_rotation_append_history` with newest-first history
- `_rotation_trim_history` with `.[0:20]`
- `_rotation_write_schedule_state`
- rendered unit contents for `sbx-shortid-rotate.service` and `sbx-shortid-rotate.timer`
- `Persistent=true` in the timer file

- [ ] **Step 4: Re-run the module test until all schedule and history cases pass**

Run:

```bash
bash tests/unit/test_reality_rotation.sh
```

Expected:

- PASS for weekly schedule setup
- PASS for schedule off
- PASS for history trimming

- [ ] **Step 5: Commit the schedule layer**

Run:

```bash
git add lib/reality_rotation.sh tests/unit/test_reality_rotation.sh
git commit -m "feat: add scheduled short id rotation"
```

## Task 3: Wire `sbx-manager` Help, Routing, and Flag Validation

**Files:**
- Create: `tests/unit/test_sbx_manager_rotate_shortid.sh`
- Modify: `bin/sbx-manager.sh`
- Test: `bash tests/unit/test_sbx_manager_rotate_shortid.sh`

- [ ] **Step 1: Write failing CLI routing tests**

Create `tests/unit/test_sbx_manager_rotate_shortid.sh` using the pattern from `tests/unit/test_sbx_manager_telegram.sh`.

Stub library example:

```bash
cat >"${STUB_LIB}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
need_root() { echo "need_root" >>"${INVOCATION_LOG}"; return 0; }
EOF

cat >"${STUB_LIB}/reality_rotation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
reality_rotate_shortid() { echo "reality_rotate_shortid $*" >>"${INVOCATION_LOG}"; }
reality_rotation_schedule() { echo "reality_rotation_schedule $*" >>"${INVOCATION_LOG}"; }
EOF
```

Add tests for:

- help text lists `rotate-shortid`
- `sbx rotate-shortid --dry-run` calls `need_root` then `reality_rotate_shortid --dry-run`
- `sbx rotate-shortid --schedule weekly` calls `need_root` then `reality_rotation_schedule weekly`
- `sbx rotate-shortid --dry-run --schedule weekly` exits non-zero with a clear error

- [ ] **Step 2: Run the CLI test to verify it fails**

Run:

```bash
bash tests/unit/test_sbx_manager_rotate_shortid.sh
```

Expected:

- FAIL because `bin/sbx-manager.sh` does not yet source `reality_rotation.sh`
- FAIL because `rotate-shortid` is not in help or command routing

- [ ] **Step 3: Implement the `sbx-manager` integration**

Modify `bin/sbx-manager.sh` in two places:

1. Source the module if present:

```bash
[[ -f "$LIB_DIR/reality_rotation.sh" ]] && source "$LIB_DIR/reality_rotation.sh"
```

2. Add help text and command dispatch:

```bash
${B}Reality Rotation:${N}
  rotate-shortid [--dry-run]                     Rotate the active Reality short ID
  rotate-shortid --schedule <daily|weekly|monthly|off>
                                                Configure automatic short ID rotation
```

```bash
  rotate-shortid)
    need_root || exit 1
    case "${2:-}" in
      --schedule)
        [[ -n "${3:-}" ]] || error_exit "Usage: sbx rotate-shortid --schedule <daily|weekly|monthly|off>"
        [[ $# -eq 3 ]] || error_exit "Do not combine --schedule with other flags."
        reality_rotation_schedule "${3}"
        ;;
      *)
        reality_rotate_shortid "$@"
        ;;
    esac
    ;;
```

Normalize the argument handling so `"$@"` passed to `reality_rotate_shortid` excludes the top-level command name.

- [ ] **Step 4: Re-run the CLI routing test**

Run:

```bash
bash tests/unit/test_sbx_manager_rotate_shortid.sh
```

Expected:

- PASS for help text
- PASS for `--dry-run` routing
- PASS for `--schedule weekly` routing
- PASS for invalid flag combinations

- [ ] **Step 5: Commit the CLI integration**

Run:

```bash
git add bin/sbx-manager.sh tests/unit/test_sbx_manager_rotate_shortid.sh
git commit -m "feat: add rotate-shortid CLI command"
```

## Task 4: Register the Module in `install.sh` and Remove Rotation Units on Uninstall

**Files:**
- Create: `tests/unit/test_reality_rotation_installation.sh`
- Modify: `install.sh`
- Test: `bash tests/unit/test_reality_rotation_installation.sh`

- [ ] **Step 1: Write failing install-time assertions**

Create `tests/unit/test_reality_rotation_installation.sh` with static checks:

```bash
assert_success "grep -qE '\\breality_rotation\\b' '${PROJECT_ROOT}/install.sh'" \
  "install.sh module list includes reality_rotation"
assert_success "grep -q '\\[\"reality_rotation\"\\]=' '${PROJECT_ROOT}/install.sh'" \
  "install.sh API contract includes reality_rotation"
assert_success "grep -q 'sbx-shortid-rotate.timer' '${PROJECT_ROOT}/install.sh'" \
  "uninstall flow removes the timer unit"
assert_success "grep -q 'sbx-shortid-rotate.service' '${PROJECT_ROOT}/install.sh'" \
  "uninstall flow removes the service unit"
```

- [ ] **Step 2: Run the install-time assertion test to verify it fails**

Run:

```bash
bash tests/unit/test_reality_rotation_installation.sh
```

Expected:

- FAIL because `install.sh` is not yet aware of the new module or timer cleanup

- [ ] **Step 3: Update `install.sh`**

Make these changes:

1. Add `reality_rotation` to the `_load_modules` array after `subscription` and before `stats`.

2. Add an API contract entry:

```bash
["reality_rotation"]="reality_rotate_shortid reality_rotation_schedule reality_rotation_remove_units"
```

3. In `uninstall_flow`, remove the units best-effort:

```bash
  if declare -f reality_rotation_remove_units >/dev/null 2>&1; then
    reality_rotation_remove_units || true
  else
    systemctl stop sbx-shortid-rotate.timer 2>/dev/null || true
    systemctl disable sbx-shortid-rotate.timer 2>/dev/null || true
    systemctl stop sbx-shortid-rotate.service 2>/dev/null || true
    rm -f /etc/systemd/system/sbx-shortid-rotate.service
    rm -f /etc/systemd/system/sbx-shortid-rotate.timer
    systemctl daemon-reload 2>/dev/null || true
  fi
```

- [ ] **Step 4: Run the install integration test and module dependency tests**

Run:

```bash
bash tests/unit/test_reality_rotation_installation.sh
bash tests/unit/test_module_dependencies.sh
bash tests/unit/test_module_loading_sequence.sh
```

Expected:

- PASS for module registration
- PASS for uninstall cleanup assertions
- PASS for updated module counts and dependency ordering

- [ ] **Step 5: Commit the install/uninstall integration**

Run:

```bash
git add install.sh tests/unit/test_reality_rotation_installation.sh
git commit -m "feat: register short id rotation module"
```

## Task 5: Run Full Verification Locally and on the AWS VM

**Files:**
- Modify: none expected
- Test: local unit suite, VM unit suite, VM runtime checks, VM docker smoke

- [ ] **Step 1: Run the targeted local tests**

Run:

```bash
bash tests/unit/test_reality_rotation.sh
bash tests/unit/test_sbx_manager_rotate_shortid.sh
bash tests/unit/test_reality_rotation_installation.sh
```

Expected:

- all three targeted tests pass

- [ ] **Step 2: Run the local regression suite**

Run:

```bash
bash tests/test-runner.sh unit
bash -u install.sh --help
```

Expected:

- unit suite exits 0
- `install.sh --help` exits 0 under `bash -u`

- [ ] **Step 3: Sync the branch to the existing AWS VM and run remote unit checks**

On the VM, in `~/sbx`, update to the branch under test, then run:

```bash
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  'cd ~/sbx && bash tests/test-runner.sh unit'
```

Expected:

- remote unit suite exits 0 on Debian 12 x86_64

- [ ] **Step 4: Run VM runtime validation for the new command and timer**

On the VM host, with the current branch installed in the existing test environment, run:

```bash
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  'sudo sbx rotate-shortid --dry-run'

ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  'sudo sbx rotate-shortid'

ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  "sudo sbx rotate-shortid --schedule weekly && systemctl status sbx-shortid-rotate.timer --no-pager"

ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  "sudo systemctl start sbx-shortid-rotate.service && journalctl -u sbx-shortid-rotate.service -n 50 --no-pager"
```

Expected:

- dry-run prints old/new short IDs without mutating files
- live rotation changes `config.json`, `client-info.txt`, and `state.json`
- weekly timer is active
- service journal shows a successful scheduled rotation path

- [ ] **Step 5: Run VM docker smoke and create the final feature commit**

Run:

```bash
ssh -i ~/.ssh/ai-polling-proxy.pem -o StrictHostKeyChecking=accept-new \
  admin@18.217.254.125 \
  'cd ~/sbx && bash scripts/e2e/install-lifecycle-smoke.sh'

git status --short
git commit -m "feat: add reality short id rotation"
```

Expected:

- Docker lifecycle smoke passes on the VM
- working tree is clean except for the intended feature changes

## Review Checklist

- One scheduler model only: `systemd`, not cron.
- One state model only: `.protocols.reality.short_id_rotation`.
- One execution path only: manual and timer runs both call `reality_rotate_shortid`.
- `--schedule` never performs an immediate rotation.
- `--dry-run` never mutates files or timers.
- Config validation happens before any live file replacement.
- Restart failure restores the old live files.
- Subscription refresh happens only after a successful restart and only when subscription is enabled.
- Uninstall removes both `sbx-shortid-rotate.service` and `sbx-shortid-rotate.timer`.
