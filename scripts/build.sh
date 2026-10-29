#!/bin/sh
# Fetch, patch and build the kernel with the two-huge-GPU PCI changes.
#
#   KVER=6.14.11        kernel version to build
#   CONFIG=/boot/config-$(uname -r)   base config (default: the running one)
#   JOBS=2              parallel jobs (linker is memory hungry)
#
# Run from the repository root: ./scripts/build.sh
set -eu

KVER=${KVER:-6.14.11}
CONFIG=${CONFIG:-/boot/config-$(uname -r)}
JOBS=${JOBS:-2}
TARBALL=linux-$KVER.tar.xz

cd "$(dirname "$0")/.."

[ -f "$TARBALL" ] || curl -# -L -o "$TARBALL" \
    "https://cdn.kernel.org/pub/linux/kernel/v6.x/$TARBALL"
[ -d "linux-$KVER" ] || tar xf "$TARBALL"

cd "linux-$KVER"

if [ ! -f .config ]; then
    [ -f "$CONFIG" ] || { echo "no config at $CONFIG, pass CONFIG=..." >&2; exit 1; }
    cp "$CONFIG" .config
fi

for p in ../patches/*.patch; do
    echo "== $(basename "$p")"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git am -q "$p"
    else
        patch -p1 --batch --forward --dry-run <"$p" >/dev/null
        patch -p1 --batch --forward <"$p"
    fi
done

make olddefconfig
make -j"$JOBS"
ls -l arch/x86/boot/bzImage
