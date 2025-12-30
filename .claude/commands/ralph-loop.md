---
description: Start an iterative development loop that continues until task completion
arguments: '"prompt" --max-iterations N --completion-promise "TEXT"'
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

Start a Ralph Wiggum loop for iterative development.

First, run the setup script to initialize the loop:

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/setup-ralph-loop.sh" $ARGUMENTS
```

Now check the loop configuration:

```bash
cat .claude/ralph-loop.local.md
```

If there is a completion promise configured, you MUST output it wrapped in `<promise></promise>` XML tags when the task is truly complete.

Begin working on the task described in the prompt.

CRITICAL INSTRUCTIONS:
- You MUST output the promise statement ONLY when it is completely and unequivocally TRUE
- DO NOT output the promise just to escape the loop
- DO NOT lie about whether the task is complete
- If you feel stuck, iterate and try different approaches
- The loop will continue until you genuinely complete the task

Remember: Iteration leads to success. Keep working until the task is truly done.
