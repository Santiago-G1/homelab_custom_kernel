#!/bin/sh
# Install the kernel built by build.sh. Run from inside linux-$KVER/, or pass
# the tree as $1. On Proxmox, read the GRUB note in the README first.
set -eu

TREE=${1:-.}
cd "$TREE"

[ -f arch/x86/boot/bzImage ] || { echo "bzImage missing: build it first" >&2; exit 1; }

K=$(make -s kernelrelease)
echo "== installing $K"

make -j2 modules_install INSTALL_MOD_STRIP=1

cp arch/x86/boot/bzImage "/boot/vmlinuz-$K"
cp System.map "/boot/System.map-$K"
cp .config "/boot/config-$K"

depmod -a "$K"
update-initramfs -c -k "$K"
update-grub

ls -l "/boot/vmlinuz-$K" "/boot/initrd.img-$K"
