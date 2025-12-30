# PostToolUse Hook Optimization (format-and-lint-shell.sh)

**Date:** 2025-11-20
**Optimization Type:** Output Verbosity Reduction + Performance

## Problem

The original PostToolUse hook for shell script formatting and linting was overly verbose:
- **ASCII box warnings** shown every time the hook ran (3 different boxes)
- **Color codes** in output (not useful in logs/verbose mode)
- **Excessive messages** for routine operations
- **186 lines** of code with significant duplication

**Context from Official Documentation:**
> PostToolUse hooks: Exit code 0 stdout shown to user in verbose mode (ctrl+o)

While PostToolUse output doesn't go to Claude's context (unlike SessionStart), it still appears in verbose mode and should be concise to avoid log spam and improve user experience.

## Solution

Refactored `.claude/scripts/format-and-lint-shell.sh` to be minimal, efficient, and user-friendly.

### Before (186 lines, verbose output)

**Missing tool warnings (shown EVERY execution):**
```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  Shell Formatter Not Installed                           │
├─────────────────────────────────────────────────────────────┤
│ Install shfmt for automatic shell script formatting:        │
│                                                              │
│   Linux (snap):   sudo snap install shfmt                   │
│   macOS:          brew install shfmt                        │
│   Go:             go install mvdan.cc/sh/v3/cmd/shfmt@latest│
│                                                              │
│ Your code is valid but not auto-formatted.                  │
└─────────────────────────────────────────────────────────────┘
```

**Success messages (with ANSI color codes):**
```
✓ Shell script already formatted: install-hooks.sh
✓ ShellCheck passed: install-hooks.sh
```

**Error messages (verbose with colors):**
```
⚠ ShellCheck found 3 issue(s) in install-hooks.sh:

  In install-hooks.sh line 42:
  SC2034: VAR appears unused. Verify use (or export if used externally).

  In install-hooks.sh line 58:
  SC2086: Double quote to prevent globbing and word splitting.

ℹ To see details, run: shellcheck "install-hooks.sh"
ℹ To disable specific warnings, add: # shellcheck disable=SC####
```

### After (113 lines, concise output)

**Missing tool warnings (shown ONCE per session):**
```
⚠ shfmt not installed. Install: snap install shfmt (or go install mvdan.cc/sh/v3/cmd/shfmt@latest)
```

**Success messages (no output - uses suppressOutput):**
```
{"suppressOutput": true}
```

**Formatting notifications (when changes made):**
```
✓ Formatted: install-hooks.sh
✓ ShellCheck passed: install-hooks.sh
```

**Error messages (concise):**
```
⚠ ShellCheck found 3 issue(s) in install-hooks.sh:
  In install-hooks.sh line 42:
  SC2034: VAR appears unused. Verify use (or export if used externally).
  In install-hooks.sh line 58:
  SC2086: Double quote to prevent globbing and word splitting.
  → Run: shellcheck "install-hooks.sh"
  → Disable: # shellcheck disable=SC####
```

## Improvements

### Quantitative
- **Code size:** 186 lines → 113 lines (39% reduction)
- **ASCII boxes:** 3 boxes (36 lines) → 0 boxes
- **Color codes:** Removed all ANSI escape sequences
- **Warning spam:** Every run → Once per session

### Qualitative

1. **Removed:**
   - All ASCII box borders and decorative elements
   - ANSI color codes (not rendered in logs)
   - Verbose success messages when nothing changed
   - Redundant formatting indicators
   - Multi-line installation instructions

2. **Added:**
   - **Session-based warning suppression** using temporary marker files
     - `/tmp/sbx-shfmt-warning-shown` - Tracks shfmt warning shown
     - `/tmp/sbx-shellcheck-warning-shown` - Tracks shellcheck warning shown
     - Warnings shown only ONCE per session, not on every file edit
   - **suppressOutput JSON** when everything is clean
   - More compact error formatting

3. **Preserved:**
   - All functionality (format → lint sequentially)
   - Race condition prevention
   - Detailed error messages when issues found
   - Actionable guidance for fixing issues

## Key Optimization: Session-Based Warning Suppression

**Problem:** Original hook showed missing tool warnings on EVERY file edit:
```
Edit file 1 → "shfmt not installed" warning
Edit file 2 → "shfmt not installed" warning (again!)
Edit file 3 → "shfmt not installed" warning (again!)
...
```

**Solution:** Show warnings only once per session:
```bash
SHFMT_WARNING_FILE="/tmp/sbx-shfmt-warning-shown"

if [[ ! -f "$SHFMT_WARNING_FILE" ]]; then
    # Note: shfmt is NOT in apt repos - use snap/go/binary
    echo "⚠ shfmt not installed. Install: snap install shfmt" >&2
    touch "$SHFMT_WARNING_FILE"
fi
```

**Result:**
```
Edit file 1 → "shfmt not installed" warning
Edit file 2 → (no warning)
Edit file 3 → (no warning)
...
```

User sees the warning once, avoids repetition fatigue, warnings automatically reset on new session.

## Best Practices Applied

1. **Minimal Success Output:** Use `suppressOutput: true` when everything is clean
2. **Concise Error Messages:** Show only essential information
3. **Avoid Repetition:** Warnings shown once per session, not per file
4. **Remove Decorative Elements:** No ASCII boxes, color codes, or borders
5. **Actionable Guidance:** When errors occur, show clear next steps

## Design Principles for PostToolUse Hooks

Based on Claude Code official documentation and best practices:

### DO:
- ✅ Suppress output when everything is clean (`suppressOutput: true`)
- ✅ Show concise messages for actual changes (formatting applied)
- ✅ Display detailed errors only when issues found
- ✅ Avoid repetitive warnings (use session markers)
- ✅ Remove decorative elements (boxes, colors, banners)

### DON'T:
- ❌ Show success messages for every file when nothing changed
- ❌ Use ASCII art or decorative borders
- ❌ Include ANSI color codes (not rendered in logs)
- ❌ Repeat warnings on every invocation
- ❌ Output verbose installation instructions every time

## Testing

```bash
# Test with a clean file
echo '{"tool_name":"Write","tool_input":{"file_path":"hooks/install-hooks.sh"}}' | \
  bash .claude/scripts/format-and-lint-shell.sh

# Expected: {"suppressOutput": true}

# Test with missing tool (first time)
echo '{"tool_name":"Write","tool_input":{"file_path":"test.sh"}}' | \
  bash .claude/scripts/format-and-lint-shell.sh

# Expected: Warning shown once

# Test again (second time)
echo '{"tool_name":"Write","tool_input":{"file_path":"test.sh"}}' | \
  bash .claude/scripts/format-and-lint-shell.sh

# Expected: No warning (already shown in this session)
```

## Performance Impact

**Before:**
- Average output per file: ~10 lines (success) or ~20 lines (warnings)
- 10 file edits = 100-200 lines of hook output

**After:**
- Average output per file: 0 lines (clean) or 1-2 lines (formatted)
- 10 file edits = 0-20 lines of hook output
- **90% reduction in verbose mode output**

## Impact on User Experience

### Before (Verbose)
User edits 5 shell scripts in a row:
```
✓ Shell script already formatted: file1.sh
✓ ShellCheck passed: file1.sh
✓ Shell script already formatted: file2.sh
✓ ShellCheck passed: file2.sh
✓ Shell script already formatted: file3.sh
✓ ShellCheck passed: file3.sh
✓ Shell script already formatted: file4.sh
✓ ShellCheck passed: file4.sh
✓ Shell script already formatted: file5.sh
✓ ShellCheck passed: file5.sh
```
**Total:** 10 lines of output (nothing useful)

### After (Concise)
User edits 5 shell scripts in a row:
```
(no output - suppressOutput: true)
```
**Total:** 0 lines of output

Only shows output when:
1. File actually gets formatted: `✓ Formatted: file3.sh`
2. ShellCheck finds issues: `⚠ ShellCheck found 2 issue(s)...`
3. Missing tools (once): `⚠ shfmt not installed...`

## References

- **Official Docs:** [Hooks Reference - PostToolUse](https://docs.claude.com/en/docs/claude-code/hooks-reference#posttooluse)
- **Best Practice:** "stdout shown to user in verbose mode (ctrl+o)" - minimize noise
- **Related:** `.claude/docs/POSTTOOLUSE_HOOKS_FIX.md` - Race condition prevention
- **Related:** `.claude/docs/SESSION_START_OPTIMIZATION.md` - SessionStart hook optimization
