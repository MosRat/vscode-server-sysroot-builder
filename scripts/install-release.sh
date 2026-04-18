#!/usr/bin/env bash
set -euo pipefail

REPO="MosRat/vscode-server-sysroot-builder"
TAG=""
INSTALL_DIR="/opt/vscode-sysroot"
KEEP_ARCHIVE=0
USE_WGET=0
PATCH_SERVER=0

ARCHIVE="vscode-sysroot-x86_64-glibc228.tgz"
SUMFILE="${ARCHIVE}.sha256"

PROXY_PREFIX="https://ghfast.top/"
CONNECT_TIMEOUT=5
MAX_TIME=30

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
  --keep-archive            Keep downloaded files in temp dir
  --wget                    Prefer wget instead of curl
  --patch                   Patch existing VS Code Server binaries after install
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
    --patch) PATCH_SERVER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

proxy_url() {
  printf '%s%s\n' "$PROXY_PREFIX" "$1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_downloader() {
  if [ "$USE_WGET" -eq 1 ]; then
    if have_cmd wget; then
      DOWNLOADER="wget"
      return
    fi
    error "--wget was specified but wget is not installed"
    exit 1
  fi

  if have_cmd curl; then
    DOWNLOADER="curl"
  elif have_cmd wget; then
    DOWNLOADER="wget"
  else
    error "Neither curl nor wget is installed"
    exit 1
  fi
}

fetch_json_api() {
  local url="$1"

  if [ "$DOWNLOADER" = "curl" ]; then
    curl -fsSL \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time 30 \
      "$url"
  else
    wget -qO- \
      --timeout="$CONNECT_TIMEOUT" \
      --tries=1 \
      "$url"
  fi
}

get_effective_url() {
  local url="$1"

  if have_cmd curl; then
    curl -fsSL \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time 60 \
      -L \
      -o /dev/null \
      -w '%{url_effective}' \
      "$url"
  else
    wget --server-response --spider --max-redirect=10 \
      --timeout="$CONNECT_TIMEOUT" \
      --tries=1 \
      "$url" 2>&1 \
      | awk '/^  Location: /{gsub("\r","",$2); loc=$2} END{print loc}'
  fi
}

resolve_tag_from_latest_page() {
  local latest_url="$1"
  local effective=""

  effective="$(get_effective_url "$latest_url" || true)"
  [ -n "$effective" ] || return 1

  printf '%s\n' "$effective" \
    | sed -n 's#^.*/releases/tag/\([^/?#]*\).*$#\1#p' \
    | head -n1
}

resolve_latest_tag() {
  if [ -n "$TAG" ]; then
    success "Using specified release tag: $TAG"
    return
  fi

  info "Resolving latest release tag from GitHub API..."
  TAG="$(fetch_json_api "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' \
    | head -n1 || true)"

  if [ -n "$TAG" ]; then
    success "Using latest release tag: $TAG"
    return
  fi

  warn "GitHub API failed, trying releases/latest redirect..."
  TAG="$(resolve_tag_from_latest_page "https://github.com/${REPO}/releases/latest" || true)"

  if [ -n "$TAG" ]; then
    success "Resolved tag via direct releases/latest: $TAG"
    return
  fi

  warn "Direct GitHub failed, trying ghfast proxy..."
  TAG="$(resolve_tag_from_latest_page "$(proxy_url "https://github.com/${REPO}/releases/latest")" || true)"

  if [ -n "$TAG" ]; then
    success "Resolved tag via ghfast proxy: $TAG"
    return
  fi

  error "Could not determine release tag automatically"
  error "Try again later or specify --tag vX.Y.Z"
  exit 1
}

download_with_curl() {
  local url="$1" out="$2"
  curl -fL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    --progress-bar \
    "$url" -o "$out"
}

download_with_wget() {
  local url="$1" out="$2"
  wget -q \
    --show-progress \
    --progress=bar:force \
    --timeout="$CONNECT_TIMEOUT" \
    --tries=1 \
    -O "$out" "$url"
}

download_once() {
  local url="$1" out="$2"
  echo "download_once $url to $out"
  if [ "$DOWNLOADER" = "curl" ]; then
    download_with_curl "$url" "$out"
  else
    download_with_wget "$url" "$out"
  fi
}

fetch_file() {
  local url="$1" out="$2" label="$3"
  local proxy

  proxy="$(proxy_url "$url")"

  info "Downloading ${label} from GitHub..."
  if download_once "$url" "$out"; then
    printf '\n'
    success "Downloaded ${label} from GitHub"
    return 0
  fi

  printf '\n'
  warn "GitHub download failed for ${label}, retrying via ghfast proxy..."
  if download_once "$proxy" "$out"; then
    printf '\n'
    success "Downloaded ${label} via ghfast proxy"
    return 0
  fi

  printf '\n'
  error "Failed to download ${label} from both GitHub and ghfast proxy"
  return 1
}

verify_checksum() {
  local file="$1" sumfile="$2"
  local expected actual

  expected="$(awk 'NF {print $1; exit}' "$sumfile" | tr -d '\r')"
  if [ -z "$expected" ]; then
    error "Could not parse checksum from $sumfile"
    exit 1
  fi

  actual="$(sha256sum "$file" | awk '{print $1}')"

  if [ "$expected" != "$actual" ]; then
    error "Checksum mismatch for $(basename "$file")"
    error "Expected: $expected"
    error "Actual:   $actual"
    exit 1
  fi
}

detect_downloader
info "Downloader: $DOWNLOADER"

resolve_latest_tag

TMPDIR="$(mktemp -d)"
cleanup() {
  if [ "$KEEP_ARCHIVE" -eq 0 ]; then
    rm -rf "$TMPDIR"
  else
    warn "Kept downloaded files in $TMPDIR"
  fi
}
trap cleanup EXIT

# 压缩包依赖 release tag
BASE="https://github.com/${REPO}/releases/download/${TAG}"
# 脚本强制依赖 main 分支最新提交
SCRIPT_BASE="https://raw.githubusercontent.com/${REPO}/main"

fetch_file "${BASE}/${ARCHIVE}" "$TMPDIR/$ARCHIVE" "$ARCHIVE"
fetch_file "${BASE}/${SUMFILE}" "$TMPDIR/$SUMFILE" "$SUMFILE"

fetch_file "${SCRIPT_BASE}/scripts/install-remote.sh" "$TMPDIR/install-remote.sh" "install-remote.sh"
fetch_file "${SCRIPT_BASE}/scripts/patch-vscode-server.sh" "$TMPDIR/patch-vscode-server.sh" "patch-vscode-server.sh"

chmod +x "$TMPDIR/install-remote.sh" "$TMPDIR/patch-vscode-server.sh"

info "Verifying checksum..."
verify_checksum "$TMPDIR/$ARCHIVE" "$TMPDIR/$SUMFILE"
success "Checksum verification passed"

info "Installing sysroot to ${INSTALL_DIR}..."
bash "$TMPDIR/install-remote.sh" "$TMPDIR/$ARCHIVE" "$INSTALL_DIR"
success "Sysroot installation finished"

if [ "$PATCH_SERVER" -eq 1 ]; then
  info "Patching existing VS Code Server binaries..."
  bash "$TMPDIR/patch-vscode-server.sh"
  success "VS Code Server patch finished"
fi

success "Installation finished"
