#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/vscode-sysroot-x86_64-glibc228.tgz [install_dir]" >&2
  exit 1
fi

TARBALL="$1"
INSTALL_DIR="${2:-/opt/vscode-sysroot}"
PATCHELF_VERSION="0.18.0"
PATCHELF_URL="https://github.com/NixOS/patchelf/releases/download/${PATCHELF_VERSION}/patchelf-${PATCHELF_VERSION}-x86_64.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "Tarball not found: $TARBALL" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR"

mkdir -p "$HOME/.local/bin"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

wget -q -O "$TMPDIR/patchelf.tgz" "$PATCHELF_URL"
tar -xzf "$TMPDIR/patchelf.tgz" -C "$TMPDIR"
cp "$TMPDIR/bin/patchelf" "$HOME/.local/bin/patchelf"
chmod +x "$HOME/.local/bin/patchelf"

LINKER=$(find "$INSTALL_DIR" -type f \( -name 'ld-linux-x86-64.so.2' -o -name 'ld-*.so' \) | head -n1 || true)
if [ -z "$LINKER" ]; then
  echo "Could not find dynamic linker in $INSTALL_DIR" >&2
  exit 1
fi

LIBPATH=$(find "$INSTALL_DIR" -type d \( -path '*/lib' -o -path '*/lib64' -o -path '*/usr/lib' -o -path '*/usr/lib64' \) | paste -sd: -)
if [ -z "$LIBPATH" ]; then
  echo "Could not find library directories in $INSTALL_DIR" >&2
  exit 1
fi

cat > "$HOME/.vscode-server-env.sh" <<ENV
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="$LINKER"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="$LIBPATH"
export VSCODE_SERVER_PATCHELF_PATH="$HOME/.local/bin/patchelf"
ENV

if ! grep -q 'vscode-server-env.sh' "$HOME/.bashrc" 2>/dev/null; then
  echo 'source ~/.vscode-server-env.sh' >> "$HOME/.bashrc"
fi

cat <<MSG
Installed sysroot to: $INSTALL_DIR
Dynamic linker: $LINKER
Library path: $LIBPATH
Patchelf: $HOME/.local/bin/patchelf
Env file: $HOME/.vscode-server-env.sh
MSG