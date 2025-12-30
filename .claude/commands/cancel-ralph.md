Cancel the active Ralph Wiggum iteration loop.

Check if there's an active Ralph loop and cancel it:

```bash
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  iteration=$(grep "^iteration:" .claude/ralph-loop.local.md | sed 's/iteration: //')
  rm .claude/ralph-loop.local.md
  echo "Cancelled Ralph loop (was at iteration $iteration)"
else
  echo "No active Ralph loop found."
fi
```

If the loop was cancelled, confirm to the user that the Ralph Wiggum loop has been stopped.
