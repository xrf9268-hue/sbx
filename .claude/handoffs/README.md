# Handoffs Directory

This directory stores handoff files created by the `/handoff` command.

## Usage

**Create a handoff:**
```bash
/handoff "implement Reality validation"
```

**List available handoffs:**
```bash
/pickup
```

**Resume from handoff:**
```bash
/pickup 2025-11-22-implement-validation
```

## File Naming Convention

Handoff files follow this pattern:
```
YYYY-MM-DD-slug.md
```

Examples:
- `2025-11-22-reality-validation.md`
- `2025-11-23-module-split-refactor.md`
- `2025-11-24-bug-836-fix.md`

## Sensitive Data

⚠️ **Important:** Handoff files may contain:
- Code snippets
- Configuration examples
- Technical decisions
- File paths

**Before committing handoffs to git:**
- Remove or replace UUIDs with placeholders
- Remove server IPs
- Remove private keys or credentials
- Keep only structural/architectural information

## Cleanup

After PR is merged, you can:
- Delete the handoff: `rm .claude/handoffs/YYYY-MM-DD-slug.md`
- Archive it: Commit to git for historical reference

## See Also

- `.claude/WORKFLOWS.md` § "Session Continuity" - Comprehensive guide
- `CONTRIBUTING.md` § "Session Continuity" - Quick reference
- `.claude/commands/handoff.md` - Handoff command documentation
- `.claude/commands/pickup.md` - Pickup command documentation
