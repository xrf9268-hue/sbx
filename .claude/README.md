# .claude/ Directory - Claude Code Configuration

This directory contains:
1. **Reference documentation** imported into CLAUDE.md for efficient context management
2. **SessionStart hook** for automatic environment setup in Claude Code web/iOS

## Automated Hooks

sbx-lite uses Claude Code hooks to automate development workflows:

### SessionStart Hook (Environment Setup)

When you start a new Claude Code session (web/iOS), automatically:
- ✅ Installs git hooks for code quality enforcement
- ✅ Verifies/installs dependencies (jq, openssl)
- ✅ Validates bootstrap constants configuration
- ✅ Displays project information and quick commands

### PostToolUse Hooks (Shell Formatting & Linting)

**UPDATED 2025-11-19:** After editing shell scripts (Edit/Write tools), automatically runs **sequential** format-then-lint workflow:

**Step 1 - Formatting (shfmt):**
- ✅ Formats bash files with `shfmt` (if installed)
- ✅ Enforces consistent style across 18 library modules
- ✅ Reduces pre-commit failures from formatting issues
- ✅ Non-blocking if `shfmt` unavailable (provides install instructions)

**Step 2 - Linting (ShellCheck):**
- ✅ Lints the **formatted** result with `shellcheck` (if installed)
- ✅ Catches code quality issues immediately after editing
- ✅ Shows warnings with line numbers and suggestions
- ✅ Non-blocking warnings (allows continued development)
- ✅ Reduces CI/CD failures from ShellCheck errors

**Why Sequential?** Prevents race conditions from parallel hook execution. See `.claude/docs/POSTTOOLUSE_HOOK.md` for details.

### Files

- **settings.json** - Hook configuration (committed)
- **settings.local.json** - User-specific overrides (gitignored)
- **scripts/session-start.sh** - SessionStart hook implementation
- **scripts/format-and-lint-shell.sh** - PostToolUse combined hook (sequential format→lint)
- **docs/POSTTOOLUSE_HOOK.md** - PostToolUse hook rationale and behavior

### How It Works

The SessionStart hook is triggered only on **new session startup** (not resume/clear):

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

### Hook Concurrency Best Practices ⚠️ IMPORTANT

**Critical Rule**: Multiple hooks under the same matcher run **in parallel** (per Claude Code design).

**Avoid These Patterns** (will cause race conditions):
```json
// ❌ BAD: Parallel hooks competing for same resources
"PostToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [
    {"command": "format-file.sh"},  // Modifies file
    {"command": "lint-file.sh"}     // Reads file (parallel!)
  ]
}]
```

**Use These Patterns Instead**:
```json
// ✅ GOOD: Single hook with sequential operations
"PostToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [
    {"command": "format-and-lint.sh"}  // Does both sequentially
  ]
}]
```

**Why?**
1. **stdin Consumption**: Each hook tries to read ALL of stdin → race condition
2. **File Modification**: One hook modifies while another reads → undefined behavior
3. **Execution Order**: No guarantee which runs first → non-deterministic results

**See Also**: `.claude/docs/POSTTOOLUSE_HOOK.md` for details.

### What Gets Installed

| Component | Purpose | Auto-Installed |
|-----------|---------|----------------|
| **Git Hooks** | Pre-commit validation | ✅ Yes (web/iOS) |
| **jq** | JSON processing | ✅ Yes (if missing) |
| **openssl** | Cryptographic operations | ✅ Yes (if missing) |
| **Bootstrap Tests** | Constant validation | ✅ Runs automatically |
| **shfmt** | Shell script formatter | ⚠️ Manual (see below) |
| **shellcheck** | Shell script linter | ⚠️ Manual (see below) |

### Installing Development Tools (Recommended)

To enable automatic shell formatting and linting:

```bash
# shellcheck - available via apt
sudo apt install shellcheck

# shfmt - NOT in apt repos, use one of these methods:
# Option 1: snap (recommended for Linux)
sudo snap install shfmt

# Option 2: Go
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Option 3: Direct binary download
wget -qO /usr/local/bin/shfmt https://github.com/mvdan/sh/releases/download/v3.10.0/shfmt_v3.10.0_linux_amd64
sudo chmod +x /usr/local/bin/shfmt

# macOS
brew install shfmt shellcheck

# Verify installation
shfmt --version
shellcheck --version
```

**Without shfmt/shellcheck:** Hooks will show helpful install instructions but won't block your work.

### Desktop vs Web Behavior

- **Claude Code Web/iOS** (`CLAUDE_CODE_REMOTE=true`): Full auto-setup
- **Desktop**: Shows manual installation instructions

### Bypassing for Testing

To disable the hook temporarily:
1. Create `.claude/settings.local.json`:
   ```json
   {
     "hooks": {
       "SessionStart": []
     }
   }
   ```
2. Restart Claude session

## Reference Documentation

### CODING_STANDARDS.md (107 lines)
Bash coding standards and best practices:
- Security practices (strict mode, quoting, input validation)
- Error handling patterns (A/B/C)
- Common pitfalls and solutions
- Code quality standards
- Validation patterns

**When to reference:** When writing or reviewing bash code

### CONSTANTS_REFERENCE.md (87 lines)
Quick lookup for all project constants:
- 17+ constants organized by category
- Helper function reference (8 functions)
- Best practices for creating new constants
- Usage examples

**When to reference:** When using constants or creating new ones

## How Imports Work

CLAUDE.md uses `@path/to/file` syntax to import these files:

```markdown
**Detailed coding standards:** @.claude/CODING_STANDARDS.md
**Constants reference:** @.claude/CONSTANTS_REFERENCE.md
```

Claude Code automatically loads these files when:
- You reference them in conversation
- Claude needs the information to complete a task
- You explicitly ask about standards or constants

## Benefits

**Performance:**
- 67% reduction in base context load (715 → 232 lines)
- Faster session initialization
- More efficient token usage

**Organization:**
- Core instructions in CLAUDE.md
- Detailed reference in .claude/ files
- Easy to maintain and update

**Scalability:**
- Add new reference files without bloating main file
- Modular structure supports growth
- Clear separation of concerns

## Usage Tips

**For frequently used info:** Keep in main CLAUDE.md
**For detailed reference:** Move to .claude/ files with @import
**For project-specific:** Use CLAUDE.md
**For personal preferences:** Use ~/.claude/CLAUDE.md (user memory)

## Official Documentation

See: https://docs.claude.com/docs/claude-code/memory-management
