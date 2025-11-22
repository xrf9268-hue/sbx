# Handoff Lifecycle Management

**Date:** 2025-11-22
**Purpose:** Best practices and automation for managing handoff files throughout their lifecycle

---

## Table of Contents

1. [Handoff Lifecycle Stages](#handoff-lifecycle-stages)
2. [Cleanup Strategies](#cleanup-strategies)
3. [Automation Tools](#automation-tools)
4. [Git Integration](#git-integration)
5. [Best Practices](#best-practices)

---

## Handoff Lifecycle Stages

### Stage 1: Active (In Progress)

**State:** Work currently in progress, frequently accessed

**Location:** `.claude/handoffs/YYYY-MM-DD-slug.md`

**Actions:**
- ✅ Keep in main handoffs directory
- ✅ Update as work progresses
- ✅ May contain sensitive data (local only)
- ❌ Do NOT commit to git yet

**Example:**
```
.claude/handoffs/2025-11-22-reality-validation.md  [ACTIVE]
```

### Stage 2: Completed (PR Open)

**State:** Work finished, pull request open, awaiting review/merge

**Location:** `.claude/handoffs/YYYY-MM-DD-slug.md`

**Actions:**
- ✅ Sanitize sensitive data
- ✅ Optionally commit for collaboration
- ✅ Reference in PR description
- ⚠️ Still needed for PR discussions

**Example:**
```bash
# Sanitize before committing
bash .claude/scripts/sanitize-handoff.sh 2025-11-22-reality-validation.md

# Commit for collaboration
git add .claude/handoffs/2025-11-22-reality-validation.md
git commit -m "docs: add handoff for Reality validation (PR #42)"
```

### Stage 3: Merged (PR Merged)

**State:** PR merged, work completed and deployed

**Decision Point:** Archive or delete?

**Options:**

**A. Archive (Recommended for complex features)**
```bash
# Move to archive directory
bash .claude/scripts/manage-handoffs.sh archive 2025-11-22-reality-validation.md

# Result: .claude/handoffs/archive/2025-11-22-reality-validation.md
```

**B. Delete (For simple features)**
```bash
# Permanent deletion
bash .claude/scripts/manage-handoffs.sh delete 2025-11-22-reality-validation.md
```

**C. Extract & Delete (Best practice)**
```bash
# Extract architectural decisions to docs
bash .claude/scripts/manage-handoffs.sh extract 2025-11-22-reality-validation.md

# Adds key decisions to .claude/ARCHITECTURE_DECISIONS.md
# Then deletes handoff
```

---

## Cleanup Strategies

### Strategy 1: Manual Cleanup (Simple Projects)

**When to use:** Small team, infrequent handoffs

**Process:**
```bash
# 1. List all handoffs
ls -lh .claude/handoffs/*.md

# 2. Identify completed work
# (Check PR status, git history)

# 3. Delete or archive manually
rm .claude/handoffs/2025-11-22-old-feature.md
```

**Pros:** Full control, no automation needed
**Cons:** Easy to forget, manual effort

### Strategy 2: Periodic Cleanup (Recommended)

**When to use:** Active development, multiple contributors

**Schedule:** Weekly or after each PR merge

**Process:**
```bash
# List handoffs older than 30 days
bash .claude/scripts/manage-handoffs.sh list --older-than 30

# Review and archive/delete
bash .claude/scripts/manage-handoffs.sh cleanup --interactive
```

**Pros:** Prevents accumulation, keeps directory clean
**Cons:** Requires discipline

### Strategy 3: Automated Cleanup (Large Teams)

**When to use:** High-velocity teams, many PRs

**Automation:**
- Git hooks (post-merge)
- CI/CD integration
- Scheduled cleanup script

**Process:**
```bash
# In .git/hooks/post-merge (auto-archives on PR merge)
#!/usr/bin/env bash
bash .claude/scripts/manage-handoffs.sh auto-archive
```

**Pros:** Zero manual effort, consistent
**Cons:** Requires setup, may archive too aggressively

### Strategy 4: Hybrid (Best for sbx-lite)

**Combination approach:**

1. **Active handoffs:** Keep locally (gitignored)
2. **Collaborative handoffs:** Sanitize and commit
3. **Merged handoffs:** Extract decisions, then archive
4. **Old handoffs (>60 days):** Auto-delete

**Implementation:**
```bash
# .gitignore
.claude/handoffs/*.md              # Ignore by default
!.claude/handoffs/README.md        # Keep README
!.claude/handoffs/archive/         # Track archives

# Weekly cleanup (cron or manual)
bash .claude/scripts/manage-handoffs.sh cleanup --hybrid
```

---

## Automation Tools

### Tool 1: Handoff Manager Script

**Location:** `.claude/scripts/manage-handoffs.sh`

**Features:**
- List handoffs by age, status, or pattern
- Archive completed handoffs
- Delete old handoffs
- Sanitize sensitive data
- Extract architectural decisions
- Interactive cleanup wizard

**Usage:**
```bash
# List all handoffs
bash .claude/scripts/manage-handoffs.sh list

# List handoffs older than 30 days
bash .claude/scripts/manage-handoffs.sh list --older-than 30

# Archive specific handoff
bash .claude/scripts/manage-handoffs.sh archive 2025-11-22-feature.md

# Delete specific handoff
bash .claude/scripts/manage-handoffs.sh delete 2025-11-22-feature.md

# Interactive cleanup wizard
bash .claude/scripts/manage-handoffs.sh cleanup --interactive

# Extract architectural decisions
bash .claude/scripts/manage-handoffs.sh extract 2025-11-22-feature.md

# Auto-archive merged PRs
bash .claude/scripts/manage-handoffs.sh auto-archive
```

### Tool 2: Sanitization Script

**Location:** `.claude/scripts/sanitize-handoff.sh`

**Purpose:** Remove sensitive data before committing

**Sanitizes:**
- UUIDs → `UUID_PLACEHOLDER`
- Server IPs → `SERVER_IP`
- Private keys → `PRIVATE_KEY_REDACTED`
- Passwords → `PASSWORD_REDACTED`
- Tokens → `TOKEN_REDACTED`

**Usage:**
```bash
# Sanitize specific file (creates .sanitized version)
bash .claude/scripts/sanitize-handoff.sh 2025-11-22-feature.md

# Sanitize in-place
bash .claude/scripts/sanitize-handoff.sh 2025-11-22-feature.md --in-place

# Sanitize all handoffs
bash .claude/scripts/sanitize-handoff.sh --all
```

**Example transformation:**
```markdown
# Before sanitization
- UUID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
- Server: 192.168.1.100
- Private Key: UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc

# After sanitization
- UUID: UUID_PLACEHOLDER
- Server: SERVER_IP
- Private Key: PRIVATE_KEY_REDACTED
```

### Tool 3: Decision Extractor

**Location:** `.claude/scripts/extract-decisions.sh`

**Purpose:** Extract architectural decisions from handoffs to permanent docs

**Extracts:**
- Problem solving sections
- Key technical concepts
- Architectural decisions
- Trade-offs and rationale

**Usage:**
```bash
# Extract from specific handoff
bash .claude/scripts/extract-decisions.sh 2025-11-22-module-split.md

# Appends to .claude/ARCHITECTURE_DECISIONS.md
```

**Example extraction:**
```markdown
# Before (in handoff):
## 4. Problem Solving
We split common.sh into logging.sh and generators.sh because:
- common.sh was 612 lines (too large)
- Violated Single Responsibility Principle
- Made testing difficult

Trade-off: More files to manage, but better separation of concerns.

# After (in ARCHITECTURE_DECISIONS.md):
## 2025-11-22: Module Split (common.sh)

**Decision:** Split common.sh (612 lines) into logging.sh and generators.sh

**Rationale:**
- Violated Single Responsibility Principle
- Testing was difficult with monolithic module

**Trade-offs:**
- More files to manage (-) vs Better separation of concerns (+)
- Net benefit: Improved maintainability

**Reference:** Handoff 2025-11-22-module-split (archived)
```

---

## Git Integration

### Option 1: Gitignore All Handoffs (Recommended for sbx-lite)

**Configuration:**
```gitignore
# .gitignore
.claude/handoffs/*.md
!.claude/handoffs/README.md
!.claude/handoffs/archive/
```

**Workflow:**
```bash
# 1. Create handoff (local only, automatically ignored)
/handoff "implement feature"

# 2. Work continues across sessions (still local)
/pickup implement-feature

# 3. After PR merge, archive (tracked in git)
bash .claude/scripts/manage-handoffs.sh archive 2025-11-22-feature.md

# 4. Sanitized archive is committed
git add .claude/handoffs/archive/2025-11-22-feature.md
git commit -m "docs: archive handoff for feature (PR #42)"
```

**Pros:**
- ✅ No accidental sensitive data commits
- ✅ Clean working directory
- ✅ Archives preserved for reference

**Cons:**
- ❌ Can't collaborate on active handoffs

### Option 2: Selective Commit (For Collaboration)

**Configuration:**
```gitignore
# .gitignore
.claude/handoffs/*-wip-*.md    # Work in progress (ignore)
.claude/handoffs/*-private-*.md # Private handoffs (ignore)
# All other handoffs can be committed
```

**Workflow:**
```bash
# 1. Create private handoff (automatically ignored)
/handoff "implement feature (WIP)"
# Saves as: 2025-11-22-wip-implement-feature.md

# 2. When ready to share, sanitize and rename
bash .claude/scripts/sanitize-handoff.sh 2025-11-22-wip-feature.md --in-place
mv .claude/handoffs/2025-11-22-wip-feature.md \
   .claude/handoffs/2025-11-22-feature.md

# 3. Commit for collaboration
git add .claude/handoffs/2025-11-22-feature.md
git commit -m "docs: add handoff for feature collaboration"
```

**Pros:**
- ✅ Enables collaboration on active handoffs
- ✅ Flexible (private vs public)

**Cons:**
- ❌ Requires manual sanitization
- ❌ Risk of accidental sensitive data commit

### Option 3: Post-Commit Hook Validation

**Configuration:**
```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash

# Check if any handoff being committed contains sensitive data
for file in $(git diff --cached --name-only | grep '.claude/handoffs/.*\.md$'); do
  if grep -qE '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})' "$file"; then
    echo "❌ ERROR: Handoff contains sensitive data: $file"
    echo "Run: bash .claude/scripts/sanitize-handoff.sh $file --in-place"
    exit 1
  fi
done
```

**Pros:**
- ✅ Catches sensitive data before commit
- ✅ Automatic validation

**Cons:**
- ❌ May have false positives
- ❌ Requires hook installation

---

## Best Practices

### 1. Age-Based Cleanup

**Rule:** Archive or delete handoffs older than 60 days

**Rationale:**
- After 60 days, context is stale
- Architectural decisions should be in docs by then
- Keeps handoffs directory manageable

**Automation:**
```bash
# Monthly cleanup (add to crontab or run manually)
bash .claude/scripts/manage-handoffs.sh cleanup --older-than 60 --auto
```

### 2. PR-Linked Cleanup

**Rule:** Archive handoffs when associated PR is merged

**Workflow:**
```bash
# 1. Reference handoff in PR description
PR #42: Implement Reality validation
Handoff: .claude/handoffs/2025-11-22-reality-validation.md

# 2. After PR merge, archive handoff
bash .claude/scripts/manage-handoffs.sh archive 2025-11-22-reality-validation.md

# 3. Update PR with archive location
Comment: "Handoff archived at .claude/handoffs/archive/2025-11-22-reality-validation.md"
```

### 3. Extract Before Delete

**Rule:** For complex features, extract architectural decisions before deleting handoffs

**Process:**
```bash
# 1. Extract key decisions
bash .claude/scripts/extract-decisions.sh 2025-11-22-module-split.md

# 2. Verify extraction
cat .claude/ARCHITECTURE_DECISIONS.md | grep "2025-11-22"

# 3. Delete handoff (decisions preserved)
bash .claude/scripts/manage-handoffs.sh delete 2025-11-22-module-split.md
```

**Benefit:** Preserve institutional knowledge, reduce clutter

### 4. Sanitize Before Sharing

**Rule:** Always sanitize before committing or sharing handoffs

**Checklist:**
- [ ] Run sanitization script
- [ ] Manually review for domain-specific sensitive data
- [ ] Verify no credentials or tokens
- [ ] Check for internal server names/IPs

**Command:**
```bash
bash .claude/scripts/sanitize-handoff.sh 2025-11-22-feature.md --in-place
git diff .claude/handoffs/2025-11-22-feature.md  # Review changes
```

### 5. Archive Structure

**Recommended structure:**
```
.claude/handoffs/
├── README.md                          # Usage guide
├── 2025-11-22-active-feature.md      # Active work
├── 2025-11-23-wip-another-feature.md # WIP (gitignored)
└── archive/
    ├── 2025-10-01-reality-validation.md
    ├── 2025-10-15-module-split.md
    └── 2025-11-01-backup-encryption.md
```

**Benefits:**
- Clear separation of active vs completed
- Archives preserved for reference
- Easy to find recent handoffs

---

## Cleanup Decision Tree

```
┌─────────────────────────────┐
│ Handoff work completed?     │
└──────────┬──────────────────┘
           │
    ┌──────▼──────┐
    │ NO          │ YES
    │             │
    ▼             ▼
Keep in      ┌────────────────────┐
handoffs/    │ PR merged?         │
             └──┬─────────────────┘
                │
         ┌──────▼──────┐
         │ NO          │ YES
         │             │
         ▼             ▼
    Keep until    ┌──────────────────────┐
    PR merges     │ Complex/important?   │
                  └──┬───────────────────┘
                     │
              ┌──────▼──────┐
              │ NO          │ YES
              │             │
              ▼             ▼
         ┌────────┐    ┌─────────────────┐
         │ DELETE │    │ EXTRACT → ARCHIVE│
         └────────┘    └─────────────────┘
```

---

## Quick Reference

### Daily Operations
```bash
# Create handoff
/handoff "purpose"

# Resume handoff
/pickup handoff-slug

# List active handoffs
ls -lh .claude/handoffs/*.md
```

### Weekly Cleanup
```bash
# Interactive cleanup wizard
bash .claude/scripts/manage-handoffs.sh cleanup --interactive

# Review handoffs older than 30 days
bash .claude/scripts/manage-handoffs.sh list --older-than 30
```

### After PR Merge
```bash
# Option 1: Archive (for complex features)
bash .claude/scripts/manage-handoffs.sh archive YYYY-MM-DD-slug.md

# Option 2: Extract & delete (for important decisions)
bash .claude/scripts/extract-decisions.sh YYYY-MM-DD-slug.md
bash .claude/scripts/manage-handoffs.sh delete YYYY-MM-DD-slug.md

# Option 3: Delete (for simple features)
bash .claude/scripts/manage-handoffs.sh delete YYYY-MM-DD-slug.md
```

### Before Sharing
```bash
# Sanitize sensitive data
bash .claude/scripts/sanitize-handoff.sh YYYY-MM-DD-slug.md --in-place

# Review changes
git diff .claude/handoffs/YYYY-MM-DD-slug.md

# Commit if safe
git add .claude/handoffs/YYYY-MM-DD-slug.md
git commit -m "docs: add handoff for collaboration"
```

---

## Recommended Workflow for sbx-lite

**Phase 1: Active Development**
- Create handoffs locally (auto-gitignored)
- Work across sessions with /pickup
- Handoffs remain private

**Phase 2: PR Review**
- Optionally sanitize and commit for collaboration
- Reference handoff in PR description
- Keep until PR merges

**Phase 3: Post-Merge**
- For complex features: Extract decisions → Archive
- For simple features: Delete
- For important decisions: Extract → Delete

**Phase 4: Periodic Cleanup**
- Monthly: Review handoffs older than 60 days
- Archive or delete stale handoffs
- Keep archives for historical reference (max 1 year)

---

## Next Steps

To implement this lifecycle management system:

1. **Create automation scripts** (manage-handoffs.sh, sanitize-handoff.sh, extract-decisions.sh)
2. **Update .gitignore** to ignore active handoffs
3. **Create archive directory** structure
4. **Document in CONTRIBUTING.md** quick reference
5. **Add to WORKFLOWS.md** detailed lifecycle guide

**Would you like me to create these automation scripts?**

---

**Document Version:** 1.0
**Last Updated:** 2025-11-22
**Status:** Proposed (pending script implementation)
