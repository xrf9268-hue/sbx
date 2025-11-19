# Claude Code Hooks Guide for sbx-lite

This guide explains how Claude Code hooks automate development workflows in sbx-lite.

## Overview

sbx-lite uses two types of hooks to maintain code quality:

| Hook Type | When It Runs | Purpose |
|-----------|--------------|---------|
| **SessionStart** | New session startup | Environment setup, dependency installation |
| **PostToolUse** | After Edit/Write tools | Automatic shell script formatting |

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

## PostToolUse Hook (Shell Formatting)

**File:** `.claude/scripts/format-shell.sh`

**Triggered by:** Edit or Write operations on `.sh` files

**What it does:**
1. Detects shell script edits (`.sh` files, `install_multi.sh`)
2. Formats code with `shfmt` (if installed)
3. Applies consistent style across all modules
4. Provides install instructions if `shfmt` missing

**Configuration:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/format-shell.sh",
        "timeout": 10
      }]
    }]
  }
}
```

**Formatting Rules:**
- `-i 2` - 2-space indentation (matches project style)
- `-bn` - Binary ops like `&&` and `|` may start a line
- `-ci` - Switch cases indented
- `-sr` - Space after redirect operators
- `-kp` - Keep column alignment padding

**Benefits:**
- ✅ Automatic formatting after every edit
- ✅ Consistent style across 18 library modules
- ✅ Reduces pre-commit failures from formatting
- ✅ Non-blocking if `shfmt` unavailable
- ✅ Clear feedback on what was formatted

---

## Installing shfmt

The PostToolUse hook requires `shfmt` for automatic formatting.

### Debian/Ubuntu
```bash
sudo apt update
sudo apt install shfmt
```

### macOS
```bash
brew install shfmt
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

---

## Interaction with Pre-Commit Hooks

The PostToolUse and pre-commit hooks work together:

### PostToolUse (Real-Time)
- **When:** After every Edit/Write
- **What:** Formats code automatically
- **Benefit:** Catch style issues immediately

### Pre-Commit (Before Commit)
- **When:** During `git commit`
- **What:** Validates syntax, strict mode, ShellCheck, constants
- **Benefit:** Ensures quality before commit

### Workflow Example

```
1. Edit lib/network.sh
   └─→ PostToolUse hook formats file ✓

2. Continue working...

3. git commit
   └─→ Pre-commit hook validates:
       ✓ Bash syntax
       ✓ Bootstrap constants
       ✓ Strict mode
       ✓ ShellCheck
       ✓ Unbound variables

4. Commit succeeds ✓
```

**Result:** Code is formatted AND validated automatically!

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

Edit `.claude/scripts/format-shell.sh` and modify `shfmt` flags:

```bash
# Current style (2-space, binary ops on new line, etc.)
shfmt -w -i 2 -bn -ci -sr -kp "$FILE_PATH"

# Alternative: 4-space indentation, stricter style
shfmt -w -i 4 -bn -ci "$FILE_PATH"

# See: shfmt --help for all options
```

### Add More File Patterns

Edit the pattern matching in `format-shell.sh`:

```bash
# Current: Only .sh files and install_multi.sh
if [[ ! "$FILE_PATH" =~ \.(sh)$ ]] && [[ ! "$FILE_PATH" == "install_multi.sh" ]]; then
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
cat /tmp/test-hook-input.json | .claude/scripts/format-shell.sh

# Should see:
# ✓ Shell script already formatted: common.sh
# (or)
# ✓ Auto-formatted shell script: common.sh
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
- Verify `.claude/scripts/format-shell.sh` is executable: `ls -la .claude/scripts/`

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

1. **Install shfmt** - Get the best experience with automatic formatting
2. **Let hooks run** - Don't interrupt formatting operations
3. **Review changes** - Check what was formatted before committing
4. **Report issues** - If formatting behaves unexpectedly, file an issue

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
| PostToolUse (shfmt available) | <500ms | 10s |
| PostToolUse (shfmt missing) | <100ms | 10s |

### Impact on Workflow

- **Minimal delay:** Formatting happens in <1 second typically
- **Parallel execution:** Hooks don't block Claude's thinking
- **Smart skipping:** Already-formatted files skip formatting

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
1. Read `.claude/scripts/format-shell.sh` source code
2. Understand what commands it executes (`shfmt`)
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

### 2025-11-19 - Initial Implementation
- Added PostToolUse hook for shell formatting
- Created `.claude/scripts/format-shell.sh`
- Updated `.claude/settings.json` configuration
- Documented in `.claude/README.md`

---

**Questions or Issues?**
- Open an issue on GitHub
- Check Claude Code documentation
- Review this guide's debugging section
