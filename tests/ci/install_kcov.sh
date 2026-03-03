#!/usr/bin/env bash
# tests/ci/install_kcov.sh - Install or locate kcov binary for CI usage

set -euo pipefail
exec 3>&1
exec 1>&2

KCOV_VERSION="v41"
INSTALL_DIR="/tmp/kcov-bin"
FORCE_REBUILD=0

print_result() {
  echo "$1" >&3
}

usage() {
  cat <<USAGE
Usage: install_kcov.sh [--version v41] [--install-dir /tmp/kcov-bin] [--force-rebuild]

Prints the resolved kcov binary path on stdout.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      KCOV_VERSION="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --force-rebuild)
      FORCE_REBUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $FORCE_REBUILD -eq 0 ]] && [[ -x "$INSTALL_DIR/bin/kcov" ]]; then
  print_result "$INSTALL_DIR/bin/kcov"
  exit 0
fi

if [[ $FORCE_REBUILD -eq 0 ]] && command -v kcov >/dev/null 2>&1; then
  print_result "$(command -v kcov)"
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Error: automatic kcov build is only supported on Linux runners." >&2
  echo "Install kcov manually and rerun with KCOV_BIN set." >&2
  exit 1
fi

BUILD_ROOT="/tmp/kcov-build-${KCOV_VERSION#v}"
SRC_DIR="$BUILD_ROOT/src"
BUILD_DIR="$BUILD_ROOT/build"

sudo apt-get update -qq
sudo apt-get install -y \
  cmake \
  make \
  g++ \
  git \
  binutils-dev \
  libcurl4-openssl-dev \
  libelf-dev \
  libdw-dev \
  libiberty-dev \
  zlib1g-dev \
  libssl-dev

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
git clone --depth 1 --branch "$KCOV_VERSION" https://github.com/SimonKagstrom/kcov.git "$SRC_DIR"

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
cmake --build "$BUILD_DIR" -- -j"$(nproc)"
cmake --install "$BUILD_DIR"

if [[ ! -x "$INSTALL_DIR/bin/kcov" ]]; then
  echo "Error: kcov installation completed but binary not found at $INSTALL_DIR/bin/kcov" >&2
  exit 1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$INSTALL_DIR/bin" >> "$GITHUB_PATH"
fi

print_result "$INSTALL_DIR/bin/kcov"
