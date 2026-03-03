# File Locking For Critical Writes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent concurrent `sbx` invocations from racing on configuration/service write paths by introducing a shared file lock helper and applying it to critical mutation flows.

**Architecture:** Add a reusable `with_flock` wrapper in `lib/common.sh` that acquires an exclusive lock on `/var/lock/sbx.lock` (fallback `/tmp/sbx.lock`) and executes a target command within the lock scope. Then use this wrapper at the top-level mutation functions (`write_config`, `backup_restore`, `restart_service`) so the lock boundary is coarse, safe, and low-risk.

**Tech Stack:** Bash, `flock`, existing sbx unit-test shell framework.

---

### Task 1: Add Failing Tests For Locking Surface

**Files:**
- Modify: `tests/unit/test_common_helpers.sh`
- Modify: `tests/unit/test_config_write.sh`
- Modify: `tests/unit/test_backup_internal.sh`
- Modify: `tests/unit/test_service_functions.sh`

**Step 1: Write the failing test**

Add tests that assert:
- `with_flock` function exists in common module
- `write_config` uses `with_flock`
- `backup_restore` uses `with_flock`
- `restart_service` uses `with_flock`

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_common_helpers.sh
bash tests/unit/test_config_write.sh
bash tests/unit/test_backup_internal.sh
bash tests/unit/test_service_functions.sh
```

Expected: At least the new locking assertions fail.

**Step 3: Write minimal implementation**

Do not implement here (Task 2/3).

**Step 4: Run test to verify it passes**

Do after Task 3.

**Step 5: Commit**

```bash
git add tests/unit/test_common_helpers.sh tests/unit/test_config_write.sh tests/unit/test_backup_internal.sh tests/unit/test_service_functions.sh
git commit -m "test: add locking expectations for critical write paths"
```

### Task 2: Implement Shared Lock Helper

**Files:**
- Modify: `lib/common.sh`

**Step 1: Write the failing test**

Covered in Task 1 (`with_flock` existence expectation).

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_common_helpers.sh
```

Expected: lock helper assertion fails.

**Step 3: Write minimal implementation**

Add:
- `with_flock()` in `lib/common.sh`
- lock file defaulting to `/var/lock/sbx.lock`, fallback to `/tmp/sbx.lock`
- optional timeout argument default `30`
- safe fallback when `flock` is unavailable: run command directly with warning

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_common_helpers.sh
```

Expected: helper tests pass.

**Step 5: Commit**

```bash
git add lib/common.sh tests/unit/test_common_helpers.sh
git commit -m "feat: add shared with_flock helper"
```

### Task 3: Apply Locking To Critical Mutations

**Files:**
- Modify: `lib/config.sh`
- Modify: `lib/backup.sh`
- Modify: `lib/service.sh`

**Step 1: Write the failing test**

Covered in Task 1 (call-site expectations in unit tests).

**Step 2: Run test to verify it fails**

Run:
```bash
bash tests/unit/test_config_write.sh
bash tests/unit/test_backup_internal.sh
bash tests/unit/test_service_functions.sh
```

Expected: call-site locking assertions fail.

**Step 3: Write minimal implementation**

Wrap mutation bodies with `with_flock`:
- `write_config` in `lib/config.sh`
- `backup_restore` in `lib/backup.sh`
- `restart_service` in `lib/service.sh`

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_common_helpers.sh
bash tests/unit/test_config_write.sh
bash tests/unit/test_backup_internal.sh
bash tests/unit/test_service_functions.sh
```

Expected: all pass.

**Step 5: Commit**

```bash
git add lib/config.sh lib/backup.sh lib/service.sh tests/unit/test_config_write.sh tests/unit/test_backup_internal.sh tests/unit/test_service_functions.sh
git commit -m "feat: add file locking for critical write operations"
```

### Task 4: Final Verification

**Files:**
- Modify: none
- Test: `tests/unit/test_common_helpers.sh`
- Test: `tests/unit/test_config_write.sh`
- Test: `tests/unit/test_backup_internal.sh`
- Test: `tests/unit/test_service_functions.sh`

**Step 1: Write the failing test**

N/A (verification task).

**Step 2: Run test to verify it fails**

N/A.

**Step 3: Write minimal implementation**

N/A.

**Step 4: Run test to verify it passes**

Run:
```bash
bash tests/unit/test_common_helpers.sh && \
bash tests/unit/test_config_write.sh && \
bash tests/unit/test_backup_internal.sh && \
bash tests/unit/test_service_functions.sh
```

Expected: all commands exit `0`.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: verify locking implementation for issue #83"
```
