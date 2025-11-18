# Development Workflows

Detailed workflows for TDD, Git operations, and testing practices.

## Common Workflows

### Adding a New Feature (TDD Workflow)

**Phase 1: Explore** (Research existing code)
1. Use Task tool with Explore agent to understand current implementation
2. Read relevant modules: `@lib/[module].sh`
3. Review best practices: `@docs/REALITY_BEST_PRACTICES.md`

**Phase 2: Plan** (Design before coding)
1. Use thinking mode: "think: Design [feature] considering [constraints]"
2. Document approach in comments or temporary planning file
3. Identify test cases and edge cases

**Phase 3: Test** (Write tests first)
1. Create test file: `tests/unit/test_[feature].sh`
2. Write failing tests based on requirements
3. Verify tests fail (RED phase)
4. **Commit tests:** `git commit -m "test: add tests for [feature]"`

**Phase 4: Code** (Implement feature)
1. Write minimal code to pass tests
2. Follow standards: `@.claude/CODING_STANDARDS.md`
3. Iterate: code → run tests → adjust → repeat
4. Verify all tests pass (GREEN phase)
5. **Commit implementation:** `git commit -m "feat: implement [feature]"`

**Phase 5: Refactor** (Improve quality)
1. Extract magic numbers to constants
2. Improve error messages using `lib/messages.sh`
3. Add documentation comments
4. Run tests after each refactoring
5. **Commit improvements:** `git commit -m "refactor: improve [aspect]"`

**Phase 6: Document** (Update docs)
1. Update relevant documentation files
2. Add usage examples if user-facing
3. **Commit docs:** `git commit -m "docs: document [feature]"`

## Development Workflow (Test-Driven)

### TDD Pattern (Recommended for All Features)

**IMPORTANT:** Always practice Test-Driven Development for new features and bug fixes.

**Step 1: Write Tests First**
```bash
# Tell Claude explicitly that you're practicing TDD
# This prevents Claude from creating mock implementations

# Example prompt:
# "We're practicing TDD. Write tests for [feature] based on these requirements:
# - Input: [description]
# - Expected output: [description]
# - Edge cases: [list]
# Do NOT implement the feature yet - only write failing tests."

# Create test file
tests/unit/test_new_feature.sh
```

**Step 2: Verify Tests Fail**
```bash
# Run tests - they MUST fail initially
bash tests/unit/test_new_feature.sh

# Expected output: Test failures (RED phase)
# If tests pass, they're incorrectly implemented!
```

**Step 3: Implement Feature**
```bash
# Now write minimal code to pass tests
# Iterate: code → run tests → adjust → repeat
lib/new_feature.sh
```

**Step 4: Verify Tests Pass**
```bash
# Run tests again - should all pass now (GREEN phase)
bash tests/unit/test_new_feature.sh

# If failures remain, continue iteration
```

**Step 5: Refactor (Optional)**
```bash
# Improve code quality while keeping tests passing
# REFACTOR phase - tests provide safety net
```

**Step 6: Commit Separately**
```bash
# Commit tests first
git add tests/unit/test_new_feature.sh
git commit -m "test: add tests for [feature]"

# Then commit implementation
git add lib/new_feature.sh
git commit -m "feat: implement [feature]"

# Ask Claude to generate commit messages based on git diff
```

### Independent Verification (Critical Features)

For security-critical or complex features:

1. **Initial Implementation**: Claude instance A writes tests and code
2. **Independent Review**: Ask a NEW Claude instance (use /clear) to:
   - Review tests for completeness
   - Verify implementation doesn't overfit to tests
   - Suggest additional edge cases

## Git Workflow Best Practices

### Commit Frequency

**Commit often during iteration:**
- ✅ After tests pass (GREEN phase)
- ✅ After successful refactoring
- ✅ After fixing each distinct issue
- ✅ Before attempting risky changes

**Separate commits for:**
1. Tests (first)
2. Implementation (second)
3. Documentation (third, if substantial)

### Commit Message Generation

**Let Claude write commit messages:**
```bash
# After staging changes
git add [files]

# Ask Claude:
"Examine git diff --staged and recent git log.
Write a conventional commit message following our project style."

# Claude will analyze:
# - What changed (git diff --staged)
# - Project conventions (git log --oneline -10)
# - Generate appropriate message
```

### Complex Git Operations

**Use Claude for:**
- Reverting files: "Revert lib/config.sh to previous commit"
- Resolving rebase conflicts: "Help resolve conflicts in [file]"
- Cherry-picking patches: "Apply the certificate validation logic from commit abc123"
- Searching history: "When was SNI validation added?"

### Pre-Commit Validation

**ALWAYS before committing:**
```bash
# 1. Tests pass
bash tests/test_reality.sh

# 2. Syntax valid
bash -n lib/modified_file.sh

# 3. ShellCheck passes
shellcheck lib/modified_file.sh

# 4. No debug code left
grep -n "echo.*DEBUG" lib/modified_file.sh
```

## Testing Requirements

### Test-First Development (Mandatory)

**For ALL new features:**
1. ✅ Write tests BEFORE implementation
2. ✅ Verify tests fail initially (RED)
3. ✅ Implement code to pass tests (GREEN)
4. ✅ Refactor while keeping tests passing
5. ✅ Commit tests separately from implementation

### Before Every Config Change

```bash
sing-box check -c /etc/sing-box/config.json
systemctl restart sing-box && sleep 3 && systemctl status sing-box
journalctl -u sing-box -f  # Watch 10-15 seconds
```

### Before Committing Code

```bash
# 1. All unit tests pass
bash tests/test_reality.sh

# 2. ShellCheck validation
make check

# 3. Integration tests pass
bash tests/integration/test_reality_connection.sh

# 4. Actual installation works
bash install_multi.sh
```

### Independent Verification (Critical Features)

For security-critical features (validation, encryption, authentication):

1. **Initial implementation** - Claude instance A
2. **Clear context:** `/clear`
3. **Independent review** - Fresh Claude instance
4. **Verification focus:**
   - Are tests comprehensive?
   - Are there edge cases missed?
   - Is implementation overfitting to tests?

## Working Effectively with Claude

### Thinking Modes for Complex Problems

Use thinking modes for planning complex features:

```bash
# Simple task - normal mode
"Add validation for port numbers"

# Medium complexity - use thinking
"think: Design a backup encryption system with key rotation"

# High complexity - deeper thinking
"think hard: Refactor config generation to support multi-protocol setups"

# Critical architecture decisions - maximum depth
"think harder: Design a plugin system for custom protocol handlers"
```

### Early Course Correction

**Interrupt immediately if Claude is going wrong direction:**
- Press **Escape key** to stop execution
- Provide correction: "Actually, we should use [approach] instead"
- This saves tokens and time vs. letting Claude finish wrong implementation

### Context Management

**Use /clear between unrelated tasks:**
```bash
# After completing feature A
/clear

# Start fresh context for feature B
"Implement feature B..."
```

**Benefits:**
- Maintains focus on current task
- Prevents confusion from previous context
- Improves performance and accuracy

### Subagent Usage (Task Tool)

**Use subagents early for:**
- Codebase exploration ("Where are errors from client handled?")
- Multi-file refactoring
- Complex searches requiring multiple iterations
- Tasks that might require 5+ tool calls

```bash
# Instead of running Grep/Glob directly for exploration:
# Use Task tool with subagent_type=Explore

# Example prompt:
"Use the Explore agent to find all certificate validation logic"
```

### Specificity Matters

**Good prompts (specific):**
```bash
"Add a validate_certificate() function to lib/validation.sh that:
- Checks file exists and is readable
- Verifies PEM format with openssl
- Warns if expiring within 30 days
- Returns 0 on success, 1 on failure
- Uses format_error() for error messages"
```

**Poor prompts (vague):**
```bash
"Add certificate validation"  # Too vague!
```
