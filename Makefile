# Makefile for sbx-lite development

.PHONY: all check test test-unit test-installer test-quick test-integration lint syntax security coverage benchmark install-hooks clean help

# Default target
all: check

# Help message
help:
	@echo "sbx-lite Development Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  check            - Run all checks (lint + syntax + security)"
	@echo "  test             - Run all tests (unit + installer + integration)"
	@echo "  test-unit        - Run unit tests only (fast)"
	@echo "  test-installer   - Run one-liner installer tests"
	@echo "  test-quick       - Quick Reality validation tests"
	@echo "  test-integration - Full integration tests (requires sing-box)"
	@echo "  coverage         - Generate code coverage report"
	@echo "  benchmark        - Run performance benchmarks (quick)"
	@echo "  benchmark-full   - Run full benchmark suite"
	@echo "  lint             - Run ShellCheck linting"
	@echo "  syntax           - Validate bash syntax"
	@echo "  security         - Run security checks"
	@echo "  install-hooks    - Install git pre-commit hooks"
	@echo "  clean            - Clean temporary files"
	@echo ""

# Run all checks
check: lint syntax security
	@echo "✓ All checks passed!"

# ShellCheck linting
lint:
	@echo "→ Running ShellCheck..."
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "Error: shellcheck not installed. Install with: apt install shellcheck"; \
		exit 1; \
	}
	@shellcheck -x -S warning install.sh lib/*.sh 2>/dev/null || \
		(echo "✗ ShellCheck found issues"; exit 1)
	@echo "✓ ShellCheck passed"

# Syntax validation
syntax:
	@echo "→ Checking syntax..."
	@for script in install.sh lib/*.sh; do \
		[ -f "$$script" ] || continue; \
		echo "  Checking $$script..."; \
		bash -n "$$script" || exit 1; \
	done
	@echo "✓ Syntax check passed"

# Security checks
security:
	@echo "→ Running security checks..."
	@echo "  Checking for unsafe eval..."
	@! grep -rn 'eval.*\$$' --include="*.sh" lib/ || { \
		echo "✗ Unsafe eval found"; \
		exit 1; \
	}
	@echo "  Checking for temp file issues..."
	@! grep -rn '/tmp/[^$$]*\$$' --include="*.sh" lib/ | grep -v mktemp || { \
		echo "⚠  Potential temp file issues found"; \
	}
	@echo "✓ Security checks passed"

# Run all tests (unit + installer + integration)
test: test-unit test-installer
	@echo "→ Running Reality protocol test suite..."
	@if [ -f tests/test_reality.sh ]; then \
		bash tests/test_reality.sh || exit 1; \
	else \
		echo "✗ test_reality.sh not found"; \
		exit 1; \
	fi
	@echo "✓ All tests passed"

# Run unit tests only (fast, no external dependencies)
test-unit:
	@echo "→ Running unit tests..."
	@failed=0; \
	for test in tests/unit/test_*.sh; do \
		[ -f "$$test" ] || continue; \
		echo ""; \
		echo "Running $$(basename $$test)..."; \
		bash "$$test" || failed=$$((failed + 1)); \
	done; \
	echo ""; \
	if [ $$failed -eq 0 ]; then \
		echo "✓ All unit tests passed!"; \
	else \
		echo "✗ $$failed unit test(s) failed"; \
		exit 1; \
	fi

# Run one-liner installer tests
test-installer:
	@echo "→ Running one-liner installer tests..."
	@bash tests/unit/test_module_dependencies.sh || exit 1
	@bash tests/unit/test_bootstrap_functions.sh || exit 1
	@bash tests/unit/test_module_loading_sequence.sh || exit 1
	@bash tests/integration/test_oneliner_install.sh || exit 1
	@echo "✓ Installer tests passed"

# Run quick Reality tests only (validation)
test-quick:
	@echo "→ Running quick Reality validation tests..."
	@bash tests/test_reality.sh 2>&1 | grep -E "Category 1:|Category 2:|Category 3:|✓|✗"
	@echo "✓ Quick tests complete"

# Run integration tests (requires sing-box binary)
test-integration:
	@echo "→ Running integration tests..."
	@command -v sing-box >/dev/null 2>&1 || { \
		echo "✗ sing-box binary not found. Install it first."; \
		exit 1; \
	}
	@bash tests/test_reality.sh
	@echo "✓ Integration tests passed"

# Generate code coverage report
coverage:
	@echo "→ Generating coverage report..."
	@bash tests/coverage.sh generate
	@echo "✓ Coverage report generated"

# Run performance benchmarks
benchmark:
	@echo "→ Running performance benchmarks..."
	@bash tests/benchmark.sh quick
	@echo "✓ Benchmarks complete"

# Full benchmark suite (more iterations)
benchmark-full:
	@echo "→ Running full benchmark suite..."
	@BENCHMARK_ITERATIONS=1000 bash tests/benchmark.sh
	@echo "✓ Full benchmarks complete"

# Install pre-commit hook
install-hooks:
	@echo "→ Installing git hooks..."
	@if [ ! -d .git ]; then \
		echo "Error: Not a git repository"; \
		exit 1; \
	fi
	@cp tools/pre-commit .git/hooks/pre-commit 2>/dev/null || { \
		echo "⚠  Pre-commit hook not found in tools/"; \
		echo "ℹ  Run this after creating tools/pre-commit"; \
	}
	@chmod +x .git/hooks/pre-commit 2>/dev/null || true
	@echo "✓ Git hooks installed"

# Clean temporary files
clean:
	@echo "→ Cleaning temporary files..."
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -maxdepth 1 -name "sb*" -type f -mmin +10 -delete 2>/dev/null || true
	@find /tmp -maxdepth 1 -name "sing-box*" -type f -mmin +10 -delete 2>/dev/null || true
	@echo "✓ Cleanup complete"
