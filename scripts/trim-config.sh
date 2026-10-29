#!/bin/sh
# Trim a Proxmox kernel config down to what a headless LXC/KVM host needs, so a
# rebuild takes minutes instead of hours.
#
#   CONFIG=/boot/config-7.0.14-19-pve ./scripts/trim-config.sh linux-7.0.14
#
# What goes and why:
#   - DRM/GPU drivers: the box is headless (i915 is blacklisted on the host) and
#     the P100s are driven by the nvidia module, not by DRM.
#   - SOUND and MEDIA/DVB: no audio, no tuners.
#   - WLAN/BT/HAMRADIO/ISDN/INFINIBAND/ATM/FDDI: no such hardware.
#   - every NIC vendor except Realtek (a single RTL8111).
#   - SCSI_LOWLEVEL: SATA only, no RAID/HBA cards.
#   - filesystems the host does not mount (OCFS2, GFS2, ReiserFS, JFS, F2FS,
#     NILFS2, ZONEFS, AFS, 9P, OrangeFS, Ceph, CIFS, UDF, HPFS, ROMFS).
#   - XEN/HYPERV/VMWARE_GUEST: this is the hypervisor, not a guest.
#   - DEBUG_INFO: DWARF + BTF is the single biggest cost of a kernel build and
#     buys nothing on a box nobody kdumps.
#
# What must stay (checked afterwards): MD/DM (LVM thin root), SATA_AHCI, SCSI,
# BLK_DEV_SD, EXT4, VT/VGA_CONSOLE, SERIAL_8250, BRIDGE, NETFILTER/NF_TABLES,
# OVERLAY_FS, FUSE, MEMCG/CGROUP_PIDS, APPARMOR, KVM/KVM_INTEL, VIRTIO, R8169.
#
# Do NOT use `make localmodconfig` here: it disables MD (dm-mod is built-in, so
# it is not in lsmod) and the machine no longer boots.
set -eu

TREE=${1:?usage: trim-config.sh <kernel tree>}
CONFIG=${CONFIG:-/boot/config-$(uname -r)}

cd "$TREE"
[ -f .config ] || cp "$CONFIG" .config
C=./scripts/config

for s in DRM AGP; do $C -d $s 2>/dev/null || true; done
for s in SOUND MEDIA_SUPPORT MEDIA_SUBDRV_AUTOSELECT DVB_CORE WLAN BT HAMRADIO \
         ISDN INFINIBAND ATM FDDI HIPPI NET_FC; do $C -d $s 2>/dev/null || true; done

for s in $(grep -oE '^CONFIG_NET_VENDOR_[A-Z0-9_]+' .config | sed 's/^CONFIG_//'); do
    [ "$s" = NET_VENDOR_REALTEK ] && continue
    $C -d "$s" 2>/dev/null || true
done

$C -d SCSI_LOWLEVEL 2>/dev/null || true

for s in OCFS2_FS GFS2_FS REISERFS_FS JFS_FS F2FS_FS NILFS2_FS ZONEFS_FS AFS_FS \
         9P_FS ORANGEFS_FS CEPH_FS CIFS UDF_FS HPFS_FS ROMFS_FS; do $C -d $s 2>/dev/null || true; done

for s in XEN HYPERV VMWARE_GUEST WATCHDOG; do $C -d $s 2>/dev/null || true; done

$C -e DEBUG_INFO_NONE -d DEBUG_INFO_DWARF5 -d DEBUG_INFO_BTF -d DEBUG_INFO_BTF_MODULES 2>/dev/null || true

make olddefconfig

echo "== $TREE: $(grep -c '^CONFIG_' .config) options, $(grep -c '=m$' .config) modules"
for s in MD BLK_DEV_DM EXT4_FS BRIDGE NETFILTER MEMCG CGROUP_PIDS SECURITY_APPARMOR VT; do
    printf '  %-20s %s\n' "$s" "$(grep -E "^CONFIG_$s=" .config | cut -d= -f2)"
done
