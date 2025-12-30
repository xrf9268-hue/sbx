# Ralph Wiggum 迭代开发指南

**Version:** 1.1.0
**Date:** 2025-12-30
**Purpose:** Autonomous iterative development loops for Claude Code

## Overview

Ralph Wiggum 实现了持续的自引用 AI 循环。Claude 不是一次性完成任务，而是反复处理相同的提示词，查看之前的工作并不断改进，直到完成。

适用场景：
- 达到高测试覆盖率 (90%+)
- 迭代式代码重构
- 文档生成
- 任何有可衡量完成标准的任务

## 安装方式

### 本项目已配置（原生命令）

由于 `/plugin` 命令在 Claude Code on Web 不可用，本项目使用**原生斜杠命令**实现 ralph-wiggum 功能：

```
.claude/
├── commands/
│   ├── ralph-loop.md      # /ralph-loop 命令
│   └── cancel-ralph.md    # /cancel-ralph 命令
├── scripts/
│   ├── setup-ralph-loop.sh
│   ├── ralph-stop-hook.sh
│   └── stop-hook-combined.sh
└── settings.json          # Stop hook 配置
```

## 命令

### `/ralph-loop`

启动迭代开发循环。

**语法:**
```bash
/ralph-loop "PROMPT" --max-iterations N --completion-promise "TEXT"
```

**参数:**
| 参数 | 必需 | 说明 |
|------|------|------|
| `"PROMPT"` | 是 | 要完成的任务 |
| `--max-iterations N` | 推荐 | 最大迭代次数限制 |
| `--completion-promise "TEXT"` | 推荐 | 完成时输出的短语 |

### `/cancel-ralph`

取消活动循环。

```bash
/cancel-ralph
```

## 实用示例

### 示例 1: 达到 90%+ 测试覆盖率

```bash
/ralph-loop "Improve test coverage to 90%+ for this project.

WORKFLOW:
1. Run coverage analysis: bash tests/coverage.sh generate
2. Review coverage report to identify uncovered functions
3. Add unit tests for functions with <90% coverage
4. Follow existing test patterns in tests/unit/
5. Run tests to verify: bash tests/test-runner.sh unit

SUCCESS CRITERIA:
- Coverage report shows >90% overall coverage
- All new tests pass
- All existing tests still pass
- No ShellCheck errors in test files

When coverage exceeds 90%, output: <promise>COVERAGE_90_ACHIEVED</promise>" \
  --max-iterations 50 --completion-promise "COVERAGE_90_ACHIEVED"
```

### 示例 2: 修复所有 ShellCheck 警告

```bash
/ralph-loop "Fix all ShellCheck warnings in lib/ directory.

WORKFLOW:
1. Run: shellcheck lib/*.sh 2>&1 | head -100
2. Fix each warning following bash best practices
3. Re-run shellcheck to verify fixes
4. Repeat until no warnings remain

SUCCESS CRITERIA:
- shellcheck lib/*.sh returns no warnings
- All tests still pass
- No functionality broken

When all warnings fixed: <promise>SHELLCHECK_CLEAN</promise>" \
  --max-iterations 30 --completion-promise "SHELLCHECK_CLEAN"
```

### 示例 3: 完善文档

```bash
/ralph-loop "Add comprehensive documentation to all public functions in lib/.

WORKFLOW:
1. List all functions: grep -rn '^[a-z_]*()' lib/*.sh
2. Check each function for documentation comments
3. Add missing documentation following project style
4. Include: purpose, parameters, return values, examples

SUCCESS CRITERIA:
- Every public function has documentation comment
- Documentation follows project conventions
- Examples are accurate and tested

When complete: <promise>DOCS_COMPLETE</promise>" \
  --max-iterations 40 --completion-promise "DOCS_COMPLETE"
```

### 示例 4: TDD 开发循环

```bash
/ralph-loop "Implement feature X using TDD.

PHASE 1 - Write failing tests:
1. Create tests/unit/test_feature_x.sh
2. Write test cases for all requirements
3. Verify tests fail (RED phase)

PHASE 2 - Implement:
1. Write minimal code to pass tests
2. Run: bash tests/test-runner.sh unit
3. Iterate until all tests pass (GREEN phase)

PHASE 3 - Refactor:
1. Clean up implementation
2. Ensure tests still pass

SUCCESS CRITERIA:
- All tests pass
- Code follows project conventions
- No ShellCheck errors

When complete: <promise>TDD_COMPLETE</promise>" \
  --max-iterations 30 --completion-promise "TDD_COMPLETE"
```

## How It Works

### The Loop Mechanism

1. You start a loop with `/ralph-wiggum:ralph-loop`
2. The setup script creates `.claude/ralph-loop.local.md` with:
   - Active status
   - Iteration counter
   - Max iterations
   - Completion promise
   - Original prompt

3. Claude works on the task
4. When Claude tries to exit, the **Stop hook** intercepts:
   - Checks if loop is active
   - Checks for completion promise in output
   - If not complete, feeds the same prompt back
   - Increments iteration counter

5. Loop continues until:
   - Completion promise detected: `<promise>TEXT</promise>`
   - Max iterations reached
   - Manual cancellation: `/ralph-wiggum:cancel-ralph`

### State File Format

`.claude/ralph-loop.local.md`:
```yaml
---
active: true
iteration: 5
max_iterations: 50
completion_promise: COVERAGE_90_ACHIEVED
started: 2025-12-30T10:00:00+00:00
---

Your original prompt here...
```

## Best Practices

### 1. Be Specific About Success

**Good:**
```
Coverage report shows >90% for all modules in lib/
```

**Bad:**
```
Improve test coverage
```

### 2. Include Verification Commands

**Good:**
```
Run: bash tests/coverage.sh generate
Check: coverage > 90% in output
```

**Bad:**
```
Make sure tests are good
```

### 3. Always Set Iteration Limits

**Good:**
```
--max-iterations 50
```

**Risky:**
```
(no limit - loop runs forever until promise)
```

### 4. Break Large Tasks into Phases

**Good:**
```
PHASE 1: Write tests
PHASE 2: Implement
PHASE 3: Refactor
```

**Bad:**
```
Do everything at once
```

### 5. Use Measurable Criteria

**Good:**
```
- Coverage > 90%
- All 145 tests pass
- Zero ShellCheck errors
```

**Bad:**
```
- Code is better
- Tests are good enough
```

## Troubleshooting

### Loop Not Starting

Check if state file exists:
```bash
cat .claude/ralph-loop.local.md
```

Re-run setup:
```bash
/ralph-wiggum:ralph-loop "Your prompt" --max-iterations 30
```

### Loop Not Stopping

1. Manual cancel:
   ```bash
   /ralph-wiggum:cancel-ralph
   ```

2. Direct cleanup:
   ```bash
   rm .claude/ralph-loop.local.md
   ```

### Promise Not Detected

Ensure exact format:
```
<promise>EXACT_PROMISE_TEXT</promise>
```

Not:
```
Promise: EXACT_PROMISE_TEXT
<PROMISE>EXACT_PROMISE_TEXT</PROMISE>
```

### Iteration Count Wrong

Check state file:
```bash
grep "iteration:" .claude/ralph-loop.local.md
```

## Integration with sbx-lite

### Recommended Test Coverage Loop

For this project specifically:

```bash
/ralph-wiggum:ralph-loop "Achieve 90%+ test coverage for sbx-lite.

PROJECT CONTEXT:
- Test framework: tests/test_framework.sh
- Coverage tool: tests/coverage.sh
- Unit tests: tests/unit/
- Integration tests: tests/integration/

WORKFLOW:
1. Analyze current coverage:
   bash tests/coverage.sh generate

2. Identify gaps:
   - Functions with 0% coverage
   - Functions with <90% coverage
   - Edge cases not tested

3. Add tests following patterns in:
   - tests/unit/test_validation_enhanced.sh (41 tests)
   - tests/unit/test_tools.sh (18 tests)

4. Verify:
   bash tests/test-runner.sh unit

SUCCESS CRITERIA:
- Overall coverage >90%
- All 100+ tests pass
- Tests cover edge cases
- No ShellCheck errors

Output <promise>SBX_COVERAGE_90</promise> when complete." \
  --max-iterations 100 --completion-promise "SBX_COVERAGE_90"
```

## References

- [Official Ralph Wiggum Plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [Claude Code Plugin Docs](https://code.claude.com/docs/en/plugins.md)
- [Autonomous Loops Blog Post](https://paddo.dev/blog/ralph-wiggum-autonomous-loops/)

---

**Author:** Claude Code
**License:** MIT
