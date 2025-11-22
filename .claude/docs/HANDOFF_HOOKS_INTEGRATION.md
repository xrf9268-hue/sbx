# Handoff Hooks Integration

**Date:** 2025-11-22
**Purpose:** Integrate Claude Code hooks with handoff lifecycle management

---

## Overview

Two optional hooks enhance the handoff workflow:

1. **Stop Hook** - Reminds you to create handoffs for complex sessions
2. **SessionEnd Hook** - Auto-archives very old handoffs (>90 days)

---

## Hook 1: Stop Hook (Handoff Reminder)

### Purpose

Intelligently reminds you to create a handoff when:
- Session had substantial work (10+ conversation turns)
- No recent handoff exists (last 30 minutes)
- Stop hook not already active (prevents loops)

### Behavior

**Shows friendly reminder:**
```
💡 This session had 25 conversation turns.
ℹ  Consider creating a handoff to preserve context:
    /handoff "describe what you accomplished"
```

**Does NOT:**
- Block session from ending
- Run on trivial conversations (<10 turns)
- Show if handoff recently created
- Interfere with workflow

### Integration

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/stop-hook-handoff-reminder.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Configuration

Edit `.claude/scripts/stop-hook-handoff-reminder.sh`:

```bash
# Adjust these values:
readonly MIN_CONVERSATION_LENGTH=10  # Minimum turns to suggest handoff
```

---

## Hook 2: SessionEnd Hook (Auto-Archive)

### Purpose

Automatic cleanup when session ends:
- Archives handoffs older than 90 days
- Runs silently (only reports if action taken)
- Prevents indefinite accumulation

### Behavior

**On session end (clear/exit):**
```
🗂️  Auto-archived 2 old handoff(s) (>90 days)
```

**Does NOT:**
- Run on logout or crashes
- Delete handoffs (only archives)
- Archive recent handoffs
- Interfere with active work

### Integration

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/session-end-cleanup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Configuration

Edit `.claude/scripts/session-end-cleanup.sh`:

```bash
# Adjust auto-archive threshold:
readonly AUTO_ARCHIVE_DAYS=90  # Auto-archive handoffs older than this
```

---

## Complete settings.json Example

Combining both hooks with existing sbx-lite hooks:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/format-and-lint-shell.sh",
            "suppressOutput": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/stop-hook-handoff-reminder.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/session-end-cleanup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

---

## Recommendations

### Recommended: Stop Hook ✅

**Benefits:**
- Gentle reminder for complex sessions
- Prevents forgetting to document work
- Non-intrusive (only shows when relevant)
- Helps build handoff habit

**Use if:**
- You frequently work on complex multi-session features
- You want help remembering to create handoffs
- You like workflow automation assistance

### Optional: SessionEnd Hook ⚠️

**Benefits:**
- Automatic cleanup of very old handoffs
- Prevents indefinite accumulation
- Silent unless action taken

**Considerations:**
- 90 days is very conservative (you may want shorter)
- Manual cleanup with `manage-handoffs.sh` gives more control
- Could archive handoffs you wanted to keep

**Use if:**
- You accumulate many handoffs
- You prefer automatic over manual cleanup
- You're comfortable with auto-archiving at 90 days

### Alternative: Manual Cleanup Only

**Instead of hooks, use scripts directly:**

```bash
# Weekly cleanup routine
bash .claude/scripts/manage-handoffs.sh cleanup --interactive

# Or auto-cleanup older than 60 days
bash .claude/scripts/manage-handoffs.sh cleanup --auto --older-than 60
```

**Benefits:**
- Full control over what gets archived/deleted
- Review each handoff before action
- No surprises from automation

---

## Testing Hooks

### Test Stop Hook

```bash
# 1. Read input JSON
cat > /tmp/stop-hook-test.json <<'EOF'
{
  "session_id": "test123",
  "transcript_path": "/tmp/test-transcript.jsonl",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

# 2. Create fake transcript with many messages (to trigger reminder)
for i in {1..15}; do
  echo '{"role":"user","content":"test"}' >> /tmp/test-transcript.jsonl
  echo '{"role":"assistant","content":"test"}' >> /tmp/test-transcript.jsonl
done

# 3. Test hook
cat /tmp/stop-hook-test.json | bash .claude/scripts/stop-hook-handoff-reminder.sh

# Expected: Shows reminder message on stderr
```

### Test SessionEnd Hook

```bash
# 1. Create test handoff (very old)
mkdir -p .claude/handoffs
echo "# Test Handoff" > .claude/handoffs/2020-01-01-old-test.md

# 2. Make it 100 days old (macOS)
touch -t 202408010000 .claude/handoffs/2020-01-01-old-test.md

# 3. Test hook
cat > /tmp/session-end-test.json <<'EOF'
{
  "session_id": "test123",
  "transcript_path": "/tmp/test-transcript.jsonl",
  "permission_mode": "default",
  "hook_event_name": "SessionEnd",
  "reason": "clear"
}
EOF

cat /tmp/session-end-test.json | bash .claude/scripts/session-end-cleanup.sh

# Expected: Archives old handoff to archive/
ls -la .claude/handoffs/archive/
```

---

## Troubleshooting

### Stop Hook Not Showing Reminder

**Check:**
1. Session has >10 conversation turns
2. No recent handoff created (last 30 minutes)
3. Hook is configured in settings.json
4. Script is executable: `chmod +x .claude/scripts/stop-hook-handoff-reminder.sh`

**Debug:**
```bash
# Enable hook debugging
claude --debug

# Check hook execution in output
```

### SessionEnd Hook Not Archiving

**Check:**
1. Handoffs are actually older than threshold (default 90 days)
2. Hook is configured in settings.json
3. Session ending with `clear` or normal exit (not logout)
4. Archive directory has write permissions

**Debug:**
```bash
# Test manually
cat /tmp/session-end-test.json | bash .claude/scripts/session-end-cleanup.sh
```

### Hooks Running Multiple Times

**Cause:** Multiple identical hook commands in settings.json

**Fix:** Remove duplicates - Claude Code automatically deduplicates, but check your config:
```bash
# Check for duplicates
jq '.hooks' .claude/settings.json
```

---

## Disabling Hooks

### Temporary Disable (Current Session Only)

Hooks are loaded at session start. To disable:
1. Remove hook from settings.json
2. Start new session with `/clear` or restart Claude Code

### Permanent Disable

Remove hook configuration from `.claude/settings.json`:

```json
{
  "hooks": {
    // Remove "Stop": [...] section
    // Remove "SessionEnd": [...] section
  }
}
```

---

## Advanced: Customize Reminder Logic

### Example: Only remind for specific file types

Edit `.claude/scripts/stop-hook-handoff-reminder.sh`:

```bash
# Add after parsing input
local files_modified
files_modified=$(grep -o '"file_path":\s*"[^"]*"' "$transcript_path" | wc -l)

# Only remind if shell scripts were modified
if ! grep -q '\.sh"' "$transcript_path" 2>/dev/null; then
    exit 0
fi
```

### Example: Check git status before reminding

```bash
# Only remind if uncommitted changes exist
if ! git diff --quiet 2>/dev/null; then
    log_reminder "Uncommitted changes detected. Consider creating handoff."
fi
```

---

## Security Considerations

Both hooks are **read-only** and **safe**:

**Stop Hook:**
- ✅ Only reads transcript file
- ✅ Only checks handoffs directory
- ✅ No write operations
- ✅ No sensitive data access

**SessionEnd Hook:**
- ✅ Only moves files within project
- ✅ No deletion (only archiving)
- ✅ Runs in project directory
- ✅ No external network access

**Best Practices:**
- Review scripts before enabling
- Test with `claude --debug` first
- Adjust thresholds to your workflow
- Monitor initial behavior

---

## Summary

### Quick Decision Guide

**Enable Stop Hook if:**
- ✅ You want automated handoff reminders
- ✅ You work on complex multi-session features
- ✅ You like gentle workflow nudges

**Enable SessionEnd Hook if:**
- ✅ You accumulate many handoffs
- ✅ You prefer automatic cleanup
- ✅ 90-day threshold works for you

**Use Manual Cleanup if:**
- ✅ You prefer full control
- ✅ You want to review before archiving
- ✅ You already have cleanup routine

**Both hooks are optional** - Manual cleanup with `manage-handoffs.sh` works great too!

---

**See Also:**
- `.claude/docs/HANDOFF_LIFECYCLE_MANAGEMENT.md` - Complete lifecycle guide
- `.claude/WORKFLOWS.md` § "Session Continuity" - Handoff/pickup workflow
- `CONTRIBUTING.md` § "Session Continuity" - Quick reference

---

**Document Version:** 1.0
**Last Updated:** 2025-11-22
**Status:** Ready for integration
