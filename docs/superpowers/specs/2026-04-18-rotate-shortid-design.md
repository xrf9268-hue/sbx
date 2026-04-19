# Reality Short ID Rotation Design

Date: 2026-04-18

Status: approved for planning

## Goal

Add an end-to-end Reality short ID rotation feature that supports:

- manual rotation via `sbx rotate-shortid`
- preview via `--dry-run`
- scheduled rotation via `systemd` timer
- automatic refresh of server-side export and subscription sources
- structured audit history in `state.json`

## Design Principles

- Treat this feature as new product surface, not as a compatibility patch.
- Do not add cron support, legacy aliases, or alternate schedule syntaxes unless they are required by the current repository.
- Keep only the minimum compatibility needed to avoid breaking the current primary runtime paths.
- Prefer one coherent state model, one scheduler model, and one execution path for both manual and scheduled rotation.
- Fail closed. If validation or restart fails, the old short ID must remain active or be restored.

## Scope

### In scope

- `sbx rotate-shortid` command family
- `--dry-run`
- `--schedule {daily|weekly|monthly|off}`
- dedicated `systemd` service and timer for scheduled rotation
- `config.json`, `client-info.txt`, and `state.json` updates
- subscription cache refresh after successful rotation
- audit logging in `state.json` and `systemd` journal
- unit tests
- remote VM runtime verification

### Out of scope

- cron support
- arbitrary custom `OnCalendar` expressions
- client-side push updates to already imported remote devices
- installer-time auto-enable of short ID rotation
- preserving undocumented legacy short ID rotation state shapes

## Existing Code Anchors

- CLI entrypoint: `bin/sbx-manager.sh`
- install/uninstall flow: `install.sh`
- subscription cache and unit patterns: `lib/subscription.sh`
- generic service helpers: `lib/service.sh`
- config writers and Reality config shape: `lib/config.sh`
- export pipeline reading `state.json` and `client-info.txt`: `lib/export.sh`
- state locking helpers: `lib/common.sh`

## Architecture

### 1. CLI boundary

`bin/sbx-manager.sh` will add a new top-level command:

- `sbx rotate-shortid`

Supported forms:

- `sbx rotate-shortid`
- `sbx rotate-shortid --dry-run`
- `sbx rotate-shortid --schedule daily`
- `sbx rotate-shortid --schedule weekly`
- `sbx rotate-shortid --schedule monthly`
- `sbx rotate-shortid --schedule off`

Internal-only invocation for `systemd`:

- `sbx rotate-shortid --scheduled-run`

The CLI layer only parses arguments, enforces incompatible flag combinations, checks root requirement where needed, and delegates to the rotation module.

### 2. Rotation module

Add a new module:

- `lib/reality_rotation.sh`

Responsibilities:

- generate a new valid short ID
- ensure the new short ID differs from the current one
- update the Reality short ID in `config.json`
- update `SHORT_ID` in `client-info.txt`
- update current short ID and rotation metadata in `state.json`
- validate candidate config before replacing the live config
- restart `sing-box`
- refresh subscription cache when enabled
- install, remove, and inspect the rotation `systemd` timer
- emit audit output for manual and scheduled runs

This module owns the feature. The logic must not be spread across `sbx-manager.sh` and `install.sh`.

### 3. Scheduler model

Use only `systemd`:

- `sbx-shortid-rotate.service`
- `sbx-shortid-rotate.timer`

`service` type:

- `Type=oneshot`
- `ExecStart=/usr/local/bin/sbx rotate-shortid --scheduled-run`

`timer` schedule mapping:

- `daily` -> `OnCalendar=daily`
- `weekly` -> `OnCalendar=weekly`
- `monthly` -> `OnCalendar=monthly`

Required timer properties:

- `Persistent=true`

Rationale:

- matches current Debian 12 VM environment
- keeps audit trail in `journalctl`
- aligns with existing repository use of `systemd` units
- avoids carrying a second scheduling mechanism

## State Model

Keep the current live short ID at:

- `.protocols.reality.short_id`

Add a nested rotation state object at:

- `.protocols.reality.short_id_rotation`

Proposed shape:

```json
{
  "protocols": {
    "reality": {
      "short_id": "cafebabe",
      "short_id_rotation": {
        "enabled": true,
        "schedule": "weekly",
        "on_calendar": "weekly",
        "last_rotated_at": "2026-04-18T12:34:56Z",
        "last_trigger": "manual",
        "last_result": "success",
        "history": [
          {
            "at": "2026-04-18T12:34:56Z",
            "trigger": "manual",
            "old_short_id": "abcd1234",
            "new_short_id": "cafebabe",
            "result": "success"
          }
        ]
      }
    }
  }
}
```

Rules:

- `.protocols.reality.short_id` is the single source of truth for the active runtime short ID.
- `short_id_rotation.history` stores newest-first entries.
- History length is capped at 20 entries.
- `schedule` accepts only `daily`, `weekly`, `monthly`, or `off`.
- When schedule is `off`, `enabled=false` and `on_calendar=null`.
- Manual rotations update `last_trigger=manual`.
- Scheduled rotations update `last_trigger=timer`.
- Failed attempts append a failure history entry and update `last_result=failed`.

## Command Semantics

### `sbx rotate-shortid`

- Requires root.
- Rotates immediately.
- Updates runtime files and restarts `sing-box`.
- Refreshes subscription cache if subscription is enabled.
- Writes success or failure audit state.

### `sbx rotate-shortid --dry-run`

- Requires root.
- Generates a candidate short ID.
- Validates a temporary config with the candidate short ID.
- Does not modify live files.
- Does not restart services.
- Does not update timer state.
- Prints the old short ID, candidate short ID, and affected resources.

### `sbx rotate-shortid --schedule <value>`

- Requires root.
- Only updates scheduling state and timer installation.
- Does not trigger an immediate rotation.
- Accepted values: `daily`, `weekly`, `monthly`, `off`.

### `sbx rotate-shortid --scheduled-run`

- Internal-only path for the timer service.
- Reuses the exact same rotation code path as manual execution.
- Records trigger type as `timer`.

### Invalid combinations

These must fail fast with a clear error:

- `--dry-run` with `--schedule`
- `--scheduled-run` with `--dry-run`
- `--scheduled-run` with `--schedule`
- unknown schedule value

## Rotation Flow

### Successful rotation

1. Acquire the repository state lock.
2. Read current short ID from `state.json` or `client-info.txt`, preferring `state.json`.
3. Generate a new short ID using the existing validation rules.
4. Ensure new short ID is different from the current short ID.
5. Build a temporary candidate `config.json` with the new short ID applied to all Reality inbounds.
6. Run `sing-box check -c <temp_config>`.
7. If `--dry-run`, print the preview and exit success.
8. Create backups of live `config.json`, `client-info.txt`, and `state.json`.
9. Atomically replace live `config.json`.
10. Atomically replace live `client-info.txt`.
11. Atomically update `state.json` current short ID and rotation metadata.
12. Restart `sing-box` using the existing service helper path.
13. If subscription is enabled, call `subscription_refresh_cache`.
14. Append success audit entry and trim history to 20.
15. Print the new short ID and any updated subscription/export context.

### Failure handling

Failure cases:

- candidate config generation fails
- `sing-box check` fails
- file replacement fails
- restart fails
- subscription refresh fails after successful restart

Handling rules:

- If failure occurs before live file replacement, leave all live files unchanged.
- If failure occurs after partial replacement but before successful restart, restore backed-up files and restart with the old config.
- If subscription refresh fails after a successful restart, keep the new short ID active but record the failure in audit state and stderr output.
- Scheduled runs must surface errors through `journalctl -u sbx-shortid-rotate.service`.

## File Mutation Rules

### `config.json`

- Update every Reality inbound `tls.reality.short_id` to a single-element array containing the new short ID.
- Do not rewrite unrelated protocol blocks.

### `client-info.txt`

- Update `SHORT_ID="<new_sid>"`.
- Preserve existing supported keys and file permissions.
- Use the same secure ownership and permission rules as the current installer output.

### `state.json`

- Update `.protocols.reality.short_id`.
- Create or update `.protocols.reality.short_id_rotation`.
- Append success or failure history entry.
- Trim history to 20 entries.

## Subscription and Export Behavior

After a successful rotation:

- `lib/export.sh` must resolve the new short ID through the updated live sources.
- If the subscription endpoint is enabled, `subscription_refresh_cache` must rebuild its cached payloads.
- The feature guarantees that newly fetched export output and subscription responses reflect the new short ID.

The feature does not attempt to mutate configuration files already imported onto external client devices.

## Install and Uninstall Integration

### Install side

- Ensure `lib/reality_rotation.sh` is installed alongside other runtime libraries.
- Ensure `sbx-manager` help text includes the new command.
- Do not auto-enable the timer on install.

### Uninstall side

`install.sh` uninstall flow must remove:

- `sbx-shortid-rotate.service`
- `sbx-shortid-rotate.timer`

This cleanup should follow the repository's current best-effort `systemd` removal pattern.

## Testing Strategy

### Unit tests

Add unit coverage for:

- manual rotation updates `config.json`, `client-info.txt`, and `state.json`
- `--dry-run` validates candidate config but leaves live files untouched
- generated short ID differs from previous value
- history is appended and trimmed to 20 entries
- `--schedule` writes state and installs or removes timer correctly
- invalid flag combinations fail
- restart failure triggers rollback
- subscription refresh is called only when enabled

### AWS VM runtime verification

Run on the VM:

- `bash tests/test-runner.sh unit`
- `bash scripts/e2e/install-lifecycle-smoke.sh`

Additional targeted VM validation:

- install or update the timer with `sbx rotate-shortid --schedule weekly`
- inspect `systemctl status sbx-shortid-rotate.timer`
- manually trigger the timer service
- verify `config.json`, `client-info.txt`, `state.json`, and subscription cache reflect the new short ID
- verify failure and recovery path if runtime validation exposes one

## No-Debt Decisions

These are intentional, not follow-up debt:

- no cron path
- no arbitrary schedule strings
- no second compatibility state block outside `.protocols.reality.short_id_rotation`
- no separate code path for scheduled rotation beyond trigger labeling
- no attempt to preserve undocumented historical rotation formats

## Planning Notes

Implementation should use TDD:

1. write failing tests for rotation behavior and timer behavior
2. implement the minimal rotation module
3. wire CLI entrypoints
4. wire install and uninstall integration
5. run unit and VM verification

This design is ready to move into an implementation plan once the user reviews the written spec.
