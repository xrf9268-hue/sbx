#!/usr/bin/env bash
# tests/ci/install_singbox.sh - Download and extract sing-box binary for CI jobs

set -euo pipefail

REQUESTED_VERSION="latest"
DOWNLOAD_DIR="/tmp/sing-box-download"
FALLBACK_VERSION="${SINGBOX_RECOMMENDED_VERSION:-1.13.0}"
ARCH="linux-amd64"

usage() {
  cat <<USAGE
Usage: install_singbox.sh [--version <latest|1.13.0|v1.13.0>] [--download-dir /tmp/sing-box-download] [--fallback-version 1.13.0]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      REQUESTED_VERSION="$2"
      shift 2
      ;;
    --download-dir)
      DOWNLOAD_DIR="$2"
      shift 2
      ;;
    --fallback-version)
      FALLBACK_VERSION="$2"
      shift 2
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

normalize_tag() {
  local raw="$1"
  if [[ "$raw" == v* ]]; then
    echo "$raw"
  else
    echo "v$raw"
  fi
}

resolve_latest_tag() {
  local tag="${SINGBOX_LATEST_TAG:-}"
  local api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local token="${GITHUB_TOKEN:-}"
  local response=""
  local i

  if [[ -n "$tag" ]] && [[ "$tag" != "null" ]]; then
    echo "$tag"
    return 0
  fi

  for i in 1 2 3; do
    if [[ -n "$token" ]]; then
      response="$(curl -fsSL --connect-timeout 10 --max-time 30 \
        -H "Authorization: token ${token}" \
        "$api" 2>/dev/null || true)"
    else
      response="$(curl -fsSL --connect-timeout 10 --max-time 30 "$api" 2>/dev/null || true)"
    fi

    tag="$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null || true)"
    if [[ -n "$tag" ]] && [[ "$tag" != "null" ]]; then
      echo "$tag"
      return 0
    fi

    sleep "$i"
  done

  echo "$(normalize_tag "$FALLBACK_VERSION")"
}

if [[ "$REQUESTED_VERSION" == "latest" ]]; then
  VERSION_TAG="$(resolve_latest_tag)"
else
  VERSION_TAG="$(normalize_tag "$REQUESTED_VERSION")"
fi

if [[ -z "$VERSION_TAG" ]] || [[ "$VERSION_TAG" == "v" ]]; then
  echo "Error: failed to resolve sing-box version (requested: $REQUESTED_VERSION)" >&2
  exit 1
fi

URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/sing-box-${VERSION_TAG#v}-${ARCH}.tar.gz"

echo "Installing sing-box ${VERSION_TAG} from ${URL}" >&2
mkdir -p "$DOWNLOAD_DIR"

if command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O /tmp/sing-box.tar.gz
else
  curl -fsSL "$URL" -o /tmp/sing-box.tar.gz
fi

tar -xzf /tmp/sing-box.tar.gz -C "$DOWNLOAD_DIR"

if ! compgen -G "$DOWNLOAD_DIR/sing-box-*/sing-box" >/dev/null; then
  echo "Error: sing-box binary not found after extraction in $DOWNLOAD_DIR" >&2
  exit 1
fi

echo "$VERSION_TAG"
