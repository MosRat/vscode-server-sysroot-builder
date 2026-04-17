#!/usr/bin/env bash
set -euo pipefail

mkdir -p /work/src /work/build /work/tarballs /out
cd /work/src

wget -q -O .config "$MS_CONFIG_URL"

if grep -q '^CT_LOCAL_TARBALLS_DIR=' .config; then
  sed -i "s#^CT_LOCAL_TARBALLS_DIR=.*#CT_LOCAL_TARBALLS_DIR=\"${CT_TARBALLS_DIR}\"#" .config
else
  printf '\nCT_LOCAL_TARBALLS_DIR="%s"\n' "$CT_TARBALLS_DIR" >> .config
fi

ct-ng build

SYSROOT=""
for base in /work/build "$HOME/x-tools"; do
  if [ -d "$base" ]; then
    hit=$(find "$base" -type d -name sysroot 2>/dev/null | head -n1 || true)
    if [ -n "$hit" ]; then
      SYSROOT="$hit"
      break
    fi
  fi
done

if [ -z "$SYSROOT" ]; then
  echo "sysroot not found after ct-ng build" >&2
  exit 1
fi

TARBALL=/out/vscode-sysroot-x86_64-glibc228.tgz
tar -C "$SYSROOT" -czf "$TARBALL" .
sha256sum "$TARBALL" | tee /out/vscode-sysroot-x86_64-glibc228.tgz.sha256

echo "Built: $TARBALL"