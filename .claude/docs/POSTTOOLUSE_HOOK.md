# PostToolUse Hook (Shell Formatting & Linting)

This project uses a **single PostToolUse hook** to run a safe, deterministic shell workflow after edits:

1. Format with `shfmt` (if installed)
2. Lint with `shellcheck` (if installed)

Hook script: `.claude/scripts/format-and-lint-shell.sh`

## Why a single hook (concurrency safety)

Claude Code runs all hooks that match an event **in parallel**. If you configure separate format + lint hooks under the same matcher, you can hit race conditions:

- **stdin race**: multiple hooks reading stdin (`INPUT=$(cat)`) compete; one may get partial/empty JSON.
- **file race**: `shfmt -w` writes while `shellcheck` reads; results become non-deterministic (false positives/negatives).
- **ordering**: parallel hooks have no sequencing guarantee; you can lint unformatted code.

Therefore, we combine both operations in one script and run them **sequentially**.

## Output and exit-code best practices

This hook is designed to be low-noise:

- When lint passes (or ShellCheck is missing), it prints `{"suppressOutput": true}` and exits `0`.
- When ShellCheck reports issues, it prints a concise summary to stderr and exits `1` (non-blocking for interactive editing).
- Missing tool warnings are shown **once per session** using marker files:
  - `${TMPDIR:-/tmp}/sbx-<project>-shfmt-warning-shown[-<session_id>]`
  - `${TMPDIR:-/tmp}/sbx-<project>-shellcheck-warning-shown[-<session_id>]`

## Configuration consistency (ShellCheck)

Hook execution CWD is not guaranteed to be the repo root, so relying on auto-discovery of `.shellcheckrc` can be inconsistent.

To keep results aligned with CI/pre-commit, the hook prefers:

1. `$CLAUDE_PROJECT_DIR/.shellcheckrc` (when set)
2. `./.shellcheckrc` (if running in repo root)
3. `git rev-parse --show-toplevel` (fallback)

and runs ShellCheck with `--rcfile`.

## Configuration

Hook config lives in `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/format-and-lint-shell.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```
