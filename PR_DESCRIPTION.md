# Pull Request Description

**Title:** docs(claude): enhance CLAUDE.md with TDD workflow and best practices

---

## Summary

Enhances CLAUDE.md with comprehensive development workflow guidance based on [Anthropic's Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices).

This PR addresses workflow gaps by adding structured guidance for:
- Test-Driven Development (TDD) patterns
- Git commit best practices
- Effective Claude Code collaboration techniques

## New Sections Added

### 1. Development Workflow (Test-Driven)
- **TDD Pattern**: Step-by-step guide for RED-GREEN-REFACTOR cycle
- **Step 1**: Write tests first (with explicit TDD declaration to prevent mocks)
- **Step 2**: Verify tests fail (RED phase)
- **Step 3**: Implement feature iteratively
- **Step 4**: Verify tests pass (GREEN phase)
- **Step 5**: Refactor with test safety net
- **Step 6**: Commit separately (tests first, then implementation)
- **Independent Verification**: Use fresh Claude instance for critical features

### 2. Git Workflow Best Practices
- **Commit Frequency**: When to commit (after GREEN phase, after refactoring, before risky changes)
- **Separate Commits**: Tests → Implementation → Documentation
- **Commit Message Generation**: Let Claude analyze git diff and history
- **Complex Git Operations**: Reverting, rebasing, cherry-picking, history searching
- **Pre-Commit Validation**: Tests, syntax, ShellCheck, debug code removal

### 3. Working Effectively with Claude
- **Thinking Modes**: When to use "think", "think hard", "think harder"
- **Early Course Correction**: Press Escape to interrupt and redirect
- **Context Management**: Use /clear between unrelated tasks
- **Subagent Usage**: When to use Task tool with Explore agent
- **Specificity Matters**: Examples of good vs. poor prompts

## Updated Sections

### Common Workflows > Adding a New Feature
**Before** (5 steps):
1. Read docs
2. Write code
3. Test
4. Integrate
5. Document
6. Commit

**After** (6 phases - TDD workflow):
1. **Explore**: Research with Task/Explore agent
2. **Plan**: Use thinking modes for design
3. **Test**: Write failing tests first, commit
4. **Code**: Implement to pass tests, commit
5. **Refactor**: Improve quality with test safety net, commit
6. **Document**: Update docs, commit

### Testing Requirements
**Enhanced with:**
- **Test-First Mandate**: Write tests BEFORE all new features
- **RED-GREEN-REFACTOR**: Verify failure → success → improve
- **Independent Verification**: Critical features reviewed by fresh Claude instance
- **Verification Focus**: Test completeness, edge cases, overfitting check

## Key Improvements

### Development Quality
- ✅ **Earlier Bug Detection**: Tests written first catch issues before implementation
- ✅ **Refactoring Safety**: Tests provide confidence during code improvements
- ✅ **Reduced Debugging Time**: Issues caught in RED phase, not production

### Git Workflow
- ✅ **Clearer History**: Separate commits make debugging and reverting easier
- ✅ **Better Commit Messages**: Claude analyzes context for conventional commits
- ✅ **Complex Operations**: Guidance on rebasing, conflicts, history searching

### Claude Collaboration
- ✅ **Better Prompts**: Specificity guidance improves first-attempt success
- ✅ **Context Management**: /clear usage prevents confusion
- ✅ **Thinking Modes**: Match complexity to thinking depth
- ✅ **Early Correction**: Escape key saves tokens and time

## Testing Impact

**Test Coverage Increase:**
- TDD mandate ensures tests written for ALL new features
- Independent verification catches edge cases missed initially
- RED phase verification prevents mock/stub tests

**Example Workflow:**
```bash
# 1. Write tests (RED phase)
bash tests/unit/test_new_feature.sh  # MUST fail
git commit -m "test: add tests for feature X"

# 2. Implement (GREEN phase)
bash tests/unit/test_new_feature.sh  # MUST pass
git commit -m "feat: implement feature X"

# 3. Refactor (tests still GREEN)
bash tests/unit/test_new_feature.sh  # Still passing
git commit -m "refactor: improve feature X efficiency"
```

## Documentation Impact

**Total Changes:**
- **Lines added**: 280
- **Lines removed**: 12
- **Net addition**: 268 lines of actionable guidance

**Organization:**
- Sections logically grouped by development phase
- Code examples throughout for clarity
- Best practices highlighted with ✅/❌ indicators

## Backward Compatibility

✅ **Fully backward compatible** - No breaking changes
- Existing workflows still valid
- New guidance supplements (doesn't replace) current practices
- Optional adoption - teams can migrate incrementally

## Checklist

- [x] All new sections documented with examples
- [x] Code blocks use proper syntax highlighting
- [x] Best practices marked with ✅/❌
- [x] Links to external resources (Anthropic blog post)
- [x] Consistent formatting with existing CLAUDE.md style
- [x] No breaking changes to existing workflows

## References

- **Source**: [Anthropic's Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- **Related Issues**: Addresses workflow guidance gaps
- **Related PRs**: Complements existing CLAUDE.md structure

## Test Plan

**Validation:**
- [x] Markdown renders correctly
- [x] Code examples use valid bash syntax
- [x] All links resolve correctly
- [x] Examples align with project conventions
- [x] No typos or formatting issues

**Manual Review:**
- Read through all new sections for clarity
- Verify TDD workflow aligns with project testing approach
- Confirm git workflow matches conventional commit standards
- Validate Claude collaboration tips are accurate

---

**Impact Assessment**: 🟢 Low Risk
- Documentation-only changes
- No code modifications
- Backward compatible
- Improves development velocity and code quality
