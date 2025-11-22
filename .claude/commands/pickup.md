Resumes work from a previous handoff session which are stored in `.claude/handoffs`.

The handoff folder might not exist if there are none.

Requested handoff file: `$ARGUMENTS`

## Process

### 1. Check handoff file

If no handoff file was provided, list them all.  Eg:

```bash
echo "## Available Handoffs"
echo ""
if [ -d ".claude/handoffs" ]; then
  for file in .claude/handoffs/*.md; do
    if [ -f "$file" ]; then
      title=$(grep -m 1 "^# " "$file" | sed 's/^# //')
      basename=$(basename "$file")
      echo "* \`$basename\`: $title"
    fi
  done
else
  echo "No handoffs directory found. Use \`/handoff \"purpose\"\` to create your first handoff."
fi
echo ""
echo "To pickup a handoff, use: /pickup <filename>"
```

### 2. Load handoff file

If a handoff file was provided locate it in `.claude/handoffs` and read it.  Note that this file might be misspelled or the user might have only partially listed it.  If there are multiple matches, ask the user which one they want to continue with.  The file contains the instructions for how you should continue.

### 3. Resume work

After reading the handoff file:

1. **Acknowledge the handoff context**: Briefly summarize what you understand from the handoff
2. **Confirm current status**: State what was the last completed step and what's pending
3. **Ready to proceed**: Ask the user if they want you to continue with the next step from the handoff, or if there's a different direction

**sbx-lite specific considerations when resuming:**
- Verify current git branch matches development context
- Check if tests are still passing before continuing work
- Review any ShellCheck or strict mode compliance notes
- Confirm Reality protocol configurations haven't changed (if applicable)
- Validate backward compatibility requirements are still met

**Example acknowledgment:**

```
I've loaded the handoff: [Readable Summary]

Context summary:
- Working on: [brief description]
- Last completed: [last step]
- Next step: [planned next step]
- Tests status: [from handoff]
- Key files: [list]

Ready to continue with [next step], or would you like to adjust the plan?
```
