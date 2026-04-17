#!/usr/bin/env bash
set -euo pipefail

REPO="MosRat/vscode-server-sysroot-builder"
TAG=""
INSTALL_DIR="/opt/vscode-sysroot"
KEEP_ARCHIVE=0
USE_WGET=0
PATCHELF_VERSION="0.18.0"

usage() {
  cat <<USAGE
Usage: $0 [options]
  --repo owner/name         GitHub repo, default: MosRat/vscode-server-sysroot-builder
  --tag vX.Y.Z              Release tag, default: latest release
  --install-dir PATH        Sysroot install dir, default: /opt/vscode-sysroot
  --keep-archive            Keep downloaded release files in temp dir
  --wget                    Prefer wget instead of curl
  -h, --help                Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --keep-archive) KEEP_ARCHIVE=1; shift ;;
    --wget) USE_WGET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

fetch() {
  local url="$1" out="$2"
  if [ "$USE_WGET" -eq 1 ]; then
    wget -q -O "$out" "$url"
  else
    curl -fsSL "$url" -o "$out"
  fi
}

api() {
  local url="$1"
  if [ "$USE_WGET" -eq 1 ]; then
    wget -qO- "$url"
  else
    curl -fsSL "$url"
  fi
}

if [ -z "$TAG" ]; then
  TAG=$(api "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
fi

if [ -z "$TAG" ]; then
  echo "Could not determine release tag for ${REPO}" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
cleanup() {
  if [ "$KEEP_ARCHIVE" -eq 0 ]; then
    rm -rf "$TMPDIR"
  else
    echo "Kept downloaded files in $TMPDIR"
  fi
}
trap cleanup EXIT

ARCHIVE="vscode-sysroot-x86_64-glibc228.tgz"
SUMFILE="${ARCHIVE}.sha256"
BASE="https://github.com/${REPO}/releases/download/${TAG}"

fetch "${BASE}/${ARCHIVE}" "$TMPDIR/$ARCHIVE"
fetch "${BASE}/${SUMFILE}" "$TMPDIR/$SUMFILE"

(
  cd "$TMPDIR"
  sha256sum -c "$SUMFILE"
)

RAW_BASE="https://raw.githubusercontent.com/${REPO}/${TAG}"
INSTALLER_URL="${RAW_BASE}/scripts/install-remote.sh"
fetch "$INSTALLER_URL" "$TMPDIR/install-remote.sh"
chmod +x "$TMPDIR/install-remote.sh"

bash "$TMPDIR/install-remote.sh" "$TMPDIR/$ARCHIVE" "$INSTALL_DIR"
