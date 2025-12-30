---
allowed-tools:
---

# Ralph Wiggum Plugin Help

## Overview

Ralph Wiggum implements continuous self-referential AI loops for iterative development. Instead of completing a task once, Claude repeatedly works on the same prompt, viewing its previous work and refining it until completion.

## Commands

### `/ralph-wiggum:ralph-loop`

Start a Ralph loop with:

```
/ralph-wiggum:ralph-loop "Your task prompt" --max-iterations 30 --completion-promise "DONE"
```

**Parameters:**
- `"prompt"` - The task to complete (required)
- `--max-iterations N` - Maximum iterations before stopping (recommended)
- `--completion-promise "TEXT"` - Phrase to output when task is complete

### `/ralph-wiggum:cancel-ralph`

Cancel an active loop:

```
/ralph-wiggum:cancel-ralph
```

## Example: Achieving 90%+ Test Coverage

```
/ralph-wiggum:ralph-loop "Add unit tests to achieve 90%+ code coverage.

Requirements:
1. Run: bash tests/coverage.sh generate
2. Identify functions with <100% coverage
3. Add tests for uncovered functions following project patterns
4. All tests must pass: bash tests/test-runner.sh unit

Success criteria:
- Coverage report shows >90% coverage
- All existing tests still pass
- No ShellCheck errors in test files

Output <promise>COVERAGE_90_ACHIEVED</promise> when coverage exceeds 90%." \
  --max-iterations 50 --completion-promise "COVERAGE_90_ACHIEVED"
```

## Best Practices

1. **Be specific** - Define exactly what "done" means
2. **Use verification** - Include test commands in your prompt
3. **Set limits** - Always use `--max-iterations`
4. **Incremental goals** - Break large tasks into phases
5. **TDD approach** - Let test results guide iteration

## When to Use Ralph

**Good for:**
- Test coverage improvement
- Code refactoring with test verification
- Documentation generation
- Repetitive tasks with clear completion criteria

**Avoid for:**
- Tasks requiring human judgment
- Ambiguous success criteria
- Debugging complex issues
