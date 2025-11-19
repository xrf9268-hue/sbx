# Claude Code Hooks Guide for sbx-lite

This guide explains how Claude Code hooks automate development workflows in sbx-lite.

## Overview

sbx-lite uses two types of hooks to maintain code quality:

| Hook Type | When It Runs | Purpose |
|-----------|--------------|---------|
| **SessionStart** | New session startup | Environment setup, dependency installation |
| **PostToolUse** | After Edit/Write tools | Automatic shell script formatting & linting |

## SessionStart Hook

**File:** `.claude/scripts/session-start.sh`

**Triggered by:** Starting a new Claude Code session (web/iOS)

**What it does:**
1. Installs git pre-commit hooks for validation
2. Verifies/installs dependencies (jq, openssl, bash)
3. Validates bootstrap constants configuration
4. Displays project information and quick commands

**Configuration:**
```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "startup",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/session-start.sh"
      }]
    }]
  }
}
```

**Benefits:**
- ✅ Consistent development environment across sessions
- ✅ Catches configuration issues early
- ✅ No manual setup required for new contributors
- ✅ Works seamlessly in Claude Code web/iOS

---

## PostToolUse Hook (Combined Format & Lint)

**File:** `.claude/scripts/format-and-lint-shell.sh`

**Triggered by:** Edit or Write operations on `.sh` files

**What it does:**
1. Detects shell script edits (`.sh` files, `install_multi.sh`)
2. **Step 1:** Formats code with `shfmt` (if installed)
3. **Step 2:** Lints the **formatted** result with `shellcheck` (if installed)
4. Provides install instructions if tools missing

**Why Sequential?** Combines formatting and linting into a single script to avoid race conditions from parallel hook execution. See `.claude/docs/POSTTOOLUSE_HOOKS_FIX.md` for details.

**Configuration:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/format-and-lint-shell.sh",
        "timeout": 15
      }]
    }]
  }
}
```

**Formatting Rules (shfmt):**
- `-i 2` - 2-space indentation (matches project style)
- `-bn` - Binary ops like `&&` and `|` may start a line
- `-ci` - Switch cases indented
- `-sr` - Space after redirect operators
- `-kp` - Keep column alignment padding

**Linting Rules (shellcheck):**
- `-S warning` - Show warnings and above (matches pre-commit hook)
- `-e SC2250` - Exclude style preferences (consistent with pre-commit)
- Runs same checks as `hooks/pre-commit` for consistency

**Benefits:**
- ✅ Automatic formatting + linting after every edit
- ✅ Consistent style across 18 library modules
- ✅ Lints the formatted result (not the original)
- ✅ No race conditions from parallel execution
- ✅ Reduces pre-commit failures from formatting/linting
- ✅ Non-blocking if tools unavailable
- ✅ Clear feedback on formatting and linting status

---

## Installing Development Tools

The PostToolUse hooks require `shfmt` for formatting and `shellcheck` for linting.

### Debian/Ubuntu
```bash
sudo apt update
sudo apt install shfmt shellcheck
```

### macOS
```bash
brew install shfmt shellcheck
```

### Go (Any Platform)
```bash
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Ensure $GOPATH/bin is in your PATH
export PATH="$PATH:$(go env GOPATH)/bin"
```

### Verify Installation
```bash
shfmt --version
# Expected: v3.x.x or later

shellcheck --version
# Expected: 0.x.x or later
```

---

## Hook Behavior

### When shfmt is Available

**Scenario 1: File already formatted**
```
✓ Shell script already formatted: config.sh
```
- Hook exits successfully (code 0)
- No changes made to file
- No noise in transcript

**Scenario 2: File needs formatting**
```
✓ Auto-formatted shell script: network.sh
```
- Hook formats file in-place
- Returns JSON with `suppressOutput: true` to reduce transcript clutter
- User sees system message: "Shell script auto-formatted with shfmt"

**Scenario 3: Syntax error**
```
✗ Failed to format lib/broken.sh - syntax error?
  Run: shfmt -d lib/broken.sh
```
- Hook exits with code 1 (non-blocking warning)
- File not modified
- User can continue working

### When shfmt is NOT Available

```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  Shell Formatter Not Installed                           │
├─────────────────────────────────────────────────────────────┤
│ Install shfmt for automatic shell script formatting:        │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shfmt                    │
│   macOS:          brew install shfmt                        │
│   Go:             go install mvdan.cc/sh/v3/cmd/shfmt@latest│
│                                                              │
│ Your code is valid but not auto-formatted.                  │
└─────────────────────────────────────────────────────────────┘
```
- Hook exits with code 1 (non-blocking warning)
- Clear installation instructions provided
- User can continue working
- Pre-commit hooks will still validate code

### When shellcheck is Available

**Scenario 1: File passes linting**
```
✓ ShellCheck passed: config.sh
```
- Hook exits successfully (code 0)
- No issues found
- Returns JSON with `suppressOutput: true` to reduce transcript clutter

**Scenario 2: File has warnings**
```
⚠ ShellCheck found 3 issue(s) in network.sh:

  In network.sh line 45:
  SC2086: Double quote to prevent globbing and word splitting

  In network.sh line 67:
  SC2046: Quote this to prevent word splitting

  In network.sh line 89:
  SC2155: Declare and assign separately to avoid masking return values

ℹ To see details, run: shellcheck network.sh
ℹ To disable specific warnings, add: # shellcheck disable=SC####
```
- Hook exits with code 1 (non-blocking warning)
- Shows detailed warnings with line numbers
- User can continue working or fix issues
- Provides helpful commands to run

**Scenario 3: File has errors**
```
⚠ ShellCheck found 2 issue(s) in broken.sh:

  In broken.sh line 23:
  SC1009: The mentioned syntax error was in this if expression

  In broken.sh line 25:
  SC1073: Couldn't parse this test expression
```
- Hook exits with code 1 (non-blocking warning)
- Shows detailed errors
- User can fix and re-edit

### When shellcheck is NOT Available

```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  ShellCheck Not Installed                                │
├─────────────────────────────────────────────────────────────┤
│ Install ShellCheck for automatic shell script linting:      │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shellcheck               │
│   macOS:          brew install shellcheck                   │
│   Snap:           sudo snap install shellcheck              │
│   Go:             go install github.com/koalaman/shellcheck │
│                                                              │
│ Your code will be validated in pre-commit and CI/CD.        │
└─────────────────────────────────────────────────────────────┘
```
- Hook exits with code 1 (non-blocking warning)
- Clear installation instructions provided
- User can continue working
- Pre-commit and CI/CD hooks will still validate code

---

## Interaction with Pre-Commit Hooks

The PostToolUse and pre-commit hooks work together:

### PostToolUse (Real-Time)
- **When:** After every Edit/Write
- **What:** Formats and lints code automatically
- **Benefit:** Catch style and quality issues immediately

### Pre-Commit (Before Commit)
- **When:** During `git commit`
- **What:** Validates syntax, strict mode, ShellCheck, constants
- **Benefit:** Ensures quality before commit

### Workflow Example

```
1. Edit lib/network.sh
   └─→ PostToolUse hooks:
       ✓ Format with shfmt
       ✓ Lint with shellcheck

2. Continue working...

3. git commit
   └─→ Pre-commit hook validates:
       ✓ Bash syntax
       ✓ Bootstrap constants
       ✓ Strict mode
       ✓ ShellCheck (again, for safety)
       ✓ Unbound variables

4. Commit succeeds ✓
```

**Result:** Code is formatted, linted, AND validated at multiple stages!

---

## Customization

### Disable PostToolUse Hook Temporarily

Create `.claude/settings.local.json` (gitignored):

```json
{
  "hooks": {
    "PostToolUse": []
  }
}
```

**Note:** Restart Claude session for changes to take effect.

### Adjust Formatting Style

Edit `.claude/scripts/format-and-lint-shell.sh` and modify `shfmt` flags:

```bash
# Current style (2-space, binary ops on new line, etc.)
shfmt -w -i 2 -bn -ci -sr -kp "$FILE_PATH"

# Alternative: 4-space indentation, stricter style
shfmt -w -i 4 -bn -ci "$FILE_PATH"

# See: shfmt --help for all options
```

### Add More File Patterns

Edit the pattern matching in `format-and-lint-shell.sh`:

```bash
# Current: Only .sh files and install_multi.sh
if [[ ! "$FILE_PATH" =~ \.(sh)$ ]] && [[ ! "$FILE_PATH" != "install_multi.sh" ]]; then
    exit 0
fi

# Add: Also format files without extension that have bash shebang
if [[ ! "$FILE_PATH" =~ \.(sh)$ ]] && ! grep -q "^#!/usr/bin/env bash" "$FILE_PATH" 2>/dev/null; then
    exit 0
fi
```

---

## Debugging

### Check Hook Status

```bash
# In Claude Code, run:
/hooks

# Expected output shows:
# - SessionStart hook registered
# - PostToolUse hook registered
```

### Test Hook Manually

```bash
# Create test input (simulates Edit tool on lib/common.sh)
cat > /tmp/test-hook-input.json <<'EOF'
{
  "session_id": "test",
  "hook_event_name": "PostToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/home/user/sbx/lib/common.sh"
  }
}
EOF

# Run hook manually
cat /tmp/test-hook-input.json | .claude/scripts/format-and-lint-shell.sh

# Should see:
# ✓ Shell script already formatted: common.sh
# ✓ ShellCheck passed: common.sh
# (or)
# ✓ Auto-formatted shell script: common.sh
# ✓ ShellCheck passed: common.sh
```

### Enable Debug Mode

Run Claude Code with debug logging:

```bash
claude --debug

# You'll see:
# [DEBUG] Executing hooks for PostToolUse:Edit
# [DEBUG] Found 1 hook commands to execute
# [DEBUG] Hook command completed with status 0
```

### Common Issues

**Issue 1: Hook not running**
- Check `/hooks` to verify registration
- Ensure file has `.sh` extension or is `install_multi.sh`
- Verify `.claude/scripts/format-and-lint-shell.sh` is executable: `ls -la .claude/scripts/`

**Issue 2: "shfmt: command not found"**
- Install shfmt (see installation section above)
- Verify: `which shfmt` shows path

**Issue 3: Formatting changes not applied**
- Check hook output in verbose mode (Ctrl+O)
- Verify syntax is valid: `bash -n your-file.sh`
- Test shfmt manually: `shfmt -d your-file.sh`

---

## Best Practices

### For Contributors

1. **Install development tools** - Install both shfmt and shellcheck for best experience
2. **Let hooks run** - Don't interrupt formatting/linting operations
3. **Review feedback** - Check formatting changes and linting warnings
4. **Fix issues early** - Address ShellCheck warnings right after editing
5. **Report issues** - If hooks behave unexpectedly, file an issue

### For Maintainers

1. **Keep hooks simple** - Complex logic belongs in pre-commit hooks
2. **Make hooks fast** - 10-second timeout is generous, aim for <1 second
3. **Provide fallbacks** - Non-blocking warnings if tools unavailable
4. **Document changes** - Update this guide when modifying hooks

---

## Performance

### Hook Execution Times

| Hook | Typical Duration | Timeout |
|------|------------------|---------|
| SessionStart | 2-5 seconds | 60s |
| PostToolUse: format-and-lint-shell.sh | 200ms-1s | 15s |

### File Size vs Performance

| File | Lines | Format Time | Lint Time | Total |
|------|-------|-------------|-----------|-------|
| lib/common.sh | 253 | ~100ms | ~150ms | ~250ms |
| lib/network.sh | 300+ | ~150ms | ~200ms | ~350ms |
| install_multi.sh | 600+ | ~300ms | ~400ms | ~700ms |

### Impact on Workflow

- **Minimal delay:** Formatting + linting happens in <1 second for most files
- **Sequential execution:** Format runs first, then lint (on formatted code)
- **Parallel with thinking:** Hooks don't block Claude's response generation
- **Smart skipping:** Clean files skip unnecessary processing

---

## Security Considerations

### Hook Execution Safety

- ✅ Hooks run in sandboxed environment with project permissions
- ✅ No network access required for formatting
- ✅ Only processes files you're already editing
- ✅ All hook scripts are committed to repository (reviewable)

### What Hooks CAN Do

- ✅ Read/write files in project directory
- ✅ Execute commands available in your PATH
- ✅ Access environment variables

### What Hooks CANNOT Do

- ❌ Modify system files (limited by user permissions)
- ❌ Access files outside project (without explicit paths)
- ❌ Run indefinitely (timeout enforced)

### Review Before Use

Before enabling hooks:
1. Read `.claude/scripts/format-and-lint-shell.sh` source code
2. Understand what commands it executes (`shfmt`, `shellcheck`)
3. Verify configuration in `.claude/settings.json`
4. Test in a safe branch first

---

## Further Reading

- **Official Hooks Docs:** https://docs.claude.com/docs/claude-code/hooks
- **shfmt Documentation:** https://github.com/mvdan/sh
- **Project Guidelines:** See `CONTRIBUTING.md`, `CLAUDE.md`
- **Git Hooks:** See `hooks/pre-commit` for validation logic

---

## Changelog

### 2025-11-19 - Combined Hook (Race Condition Fix)
- **BREAKING:** Combined separate format/lint hooks into single sequential script
- Created `.claude/scripts/format-and-lint-shell.sh` (combined format→lint workflow)
- Removed `.claude/scripts/format-shell.sh` (deprecated - had race conditions)
- Removed `.claude/scripts/lint-shell.sh` (deprecated - had race conditions)
- Updated `.claude/settings.json` to use combined hook
- Created `.claude/docs/POSTTOOLUSE_HOOKS_FIX.md` documenting concurrency issues
- **Why:** Prevents race conditions from parallel stdin consumption and file modification
- **Impact:** Same functionality, better reliability, deterministic behavior

### 2025-11-19 - Initial Implementation
- Added PostToolUse hooks for shell formatting and linting
- Created separate format and lint scripts (later combined due to race conditions)
- Updated `.claude/settings.json` configuration
- Documented in `.claude/README.md`

---

**Questions or Issues?**
- Open an issue on GitHub
- Check Claude Code documentation
- Review this guide's debugging section
