#!/usr/bin/env bash
# Build EfiFs drivers for x64 on Linux, as upstream CI does.
#
# Three things upstream's CI does for you:
#   - apply 0001-GRUB-fixes.patch to the grub submodule;
#   - use the MinGW cross compiler throughout, since Make.common's x64 branch
#     targets a COFF DLL (an ELF libefi.a yields a PE the firmware rejects);
#   - build serially, as src/Makefile reuses this.o across drivers.
#
# usage: build-mingw.sh
set -euo pipefail
cd "$(dirname "$0")"

export PATH="${MINGW_PREFIX:-$HOME/.local/mingw}/bin:$PATH"
command -v x86_64-w64-mingw32-gcc >/dev/null || {
  echo "x86_64-w64-mingw32-gcc not on PATH (set MINGW_PREFIX)" >&2; exit 1; }

# 1. the GRUB patch
if ! git -C grub diff --quiet -- grub-core; then
  echo "grub submodule already patched"
else
  git -C grub apply ../0001-GRUB-fixes.patch && echo "applied 0001-GRUB-fixes.patch"
fi

# 2. clean, so no object survives from a different toolchain
find grub src -name '*.o' -delete 2>/dev/null || true
find grub src -name '*.d' -delete 2>/dev/null || true
rm -f grub/libgrub.a grub/config.h
rm -f src/*.efi
# gnu-efi/lib holds the library *sources* - only the per-arch build dir is output
rm -rf gnu-efi/x86_64
./set_grub_cpu.sh x64 >/dev/null

CROSS=x86_64-w64-mingw32-
# Serial on purpose: src/Makefile reuses this.o across drivers (it rm -s it per
# target), so a parallel build links the wrong filesystem into the image.
make CROSS_COMPILE=$CROSS ARCH=x64 >/tmp/efifs-build.log 2>&1 || {
  echo "build failed:"; tail -20 /tmp/efifs-build.log; exit 1; }

for f in src/*_x64.efi; do
  printf '%-12s %8d bytes  %s\n' "$(basename "$f")" "$(stat -c%s "$f")" \
    "$(file -b "$f" | cut -d, -f1-2)"
done