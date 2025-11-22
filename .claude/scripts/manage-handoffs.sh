#!/usr/bin/env bash
set -euo pipefail

# Handoff Lifecycle Manager
# Manages handoff files: list, archive, delete, cleanup
# Usage: bash .claude/scripts/manage-handoffs.sh <command> [options]

# ============================================================================
# Configuration
# ============================================================================

readonly HANDOFFS_DIR=".claude/handoffs"
readonly ARCHIVE_DIR="${HANDOFFS_DIR}/archive"
readonly DECISIONS_DOC=".claude/ARCHITECTURE_DECISIONS.md"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

# Get age of file in days
get_file_age_days() {
    local file="$1"
    local now
    local mtime
    local age_seconds

    now=$(date +%s)

    # Cross-platform modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        mtime=$(stat -f %m "$file")
    else
        # Linux
        mtime=$(stat -c %Y "$file")
    fi

    age_seconds=$((now - mtime))
    echo $((age_seconds / 86400))
}

# Extract date from filename (YYYY-MM-DD format)
get_handoff_date() {
    local filename="$1"
    if [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})- ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Extract slug from filename
get_handoff_slug() {
    local filename="$1"
    local basename
    basename=$(basename "$filename" .md)
    if [[ "$basename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# ============================================================================
# Command: list
# ============================================================================

cmd_list() {
    local older_than=0
    local pattern="*.md"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --older-than)
                older_than="$2"
                shift 2
                ;;
            --pattern)
                pattern="$2"
                shift 2
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    if [[ ! -d "$HANDOFFS_DIR" ]]; then
        log_warning "No handoffs directory found"
        return 0
    fi

    local count=0
    local total=0

    echo "Handoffs in ${HANDOFFS_DIR}:"
    echo ""

    for file in "${HANDOFFS_DIR}"/${pattern}; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "README.md" ]] && continue

        ((total++))

        local age
        age=$(get_file_age_days "$file")

        if [[ $age -ge $older_than ]]; then
            local date
            local slug
            local size

            date=$(get_handoff_date "$(basename "$file")")
            slug=$(get_handoff_slug "$(basename "$file")")
            size=$(du -h "$file" | cut -f1)

            printf "  • %s\n" "$(basename "$file")"
            printf "    Date: %s  |  Age: %d days  |  Size: %s\n" "$date" "$age" "$size"
            printf "    Slug: %s\n" "$slug"
            echo ""

            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        if [[ $older_than -gt 0 ]]; then
            log_info "No handoffs older than $older_than days"
        else
            log_info "No handoffs found"
        fi
    else
        log_success "Found $count handoff(s)"
        if [[ $older_than -gt 0 ]]; then
            log_info "($((total - count)) handoffs excluded by age filter)"
        fi
    fi
}

# ============================================================================
# Command: archive
# ============================================================================

cmd_archive() {
    local filename="$1"

    [[ -z "$filename" ]] && die "Usage: manage-handoffs.sh archive <filename>"

    local source="${HANDOFFS_DIR}/${filename}"

    [[ ! -f "$source" ]] && die "Handoff not found: $source"

    # Create archive directory if needed
    mkdir -p "$ARCHIVE_DIR"

    local dest="${ARCHIVE_DIR}/${filename}"

    if [[ -f "$dest" ]]; then
        log_warning "Archive already exists: $dest"
        read -rp "Overwrite? [y/N] " confirm
        [[ "$confirm" != "y" ]] && die "Aborted"
    fi

    mv "$source" "$dest"

    log_success "Archived: $filename → archive/"
    log_info "Location: $dest"
    log_info "To commit: git add $dest"
}

# ============================================================================
# Command: delete
# ============================================================================

cmd_delete() {
    local filename="$1"

    [[ -z "$filename" ]] && die "Usage: manage-handoffs.sh delete <filename>"

    local source="${HANDOFFS_DIR}/${filename}"

    [[ ! -f "$source" ]] && die "Handoff not found: $source"

    log_warning "About to delete: $filename"
    read -rp "Are you sure? [y/N] " confirm

    if [[ "$confirm" == "y" ]]; then
        rm "$source"
        log_success "Deleted: $filename"
    else
        log_info "Aborted"
    fi
}

# ============================================================================
# Command: cleanup (interactive)
# ============================================================================

cmd_cleanup() {
    local older_than=30
    local interactive=true
    local auto=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --older-than)
                older_than="$2"
                shift 2
                ;;
            --interactive)
                interactive=true
                shift
                ;;
            --auto)
                auto=true
                interactive=false
                shift
                ;;
            --hybrid)
                # Hybrid mode: extract decisions, archive old handoffs
                log_info "Hybrid cleanup mode"
                older_than=60
                auto=true
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    if [[ ! -d "$HANDOFFS_DIR" ]]; then
        log_warning "No handoffs directory found"
        return 0
    fi

    local candidates=()

    # Find candidates for cleanup
    for file in "${HANDOFFS_DIR}"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "README.md" ]] && continue

        local age
        age=$(get_file_age_days "$file")

        if [[ $age -ge $older_than ]]; then
            candidates+=("$file")
        fi
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        log_info "No handoffs older than $older_than days"
        return 0
    fi

    log_info "Found ${#candidates[@]} handoff(s) older than $older_than days"
    echo ""

    for file in "${candidates[@]}"; do
        local filename
        local age
        local slug

        filename=$(basename "$file")
        age=$(get_file_age_days "$file")
        slug=$(get_handoff_slug "$filename")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "File: $filename"
        echo "Age: $age days"
        echo "Slug: $slug"
        echo ""

        if $interactive; then
            echo "Options:"
            echo "  1) Archive (move to archive/)"
            echo "  2) Delete (permanent)"
            echo "  3) Keep (skip)"
            echo "  4) Quit cleanup"
            echo ""
            read -rp "Choice [1-4]: " choice

            case $choice in
                1)
                    cmd_archive "$filename"
                    ;;
                2)
                    rm "$file"
                    log_success "Deleted: $filename"
                    ;;
                3)
                    log_info "Kept: $filename"
                    ;;
                4)
                    log_info "Cleanup aborted"
                    return 0
                    ;;
                *)
                    log_warning "Invalid choice, keeping: $filename"
                    ;;
            esac
        elif $auto; then
            # Auto mode: archive all old handoffs
            mkdir -p "$ARCHIVE_DIR"
            mv "$file" "${ARCHIVE_DIR}/${filename}"
            log_success "Auto-archived: $filename"
        fi

        echo ""
    done

    log_success "Cleanup complete"
}

# ============================================================================
# Command: auto-archive (for post-merge hooks)
# ============================================================================

cmd_auto_archive() {
    log_info "Auto-archiving handoffs for merged PRs..."

    # Find handoffs with recent git activity (merged in last 7 days)
    local recent_files
    recent_files=$(git log --since="7 days ago" --name-only --pretty=format: | \
                   grep "^${HANDOFFS_DIR}/.*\.md$" | \
                   grep -v "README.md" | \
                   sort -u || true)

    if [[ -z "$recent_files" ]]; then
        log_info "No handoffs in recent git history"
        return 0
    fi

    mkdir -p "$ARCHIVE_DIR"

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local filename
            filename=$(basename "$file")

            # Check if associated PR is merged (heuristic: file committed but still in handoffs/)
            if git log --all --pretty=format:%s | grep -q "$filename"; then
                mv "$file" "${ARCHIVE_DIR}/${filename}"
                log_success "Auto-archived: $filename (PR merged)"
            fi
        fi
    done <<< "$recent_files"
}

# ============================================================================
# Command: extract (extract architectural decisions)
# ============================================================================

cmd_extract() {
    local filename="$1"

    [[ -z "$filename" ]] && die "Usage: manage-handoffs.sh extract <filename>"

    local source="${HANDOFFS_DIR}/${filename}"

    [[ ! -f "$source" ]] && die "Handoff not found: $source"

    log_info "Extracting architectural decisions from: $filename"

    # Create decisions document if it doesn't exist
    if [[ ! -f "$DECISIONS_DOC" ]]; then
        cat > "$DECISIONS_DOC" <<'EOF'
# Architecture Decisions

Architectural decisions extracted from handoffs and development sessions.

---

EOF
    fi

    # Extract date and slug
    local date
    local slug
    date=$(get_handoff_date "$filename")
    slug=$(get_handoff_slug "$filename")

    # Extract key sections from handoff
    local problem_solving
    local technical_concepts

    # Look for problem solving section (simplified extraction)
    if grep -q "^## .*Problem Solving" "$source"; then
        problem_solving=$(sed -n '/^## .*Problem Solving/,/^## /p' "$source" | head -n -1)
    fi

    # Look for technical concepts
    if grep -q "^## .*Technical Concepts" "$source"; then
        technical_concepts=$(sed -n '/^## .*Technical Concepts/,/^## /p' "$source" | head -n -1)
    fi

    # Append to decisions document
    {
        echo ""
        echo "## $date: $slug"
        echo ""
        if [[ -n "$technical_concepts" ]]; then
            echo "$technical_concepts"
            echo ""
        fi
        if [[ -n "$problem_solving" ]]; then
            echo "$problem_solving"
            echo ""
        fi
        echo "**Reference:** Handoff \`$filename\`"
        echo ""
        echo "---"
        echo ""
    } >> "$DECISIONS_DOC"

    log_success "Decisions extracted to: $DECISIONS_DOC"
    log_info "Review and edit as needed"
}

# ============================================================================
# Main
# ============================================================================

usage() {
    cat <<EOF
Handoff Lifecycle Manager

Usage: bash .claude/scripts/manage-handoffs.sh <command> [options]

Commands:
  list                          List all handoffs
  list --older-than <days>      List handoffs older than N days
  archive <filename>            Move handoff to archive/
  delete <filename>             Delete handoff (with confirmation)
  cleanup --interactive         Interactive cleanup wizard
  cleanup --auto --older-than N Auto-archive handoffs older than N days
  cleanup --hybrid              Extract decisions, archive old handoffs
  auto-archive                  Auto-archive handoffs for merged PRs
  extract <filename>            Extract architectural decisions to docs

Examples:
  # List all handoffs
  bash .claude/scripts/manage-handoffs.sh list

  # List handoffs older than 30 days
  bash .claude/scripts/manage-handoffs.sh list --older-than 30

  # Archive specific handoff
  bash .claude/scripts/manage-handoffs.sh archive 2025-11-22-feature.md

  # Interactive cleanup
  bash .claude/scripts/manage-handoffs.sh cleanup --interactive

  # Extract decisions before deleting
  bash .claude/scripts/manage-handoffs.sh extract 2025-11-22-feature.md
  bash .claude/scripts/manage-handoffs.sh delete 2025-11-22-feature.md

EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    local command="$1"
    shift

    case $command in
        list)
            cmd_list "$@"
            ;;
        archive)
            cmd_archive "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        auto-archive)
            cmd_auto_archive "$@"
            ;;
        extract)
            cmd_extract "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            die "Unknown command: $command (try 'help')"
            ;;
    esac
}

main "$@"
