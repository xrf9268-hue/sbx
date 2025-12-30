# Ralph Wiggum Plugin (Local Installation)

This is a local copy of the [Ralph Wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) from Anthropic's official Claude Code repository.

## Quick Start

### Using Plugin Commands

```bash
# Start an iterative loop
/ralph-wiggum:ralph-loop "Your task" --max-iterations 30 --completion-promise "DONE"

# Cancel active loop
/ralph-wiggum:cancel-ralph

# Get help
/ralph-wiggum:help
```

### Example: 90%+ Test Coverage

```bash
/ralph-wiggum:ralph-loop "Achieve 90%+ test coverage.
1. Run: bash tests/coverage.sh generate
2. Add tests for uncovered functions
3. Verify: bash tests/test-runner.sh unit
Output <promise>COVERAGE_90</promise> when done." \
  --max-iterations 50 --completion-promise "COVERAGE_90"
```

## Documentation

See [.claude/docs/RALPH_WIGGUM_PLUGIN_GUIDE.md](../docs/RALPH_WIGGUM_PLUGIN_GUIDE.md) for full documentation.

## Installation via Marketplace

For the official version (receives updates):

```bash
/plugin marketplace add anthropics/claude-code
/plugin install ralph-wiggum
```

## License

MIT - See [Anthropic Claude Code](https://github.com/anthropics/claude-code)
