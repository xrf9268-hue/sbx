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

### PostToolUse Hook (Shell Formatting)

**NEW:** After editing shell scripts (Edit/Write tools), automatically:
- ✅ Formats bash files with `shfmt` (if installed)
- ✅ Enforces consistent style across 18 library modules
- ✅ Reduces pre-commit failures from formatting issues
- ✅ Non-blocking if `shfmt` unavailable (provides install instructions)

### Files

- **settings.json** - Hook configuration (committed)
- **settings.local.json** - User-specific overrides (gitignored)
- **scripts/session-start.sh** - SessionStart hook implementation
- **scripts/format-shell.sh** - PostToolUse hook for shell formatting

### How It Works

The hook is triggered only on **new session startup** (not resume/clear):

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

### What Gets Installed

| Component | Purpose | Auto-Installed |
|-----------|---------|----------------|
| **Git Hooks** | Pre-commit validation | ✅ Yes (web/iOS) |
| **jq** | JSON processing | ✅ Yes (if missing) |
| **openssl** | Cryptographic operations | ✅ Yes (if missing) |
| **Bootstrap Tests** | Constant validation | ✅ Runs automatically |
| **shfmt** | Shell script formatter | ⚠️ Manual (see below) |

### Installing shfmt (Recommended)

To enable automatic shell formatting:

```bash
# Debian/Ubuntu
sudo apt install shfmt

# macOS
brew install shfmt

# Go (any platform)
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Verify installation
shfmt --version
```

**Without shfmt:** Hooks will show helpful install instructions but won't block your work.

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
