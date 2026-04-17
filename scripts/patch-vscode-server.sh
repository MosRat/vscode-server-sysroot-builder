#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${HOME}/.vscode-server-env.sh"
SERVER_ROOTS=(
  "${HOME}/.vscode-server"
  "${HOME}/.vscode-server-insiders"
  "${HOME}/.cursor-server"
)

info()  { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*"; }
ok()    { printf '[ OK ] %s\n' "$*"; }
err()   { printf '[ERR ] %s\n' "$*" >&2; }

if [ ! -f "$ENV_FILE" ]; then
  err "Missing ${ENV_FILE}. Run install-remote.sh first."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${VSCODE_SERVER_CUSTOM_GLIBC_LINKER:?missing}"
: "${VSCODE_SERVER_CUSTOM_GLIBC_PATH:?missing}"
: "${VSCODE_SERVER_PATCHELF_PATH:?missing}"

if [ ! -x "$VSCODE_SERVER_PATCHELF_PATH" ]; then
  err "patchelf not executable: $VSCODE_SERVER_PATCHELF_PATH"
  exit 1
fi

patch_one() {
  local f="$1"

  if ! file "$f" | grep -q 'ELF .* dynamically linked'; then
    return 0
  fi

  info "Patching $f"
  "$VSCODE_SERVER_PATCHELF_PATH" \
    --set-interpreter "$VSCODE_SERVER_CUSTOM_GLIBC_LINKER" \
    --set-rpath "$VSCODE_SERVER_CUSTOM_GLIBC_PATH" \
    "$f"
}

patched=0
for root in "${SERVER_ROOTS[@]}"; do
  [ -d "$root" ] || continue
  info "Scanning $root"

  while IFS= read -r -d '' f; do
    patch_one "$f"
    patched=$((patched + 1))
  done < <(find "$root" -type f -perm -0100 -print0 2>/dev/null)
done

ok "Patch completed, processed ${patched} executable candidates"