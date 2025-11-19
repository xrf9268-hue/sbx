# Shell Linting Analysis - Current Integration Status

**Date:** 2025-11-19
**Scope:** Analyze existing ShellCheck integration and evaluate need for PostToolUse lint hook

---

## Current ShellCheck Integration

### 1. Pre-Commit Hook (Local)
**File:** `hooks/pre-commit` (lines 133-165)

**Configuration:**
```bash
shellcheck -S warning -e SC2250 "$file"
```

**Behavior:**
- ✅ Runs on every `git commit`
- ⚠️ **NON-BLOCKING** - Shows warnings but allows commit
- Severity: `-S warning` (moderate)
- Excludes: `SC2250` (style preferences)
- Checks: `install_multi.sh`, `lib/*.sh`, `bin/sbx-manager.sh`

**Output:**
```
[4/5] Running ShellCheck linting...

If ShellCheck installed:
  ⚠ WARNING: ShellCheck found X files with warnings
  (Not blocking commit, but please review)

If ShellCheck NOT installed:
  ⚠ SKIP: ShellCheck not installed
  Install with: apt install shellcheck (or brew install shellcheck)
```

**Key Point:** Pre-commit hook is **non-blocking** for ShellCheck warnings.

---

### 2. CI/CD (GitHub Actions)
**File:** `.github/workflows/shellcheck.yml` (lines 27-91)

**Configuration:**
```bash
shellcheck -e SC1090 -e SC1091 -S error "$script"
```

**Behavior:**
- ✅ Runs on every push/PR
- 🔴 **BLOCKING** - Build fails on errors
- Severity: `-S error` (strict - only errors, not warnings)
- Excludes: `SC1090`, `SC1091` (source file warnings)
- Checks: `install_multi.sh`, `lib/*.sh`, `bin/*.sh`

**Jobs:**
1. **shellcheck** - Static analysis (BLOCKING)
2. **syntax-check** - Bash syntax validation (BLOCKING)
3. **code-style** - Strict mode, shebang checks (BLOCKING)
4. **security-scan** - Security patterns (BLOCKING/WARNING)
5. **unit-tests** - Unit test execution (BLOCKING)

**Key Point:** CI/CD is **strictly enforced** - errors block merge.

---

### 3. SessionStart Hook
**File:** `.claude/scripts/session-start.sh`

**No ShellCheck Integration:**
- Does NOT install ShellCheck
- Does NOT run ShellCheck validation
- Focuses on: git hooks, jq, openssl, bootstrap validation

---

## Current Coverage Summary

| Stage | When | ShellCheck | Severity | Blocking | Coverage |
|-------|------|------------|----------|----------|----------|
| **PostToolUse** | After Edit/Write | ❌ NO | N/A | N/A | N/A |
| **Pre-commit** | Before commit | ⚠️ Optional | Warning | ❌ NO | All .sh files |
| **CI/CD** | Push/PR | ✅ YES | Error | ✅ YES | All .sh files |

---

## Gap Analysis

### What's Missing?

**Real-time feedback during development:**
- ❌ No linting after Edit/Write operations
- ❌ No immediate feedback on code quality
- ❌ Issues only discovered at commit time (if ShellCheck installed)
- ❌ Or only discovered in CI/CD (after push)

**Current Developer Experience:**
```
1. Edit lib/network.sh
   └─→ PostToolUse: Formats with shfmt ✓
   └─→ PostToolUse: NO linting ✗

2. Continue working...
   (No feedback on ShellCheck issues)

3. git commit
   └─→ Pre-commit: ShellCheck warnings (non-blocking)
   (Developer may ignore warnings)

4. git push
   └─→ CI/CD: ShellCheck errors (BLOCKING)
   (Build fails - developer must fix and re-push)
```

**Pain Point:** Developers discover lint errors **too late** (after push).

---

## Should We Add PostToolUse Lint Hook?

### Option 1: Add PostToolUse ShellCheck Hook ✅ RECOMMENDED

**Pros:**
- ✅ **Immediate feedback** - Catch issues right after editing
- ✅ **Faster iteration** - Fix problems before commit
- ✅ **Reduced CI/CD failures** - Catch errors locally
- ✅ **Complements formatting** - Format + lint together
- ✅ **Developer-friendly** - See issues while context is fresh
- ✅ **Non-blocking** - Can be warning-only (like pre-commit)

**Cons:**
- ⚠️ Requires ShellCheck installed (can be non-blocking)
- ⚠️ Adds ~100-500ms latency after edits
- ⚠️ May be noisy if code has many warnings
- ⚠️ Duplicates pre-commit/CI checks (but earlier feedback is good)

**Configuration Example:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/format-shell.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/lint-shell.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

---

### Option 2: Keep Current Setup ⚠️ NOT RECOMMENDED

**Pros:**
- ✅ No additional complexity
- ✅ No performance overhead
- ✅ ShellCheck already in pre-commit + CI/CD

**Cons:**
- ❌ Late feedback (commit or push time)
- ❌ More CI/CD failures
- ❌ Slower development iteration
- ❌ Developer frustration (fix-push-fail-repeat cycle)

---

## Recommended Implementation

### PostToolUse Lint Hook Design

**File:** `.claude/scripts/lint-shell.sh`

**Features:**
- ✅ Runs ShellCheck on edited shell scripts
- ✅ **Non-blocking warnings** (exit code 1, not 2)
- ✅ Shows clear error messages with line numbers
- ✅ Provides install instructions if ShellCheck missing
- ✅ Uses same excludes as pre-commit (`-e SC2250`)
- ✅ Warning severity (matches pre-commit, not CI/CD)
- ✅ Minimal transcript noise (suppressOutput for clean files)

**Configuration:**
```bash
# Same as pre-commit (non-blocking warnings)
shellcheck -S warning -e SC2250 "$file_path"
```

**Behavior:**

**Case 1: ShellCheck finds issues**
```
⚠ ShellCheck found 3 issues in network.sh:
  Line 45: Use "$var" instead of $var
  Line 67: Quote this to prevent word splitting
  Line 89: Declare and assign separately to avoid masking return values
```
- Exit code: 1 (non-blocking warning)
- Developer sees issues immediately
- Can continue working or fix issues

**Case 2: ShellCheck not installed**
```
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  ShellCheck Not Installed                                │
├─────────────────────────────────────────────────────────────┤
│ Install ShellCheck for automatic linting:                   │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shellcheck               │
│   macOS:          brew install shellcheck                   │
│   Snap:           sudo snap install shellcheck              │
│                                                              │
│ Your code will be validated in pre-commit and CI/CD.        │
└─────────────────────────────────────────────────────────────┘
```
- Exit code: 1 (non-blocking)
- Developer informed but not blocked
- Pre-commit and CI/CD will still validate

**Case 3: File is clean**
```
✓ ShellCheck passed: network.sh
```
- Exit code: 0
- JSON output with `suppressOutput: true`
- No clutter in transcript

---

## Comparison Matrix

| Approach | Feedback Time | Blocking | Coverage | Developer UX |
|----------|---------------|----------|----------|--------------|
| **PostToolUse (Proposed)** | Immediate | No | All edits | ✅ Excellent |
| **Pre-commit (Current)** | At commit | No | All commits | ⚠️ Good |
| **CI/CD (Current)** | After push | Yes | All pushes | ❌ Poor (late) |

**Best Practice:** Use all three together!
- **PostToolUse:** Immediate feedback (catch early)
- **Pre-commit:** Safety net at commit time
- **CI/CD:** Final enforcement (no escape)

---

## Performance Considerations

### ShellCheck Performance

| File Size | Lines | Typical Duration |
|-----------|-------|------------------|
| lib/common.sh | 253 | ~100-200ms |
| lib/network.sh | 300+ | ~150-300ms |
| install_multi.sh | 600+ | ~300-500ms |

**Impact:** ~100-500ms latency after edits (acceptable for quality)

**Optimization:**
- Only lint files that changed (already done by matcher)
- Run ShellCheck with minimal severity (faster than full analysis)
- Use `suppressOutput` to reduce transcript overhead

---

## Integration with Existing Automation

### Automation Stack (Proposed)

```
┌──────────────────────────────────────────────────────────┐
│  TIER 1: Real-Time (PostToolUse Hooks)                   │
├──────────────────────────────────────────────────────────┤
│  After Edit/Write:                                        │
│    1. Format with shfmt           (~100-500ms)           │
│    2. Lint with ShellCheck        (~100-500ms)           │
│                                                           │
│  Total latency: ~200ms-1s (acceptable)                   │
│  Result: Clean, formatted, linted code ready to commit   │
└──────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  TIER 2: Pre-Commit Validation (Git Hook)                │
├──────────────────────────────────────────────────────────┤
│  Before commit:                                           │
│    1. Bash syntax check           (BLOCKING)             │
│    2. Bootstrap constants          (BLOCKING)             │
│    3. Strict mode check            (BLOCKING)             │
│    4. ShellCheck warnings          (NON-BLOCKING)         │
│    5. Unbound variable check       (BLOCKING)             │
│                                                           │
│  Result: Valid code committed to local branch            │
└──────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  TIER 3: CI/CD Enforcement (GitHub Actions)              │
├──────────────────────────────────────────────────────────┤
│  After push:                                              │
│    1. ShellCheck errors            (BLOCKING)             │
│    2. Syntax validation            (BLOCKING)             │
│    3. Code style checks            (BLOCKING)             │
│    4. Security scan                (BLOCKING/WARNING)     │
│    5. Unit tests                   (BLOCKING)             │
│                                                           │
│  Result: Only quality code merged to main                │
└──────────────────────────────────────────────────────────┘
```

---

## Recommendation

### ✅ YES - Add PostToolUse ShellCheck Hook

**Why:**
1. **Better Developer Experience**
   - Immediate feedback on code quality
   - Fix issues while context is fresh
   - Reduced frustration from late failures

2. **Reduced CI/CD Failures**
   - Catch ShellCheck errors locally
   - Fewer failed builds
   - Faster development iteration

3. **Complements Existing Automation**
   - Works alongside formatting hook
   - Doesn't replace pre-commit or CI/CD
   - Adds early warning system

4. **Non-Disruptive**
   - Non-blocking warnings (like pre-commit)
   - Graceful degradation if ShellCheck missing
   - Minimal performance impact (~200ms-1s)

5. **Aligns with Project Philosophy**
   - Automation at every stage
   - Early error detection
   - Developer-friendly tooling

**When NOT to use:**
- If ShellCheck is too noisy (many warnings in legacy code)
- If performance is critical (<1s latency unacceptable)
- If developers prefer manual linting

---

## Implementation Plan

### Phase 1: Create Lint Hook Script
**File:** `.claude/scripts/lint-shell.sh`

**Features:**
- ShellCheck integration with warning severity
- Non-blocking warnings (exit code 1)
- Install instructions if missing
- Same excludes as pre-commit
- JSON output for clean files

### Phase 2: Register Hook in Settings
**File:** `.claude/settings.json`

Add to PostToolUse hooks array (after format-shell.sh):
```json
{
  "type": "command",
  "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/lint-shell.sh",
  "timeout": 10
}
```

### Phase 3: Update Documentation
- Update `.claude/README.md` with lint hook info
- Update `.claude/HOOKS_GUIDE.md` with linting section
- Add ShellCheck to installation requirements

### Phase 4: Test and Iterate
1. Test with clean file (should pass silently)
2. Test with file containing warnings (should show issues)
3. Test without ShellCheck (should show install instructions)
4. Verify performance is acceptable (~200ms-1s)

---

## Conclusion

**Recommendation: IMPLEMENT PostToolUse ShellCheck hook**

**Benefits outweigh costs:**
- ✅ Immediate feedback > Late feedback
- ✅ Fewer CI/CD failures > More CI/CD failures
- ✅ Better UX > Delayed error discovery
- ✅ ~200ms-1s latency > Acceptable trade-off for quality

**Next Steps:**
1. Review this analysis
2. Approve implementation
3. Create `.claude/scripts/lint-shell.sh`
4. Register hook in `.claude/settings.json`
5. Test and document

---

**Questions or Concerns?**
- Is ~200ms-1s latency acceptable?
- Should it be blocking (exit 2) or non-blocking (exit 1)?
- Should it match pre-commit (warning) or CI/CD (error) severity?
- Any specific ShellCheck rules to exclude?
