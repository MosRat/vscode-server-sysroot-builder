#!/usr/bin/env bash
set -euo pipefail

REPO="MosRat/vscode-server-sysroot-builder"
TAG=""
INSTALL_DIR="/opt/vscode-sysroot"
KEEP_ARCHIVE=0
USE_WGET=0

ARCHIVE="vscode-sysroot-x86_64-glibc228.tgz"
SUMFILE="${ARCHIVE}.sha256"

color() {
  local code="$1"; shift
  if [ -t 1 ]; then
    printf "\033[%sm%s\033[0m\n" "$code" "$*"
  else
    printf "%s\n" "$*"
  fi
}

info()    { color "1;34" "[INFO] $*"; }
success() { color "1;32" "[ OK ] $*"; }
warn()    { color "1;33" "[WARN] $*"; }
error()   { color "1;31" "[ERR ] $*"; }

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
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

fetch_json() {
  local url="$1"
  if [ "$USE_WGET" -eq 1 ]; then
    wget -qO- "$url"
  else
    curl -fsSL "$url"
  fi
}

fetch_file() {
  local url="$1" out="$2" label="$3"
  info "Downloading ${label}..."
  if [ "$USE_WGET" -eq 1 ]; then
    wget --show-progress --progress=bar:force -O "$out" "$url"
  else
    curl -fL --progress-bar "$url" -o "$out"
  fi
  success "Downloaded ${label}"
}

info "Resolving release information for ${REPO}..."

if [ -z "$TAG" ]; then
  TAG=$(fetch_json "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
fi

if [ -z "$TAG" ]; then
  error "Could not determine release tag for ${REPO}"
  exit 1
fi

success "Using release tag: ${TAG}"

TMPDIR=$(mktemp -d)
cleanup() {
  if [ "$KEEP_ARCHIVE" -eq 0 ]; then
    rm -rf "$TMPDIR"
  else
    warn "Kept downloaded files in $TMPDIR"
  fi
}
trap cleanup EXIT

BASE="https://github.com/${REPO}/releases/download/${TAG}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${TAG}"

fetch_file "${BASE}/${ARCHIVE}" "$TMPDIR/$ARCHIVE" "$ARCHIVE"
fetch_file "${BASE}/${SUMFILE}" "$TMPDIR/$SUMFILE" "$SUMFILE"
fetch_file "${RAW_BASE}/scripts/install-remote.sh" "$TMPDIR/install-remote.sh" "install-remote.sh"

chmod +x "$TMPDIR/install-remote.sh"

info "Verifying checksum..."
(
  cd "$TMPDIR"
  sha256sum -c "$SUMFILE"
)
success "Checksum verification passed"

info "Installing sysroot to ${INSTALL_DIR}..."
bash "$TMPDIR/install-remote.sh" "$TMPDIR/$ARCHIVE" "$INSTALL_DIR"
success "Installation finished"