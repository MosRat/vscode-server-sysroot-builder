#!/usr/bin/env bash
set -euo pipefail

mkdir -p /work/src /work/build /work/tarballs /work/x-tools /out
cd /work/src

wget -q -O .config "$MS_CONFIG_URL"

if grep -q '^CT_PREFIX_DIR=' .config; then
  sed -i 's#^CT_PREFIX_DIR=.*#CT_PREFIX_DIR="${CT_TOP_DIR}/x-tools/${CT_TARGET}"#' .config
else
  printf 'CT_PREFIX_DIR="${CT_TOP_DIR}/x-tools/${CT_TARGET}"\n' >> .config
fi

if grep -q '^CT_LOCAL_TARBALLS_DIR=' .config; then
  sed -i "s#^CT_LOCAL_TARBALLS_DIR=.*#CT_LOCAL_TARBALLS_DIR=\"${CT_TARBALLS_DIR}\"#" .config
else
  printf 'CT_LOCAL_TARBALLS_DIR="%s"\n' "$CT_TARBALLS_DIR" >> .config
fi

if grep -q '^CT_SAVE_TARBALLS=' .config; then
  sed -i 's#^CT_SAVE_TARBALLS=.*#CT_SAVE_TARBALLS=y#' .config
else
  printf 'CT_SAVE_TARBALLS=y\n' >> .config
fi

if grep -q '^CT_LOG_PROGRESS_BAR=' .config; then
  sed -i 's#^CT_LOG_PROGRESS_BAR=.*#CT_LOG_PROGRESS_BAR=n#' .config
else
  printf 'CT_LOG_PROGRESS_BAR=n\n' >> .config
fi

sed -i \
  -e 's/^CT_LOG_ERROR=.*/# CT_LOG_ERROR is not set/' \
  -e 's/^CT_LOG_WARN=.*/# CT_LOG_WARN is not set/' \
  -e 's/^CT_LOG_INFO=.*/CT_LOG_INFO=y/' \
  -e 's/^CT_LOG_EXTRA=.*/# CT_LOG_EXTRA is not set/' \
  -e 's/^CT_LOG_ALL=.*/# CT_LOG_ALL is not set/' \
  -e 's/^CT_LOG_DEBUG=.*/# CT_LOG_DEBUG is not set/' \
  .config

ct-ng build

TARGET="$(ct-ng show-tuple | tail -n1 | tr -d '\r')"
if [ -z "$TARGET" ]; then
  echo "Could not determine target tuple from ct-ng show-tuple" >&2
  exit 1
fi

PREFIX_DIR="/work/src/x-tools/${TARGET}"
GCC="${PREFIX_DIR}/bin/${TARGET}-gcc"

if [ ! -x "$GCC" ]; then
  echo "Could not find ${TARGET}-gcc at expected path: $GCC" >&2
  find /work/src -maxdepth 4 -type f -name "${TARGET}-gcc" 2>/dev/null || true
  exit 1
fi

SYSROOT="$("$GCC" -print-sysroot | tr -d '\r')"
if [ -z "$SYSROOT" ] || [ ! -d "$SYSROOT" ]; then
  echo "Compiler reported invalid sysroot: $SYSROOT" >&2
  exit 1
fi

TARBALL=/out/vscode-sysroot-x86_64-glibc228.tgz
tar -C "$SYSROOT" -czf "$TARBALL" .
sha256sum "$TARBALL" | tee /out/vscode-sysroot-x86_64-glibc228.tgz.sha256

echo "TARGET=$TARGET"
echo "PREFIX_DIR=$PREFIX_DIR"
echo "GCC=$GCC"
echo "SYSROOT=$SYSROOT"
echo "Built: $TARBALL"