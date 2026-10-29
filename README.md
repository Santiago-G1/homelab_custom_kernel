# Custom Linux kernel for two 16 GiB GPUs on a 36-bit platform

Three small PCI changes on top of `6.14.11` that let **two Tesla P100 (16 GiB
BAR1 each) initialize at the same time** on an Ivy Bridge class machine with a
**36-bit physical address space** — the case where a stock kernel can only ever
place one of them.

Tested on: Intel H61M-I + i5-3570, 16 GB DDR3, 2× Tesla P100-PCIE-16GB, Proxmox
VE 9.2.

## The problem

A P100 exposes a 16 GiB prefetchable BAR1 (its framebuffer) plus a 32 MiB
prefetchable BAR3. Three things have to be true at once for two of them to fit
in 64 GiB (36 bits):

1. **The bridge window must be exactly 16 GiB.** Linux sizes a window as
   `max(size, align)` of everything behind it, so "16 GiB BAR + 32 MiB BAR"
   becomes a 16 GiB + 32 MiB window, which can no longer be aligned to 16 GiB
   and therefore cannot tile with a second one.
2. **Nothing may sit where a 16 GiB window has to go.** With the windows aligned
   to 16 GiB, the only two slots below 64 GiB are at 32 GiB and 48 GiB. Firmware
   parks the HDA audio and SMBus BARs right there, and leaves a useless 1 MiB
   prefetchable window behind the NIC port at 32.5 GiB.
3. Once those two are true, the generic allocator finds `[32 GiB, 48 GiB)` and
   `[48 GiB, 64 GiB)` bottom-up on its own.

## The changes

| patch | file | what it does |
|---|---|---|
| `0001` | `drivers/pci/probe.c` | `pci_demote_small_pref_bars()`: next to a BAR ≥ 8 GiB, mark prefetchable BARs < 1 GiB non-prefetchable (and a lone prefetchable BAR < 64 KiB too) |
| `0002` | `drivers/pci/setup-bus.c` | `pci_drop_unused_pref_window()`: release a prefetchable window when nothing behind the bridge is prefetchable |
| `0003` | `drivers/pci/setup-bus.c` | `pci_evict_small_mem()`: before the generic assignment, release memory BARs < 8 GiB that overlap `[16 GiB, 64 GiB)`; they are reassigned a few lines later, before any driver binds |

Each patch carries the reasoning in its commit message. `git am` them if you
keep a git checkout of the kernel; `patch -p1` works too.

## Result

```
$ grep -E "PCI Bus 0000:0[12]" /proc/iomem
800000000-bffffffff : PCI Bus 0000:01      # 32-48 GiB  (CPU PEG port, Gen3 x16)
c00000000-fffffffff : PCI Bus 0000:02      # 48-64 GiB  (chipset port, Gen2 x4)

$ nvidia-smi --query-gpu=index,pci.bus_id,pcie.link.gen.current,pcie.link.width.current,memory.total --format=csv
index, pci.bus_id, pcie.link.gen.current, pcie.link.width.current, memory.total [MiB]
0, 00000000:01:00.0, 3, 16, 16384 MiB
1, 00000000:02:00.0, 2, 4, 16384 MiB
```

It survives reboots, and it does not depend on how much RAM is installed: the
windows live at 32 and 48 GiB, far above the top of DRAM (tested with 8 and 16
GB). No `mem=` limit, no boot-time script, no module.

Kernel command line used here: `pcie_aspm=off pci=nocrs`. `pci=nocrs` predates
this work and is kept for the rest of the board; dropping it makes the firmware
windows come back as `[disabled]`.

## Build

```sh
./scripts/build.sh                    # KVER=6.14.11 CONFIG=/boot/config-$(uname -r) JOBS=2
```

It fetches the tarball from kernel.org, applies `patches/*` in order, uses your
running config as the base and runs `make olddefconfig`. Requirements are the
usual kernel toolchain: `gcc make bc bison flex libssl-dev libelf-dev cpio
zstd`. On a 16 GB machine build with `-j2`; the linker step is the memory
hungry one.

## Install

```sh
./scripts/install-kernel.sh           # run inside linux-$KVER/
```

`modules_install` with `INSTALL_MOD_STRIP=1`, `bzImage`/`System.map`/`.config`
into `/boot`, `depmod`, `update-initramfs -c`, `update-grub`.

Watch out for GRUB on Proxmox: `feature_menuentry_id` is not defined there, so
**`menuentry --id` is ignored** and any `GRUB_DEFAULT` by id silently falls back
to the first entry. Pin the kernel with a first entry generated from
`/etc/grub.d/01_...` and `GRUB_DEFAULT="0"`.

## Porting to another kernel version

The patches touch three functions (`pci_read_bases()`,
`__pci_bus_size_bridges()` / `pci_bus_size_bridges()` and
`pci_assign_unassigned_root_bus_resources()`), so they should keep applying with
at most a line of fuzz. Check the two constants that encode this platform's
geometry:

* `SZ_8G` / `SZ_1G` in `pci_demote_small_pref_bars()` — what counts as a huge
  BAR and what counts as a small sibling.
* `PCI_36BIT_LIMIT` (`4 * SZ_16G`) and the start of the eviction slot
  (`SZ_16G`) — where the platform's physical address space ends and where the
  first huge window can begin. Platforms with 39+ bits do not need change 3 at
  all.

## Notes for Proxmox

* **nvidia**: rebuild DKMS against the new kernel. If the module reports
  `Exec format error`, the `.config` used by DKMS did not match the running
  kernel: copy `/boot/config-$K` into the tree and run `make modules_prepare`.
* **ZFS**: this kernel has no in-tree ZFS. Proxmox ties `zfs.ko` to its own
  `-pve` kernel, so build OpenZFS (`2.4.4` was needed here) against it, or keep
  the root filesystem off ZFS.
* **Do not compile on the hypervisor** if it is RAM constrained: build
  elsewhere, copy `bzImage` + `/lib/modules/$K`.

## Dead ends

`docs/what-does-not-work.md` lists the approaches that do not work on this
platform (boot parameters, `setpci`, custom modules, `mem=` tricks) — worth
reading before trying to solve it another way.

## License

GPL-2.0, same as the kernel this patches. The code is a derivative work of
`drivers/pci/probe.c` and `drivers/pci/setup-bus.c`.
