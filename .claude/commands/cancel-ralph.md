---
description: Cancel an active Ralph Wiggum iteration loop
allowed-tools: Bash
---

Cancel active Ralph Wiggum loop.

```bash
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  iteration=$(grep "^iteration:" .claude/ralph-loop.local.md | sed 's/iteration: //')
  rm .claude/ralph-loop.local.md
  echo "Cancelled Ralph loop (was at iteration $iteration)"
else
  echo "No active Ralph loop found."
fi
```
