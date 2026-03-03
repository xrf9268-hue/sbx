# sbx Health Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `sbx health` to provide a post-install runtime health report for service, config, ports, certificate expiry, and deprecated field checks.

**Architecture:** Extend `bin/sbx-manager.sh` with a `run_health_check` command handler and small internal helper functions for consistent `[OK]/[WARN]/[FAIL]` reporting. Keep output text-only for this issue; reserve `--json` support for issue `#81` to avoid mixed scope and output contract churn.

**Tech Stack:** Bash, mocked CLI binaries in unit tests, `jq` for config parsing.

---

### Task 1: Add Failing Health Command Tests

**Files:**
- Create: `tests/unit/test_sbx_manager_health.sh`

**Step 1: Write the failing test**

Add tests for:
- healthy environment returns exit code `0` and contains `[OK]` checks
- failing environment returns non-zero and contains `[FAIL]`
- warning-only environment returns `0` and contains `[WARN]`

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh
```

Expected: fail because `sbx health` is not implemented yet.

**Step 3: Write minimal implementation**

Do not implement in this task.

**Step 4: Run test to verify it passes**

Do after Task 2.

**Step 5: Commit**

```bash
git add tests/unit/test_sbx_manager_health.sh
git commit -m "test: add sbx health command coverage"
```

### Task 2: Implement Health Command In sbx-manager

**Files:**
- Modify: `bin/sbx-manager.sh`

**Step 1: Write the failing test**

Covered by Task 1.

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh
```

Expected: fail due missing command/behavior.

**Step 3: Write minimal implementation**

Implement:
- `health` command entry in CLI case statement
- health checks:
  - `systemctl is-active`
  - `sing-box check -c <config>`
  - configured port listeners (`tcp`/`udp`) from config
  - certificate expiry warning (<30d)
  - deprecated `sniff` / `sniff_override_destination` warning
- deterministic report with exit code:
  - fail count > 0 -> exit `1`
  - otherwise exit `0`

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh
```

Expected: pass.

**Step 5: Commit**

```bash
git add bin/sbx-manager.sh tests/unit/test_sbx_manager_health.sh
git commit -m "feat: add sbx health runtime diagnostics"
```

### Task 3: Update Help & Docs

**Files:**
- Modify: `bin/sbx-manager.sh`
- Modify: `README.md`

**Step 1: Write the failing test**

Use assertion in health test or smoke check for usage output containing `health`.

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh
```

Expected: usage assertion fails before docs/help update.

**Step 3: Write minimal implementation**

Add `health` in:
- CLI usage section in `sbx-manager`
- README usage/troubleshooting commands

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh
```

Expected: pass.

**Step 5: Commit**

```bash
git add bin/sbx-manager.sh README.md tests/unit/test_sbx_manager_health.sh
git commit -m "docs: expose sbx health command"
```

### Task 4: Verification Before Completion

**Files:**
- Modify: none

**Step 1: Write the failing test**

N/A.

**Step 2: Run test to verify it fails**

N/A.

**Step 3: Write minimal implementation**

N/A.

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_sbx_manager_health.sh && \
bash tests/unit/test_sbx_manager_status.sh && \
bash tests/unit/test_sbx_manager_uri.sh && \
bash -n bin/sbx-manager.sh
```

Expected: all pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: verify sbx health feature"
```
