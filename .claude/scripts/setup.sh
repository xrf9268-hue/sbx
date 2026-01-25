#!/usr/bin/env bash
# .claude/scripts/setup.sh - Setup hook for sbx-lite (one-time initialization)
#
# Runs only with: claude --init, --init-only, or --maintenance
# NOT run on every session start - for that see session-start.sh
#
# Purpose: Install dependencies and configure development environment

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

#==============================================================================
# Environment Detection
#==============================================================================

# Desktop environment - provide minimal guidance
if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo "Desktop: Run 'bash hooks/install-hooks.sh' manually to set up git hooks."
    exit 0
fi

echo "Setting up sbx-lite development environment..."

#==============================================================================
# 1. Install Git Hooks
#==============================================================================

if [[ -x "hooks/install-hooks.sh" ]]; then
    echo "Installing git hooks..."
    if bash hooks/install-hooks.sh > /tmp/hook-install.log 2>&1; then
        echo "  [OK] Git hooks installed"
    else
        echo "  [WARN] Git hooks: check /tmp/hook-install.log"
    fi
else
    echo "  [SKIP] hooks/install-hooks.sh not found"
fi

#==============================================================================
# 2. Install Dependencies
#==============================================================================

# Essential deps (required for core functionality)
essential_deps=(jq openssl bash git)
# Optional deps (code quality tools)
optional_deps=(shellcheck shfmt)

install_packages() {
    local packages=("$@")
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "${packages[@]}" >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q "${packages[@]}" >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet "${packages[@]}" >/dev/null 2>&1
    fi
}

# Check and install essential deps
essential_missing=()
for dep in "${essential_deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        essential_missing+=("$dep")
    fi
done

if [[ ${#essential_missing[@]} -gt 0 ]]; then
    echo "Installing essential deps: ${essential_missing[*]}..."
    install_packages "${essential_missing[@]}" || true
fi

# Install shellcheck
if ! command -v shellcheck >/dev/null 2>&1; then
    echo "Installing shellcheck..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y -qq shellcheck >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q ShellCheck >/dev/null 2>&1 || true
    fi

    # Fallback to binary download
    if ! command -v shellcheck >/dev/null 2>&1; then
        SHELLCHECK_VERSION="v0.10.0"
        if wget -qO- "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" 2>/dev/null | tar -xJf - -C /tmp/ 2>/dev/null; then
            sudo mv "/tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ && sudo chmod +x /usr/local/bin/shellcheck
            echo "  [OK] shellcheck installed from binary"
        fi
    else
        echo "  [OK] shellcheck installed"
    fi
fi

# Install shfmt (NOT in apt - use snap, go, or direct binary)
if ! command -v shfmt >/dev/null 2>&1; then
    echo "Installing shfmt..."
    if command -v snap >/dev/null 2>&1; then
        sudo snap install shfmt >/dev/null 2>&1 || true
    elif command -v go >/dev/null 2>&1; then
        go install mvdan.cc/sh/v3/cmd/shfmt@latest >/dev/null 2>&1 || true
        export PATH="$PATH:$HOME/go/bin"
        if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
            echo "export PATH=\"\$PATH:\$HOME/go/bin\"" >> "$CLAUDE_ENV_FILE"
        fi
    else
        # Direct binary download
        SHFMT_VERSION="v3.10.0"
        if wget -qO /tmp/shfmt "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64" 2>/dev/null; then
            sudo mv /tmp/shfmt /usr/local/bin/shfmt && sudo chmod +x /usr/local/bin/shfmt
            echo "  [OK] shfmt installed from binary"
        fi
    fi

    if command -v shfmt >/dev/null 2>&1; then
        echo "  [OK] shfmt installed"
    fi
fi

#==============================================================================
# 3. Final Status
#==============================================================================

export PATH="$PATH:$HOME/go/bin:/usr/local/bin"

echo ""
echo "Setup complete. Dependency status:"
for dep in "${essential_deps[@]}" "${optional_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  [OK] $dep"
    else
        echo "  [MISSING] $dep"
    fi
done

exit 0
