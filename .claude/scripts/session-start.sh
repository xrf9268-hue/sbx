#!/usr/bin/env bash
# .claude/scripts/session-start.sh - SessionStart hook for sbx-lite
#
# Smart session initialization with caching for efficiency.
# - First run: Installs deps and runs full validation
# - Subsequent runs: Quick status check only (~0.1s)
#
# Cache invalidation: Delete /tmp/sbx-session-* files to force re-check

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

# Cache keys based on project path
CACHE_DIR="${TMPDIR:-/tmp}"
PROJECT_HASH=$(echo "$PROJECT_DIR" | md5sum | cut -c1-8)
SETUP_MARKER="$CACHE_DIR/sbx-setup-done-$PROJECT_HASH"
BOOTSTRAP_CACHE="$CACHE_DIR/sbx-bootstrap-$PROJECT_HASH"
GH_INSTALL_LOG="$CACHE_DIR/sbx-gh-install-$PROJECT_HASH.log"

#==============================================================================
# Environment Detection
#==============================================================================

if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
  echo "Desktop: Run 'bash hooks/install-hooks.sh' to set up git hooks."
  exit 0
fi

#==============================================================================
# CLAUDE_ENV_FILE Support (Persist PATH across Bash commands)
#==============================================================================

# Ensure /usr/local/bin is in PATH for tools installed by this script
# CLAUDE_ENV_FILE is sourced before each Bash command by Claude Code
setup_claude_env() {
  local env_file="${CLAUDE_ENV_FILE:-}"

  # Skip if CLAUDE_ENV_FILE not set
  [[ -z "$env_file" ]] && return 0

  # Create env file if it doesn't exist
  if [[ ! -f "$env_file" ]]; then
    touch "$env_file" 2>/dev/null || return 0
  fi

  # Add /usr/local/bin to PATH if not already present in env file
  if ! grep -q 'PATH=.*\/usr\/local\/bin' "$env_file" 2>/dev/null; then
    cat >>"$env_file" <<'EOF'
# sbx-lite: Ensure installed tools are in PATH
export PATH="/usr/local/bin:$PATH"
EOF
  fi
}

#==============================================================================
# First Run Setup (runs once, then cached)
#==============================================================================

first_run_setup() {
  echo "First run: Setting up sbx-lite environment..."

  # Install git hooks
  if [[ -x "hooks/install-hooks.sh" ]]; then
    bash hooks/install-hooks.sh >/dev/null 2>&1 && echo "  [OK] Git hooks" || echo "  [WARN] Git hooks"
  fi

  # Check and install essential deps
  local missing=()
  for dep in jq openssl; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  Installing: ${missing[*]}..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1 || true
    fi
  fi

  # Install shellcheck/shfmt (optional, best-effort)
  for tool in shellcheck shfmt; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      install_tool "$tool"
    fi
  done

  # Install gh (GitHub CLI, optional, best-effort)
  if ! command -v gh >/dev/null 2>&1; then
    install_gh
  fi

  # Persist PATH to CLAUDE_ENV_FILE for subsequent commands
  setup_claude_env

  # Run bootstrap validation once
  if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
    if bash tests/unit/test_bootstrap_constants.sh >"$BOOTSTRAP_CACHE.log" 2>&1; then
      echo "OK" >"$BOOTSTRAP_CACHE"
      echo "  [OK] Bootstrap validation"
    else
      echo "FAIL" >"$BOOTSTRAP_CACHE"
      echo "  [FAIL] Bootstrap - see $BOOTSTRAP_CACHE.log"
    fi
  fi

  # Mark setup complete
  date +%s >"$SETUP_MARKER"
  echo "Setup complete."
}

install_tool() {
  local tool="$1"
  case "$tool" in
    shellcheck)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y -qq shellcheck >/dev/null 2>&1 || true
      fi
      if ! command -v shellcheck >/dev/null 2>&1; then
        local ver="v0.10.0"
        wget -qO- "https://github.com/koalaman/shellcheck/releases/download/$ver/shellcheck-$ver.linux.x86_64.tar.xz" 2>/dev/null |
          tar -xJf - -C /tmp/ 2>/dev/null &&
          sudo mv "/tmp/shellcheck-$ver/shellcheck" /usr/local/bin/ 2>/dev/null || true
      fi
      ;;
    shfmt)
      local ver="v3.10.0"
      wget -qO /tmp/shfmt "https://github.com/mvdan/sh/releases/download/$ver/shfmt_${ver}_linux_amd64" 2>/dev/null &&
        sudo mv /tmp/shfmt /usr/local/bin/shfmt && sudo chmod +x /usr/local/bin/shfmt 2>/dev/null || true
      ;;
  esac
}

install_gh() {
  local gh_version='' arch='' ver='' tmp_dir=''

  echo "=== gh install $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >>"$GH_INSTALL_LOG" 2>/dev/null || true

  # Detect latest version from GitHub API
  gh_version="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>>"$GH_INSTALL_LOG" |
    grep -o '"tag_name":\s*"v[^"]*"' | head -1 | grep -o 'v[^"]*')" || true

  if [[ -z "${gh_version:-}" ]]; then
    echo "  [WARN] gh: could not determine latest version, see $GH_INSTALL_LOG" >&2
    return 0
  fi

  ver="${gh_version#v}"

  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *)
      echo "  [WARN] gh: unsupported architecture $(uname -m), skipping" >&2
      return 0
      ;;
  esac

  tmp_dir="$(mktemp -d /tmp/gh-install-XXXXXX)"
  if curl -fsSL -o "${tmp_dir}/gh.tar.gz" \
    "https://github.com/cli/cli/releases/download/${gh_version}/gh_${ver}_linux_${arch}.tar.gz" 2>>"$GH_INSTALL_LOG"; then
    if tar -xzf "${tmp_dir}/gh.tar.gz" -C "${tmp_dir}" 2>>"$GH_INSTALL_LOG" &&
      sudo mv "${tmp_dir}/gh_${ver}_linux_${arch}/bin/gh" /usr/local/bin/gh 2>>"$GH_INSTALL_LOG" &&
      sudo chmod +x /usr/local/bin/gh 2>>"$GH_INSTALL_LOG"; then
      echo "  [OK] gh ${gh_version}"
    else
      echo "  [WARN] gh: extract/install failed, see $GH_INSTALL_LOG" >&2
    fi
  else
    echo "  [WARN] gh: download failed, see $GH_INSTALL_LOG" >&2
  fi
  rm -rf "${tmp_dir}"
}

#==============================================================================
# Quick Status Check (subsequent runs)
#==============================================================================

quick_status() {
  local status=()

  # Git hooks
  [[ -f ".git/hooks/pre-commit" ]] && status+=("hooks:OK") || status+=("hooks:MISS")

  # Essential deps
  local deps_ok=true
  for dep in jq openssl bash git; do
    command -v "$dep" >/dev/null 2>&1 || deps_ok=false
  done
  $deps_ok && status+=("deps:OK") || status+=("deps:MISS")

  # Bootstrap (from cache)
  if [[ -f "$BOOTSTRAP_CACHE" ]]; then
    [[ "$(cat "$BOOTSTRAP_CACHE")" == "OK" ]] && status+=("boot:OK") || status+=("boot:FAIL")
  fi

  # gh CLI (optional, best-effort; retried on demand from main)
  command -v gh >/dev/null 2>&1 && status+=("gh:OK") || status+=("gh:MISS")

  # Branch info
  local branch commit
  branch=$(git branch --show-current 2>/dev/null || echo "?")
  commit=$(git log --oneline -1 2>/dev/null | cut -c1-7 || echo "?")

  echo "sbx: ${status[*]} | $branch ($commit)"

  # Show issues only if something is wrong
  if [[ ! -f ".git/hooks/pre-commit" ]] || ! $deps_ok; then
    echo "Issues: Run 'rm $SETUP_MARKER' then restart to re-setup"
  fi
}

#==============================================================================
# Main
#==============================================================================

# Check if setup already done (file exists and is less than 7 days old)
if [[ -f "$SETUP_MARKER" ]]; then
  setup_age=$(($(date +%s) - $(cat "$SETUP_MARKER")))
  if [[ $setup_age -lt 604800 ]]; then # 7 days in seconds
    # Best-effort retry: gh is optional so first_run_setup doesn't block on it,
    # but if it failed we want subsequent sessions to retry until it succeeds.
    if ! command -v gh >/dev/null 2>&1; then
      install_gh
    fi
    quick_status
    exit 0
  fi
fi

# First run or cache expired
first_run_setup
quick_status

exit 0
