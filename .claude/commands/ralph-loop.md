Start a Ralph Wiggum loop for iterative development.

The user specified task:

<task>$ARGUMENTS</task>

If no task was provided in the `<task>...</task>` tag, STOP and ask the user what task they want to iterate on.

## Setup

First, parse the arguments. The format is:
- First argument: The task prompt (quoted string)
- `--max-iterations N`: Maximum iterations (default: 30)
- `--completion-promise "TEXT"`: Phrase to output when done

Create the loop state file at `.claude/ralph-loop.local.md`:

```yaml
---
active: true
iteration: 1
max_iterations: [N or 30]
completion_promise: [TEXT or empty]
started: [current timestamp]
---

[The task prompt]
```

## Instructions

Begin working on the task. You must:

1. Work on the task iteratively
2. Check your progress after each step
3. When the task is TRULY complete, output: `<promise>[COMPLETION_PROMISE]</promise>`

CRITICAL RULES:
- ONLY output the promise when the task is genuinely complete
- DO NOT output the promise just to escape the loop
- If stuck, try different approaches
- The loop continues until you complete the task

## Completion

When you're done, output the completion promise wrapped in XML tags:

```
<promise>COMPLETION_PROMISE_HERE</promise>
```

The Stop hook will detect this and end the loop.
