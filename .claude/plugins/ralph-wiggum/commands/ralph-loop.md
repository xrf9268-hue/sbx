---
allowed-tools: Bash
---

Start a Ralph Wiggum loop.

Run the setup script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS
```

Now check the `.claude/ralph-loop.local.md` file to see the loop configuration:

```bash
cat .claude/ralph-loop.local.md
```

If there is a completion promise configured, display it and explain that this exact phrase (wrapped in `<promise></promise>` XML tags) must be output when the task is complete.

Begin working on the task described in the prompt.

CRITICAL INSTRUCTIONS:
- You MUST output the promise statement ONLY when it is completely and unequivocally TRUE
- DO NOT output the promise just to escape the loop
- DO NOT lie about whether the task is complete
- If you feel stuck, iterate and try different approaches rather than giving up
- The loop will continue until you genuinely complete the task and output the promise

Remember: Iteration leads to success. Keep working until the task is truly done.
