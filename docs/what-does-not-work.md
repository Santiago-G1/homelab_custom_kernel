# What does not work on this platform

Everything here was tried on the H61M-I + i5-3570 + 2× P100 machine before the
kernel patches, and it failed. Kept so nobody pays for it twice.

## Boot parameters and sysfs knobs

| attempt | outcome |
|---|---|
| `pci=resource_alignment=...@<order>` | only affects BARs of devices; it cannot shrink a BAR, so the window stays 16 GiB + 32 MiB |
| `pci=realloc`, `pci=realloc=on` | the allocator still cannot tile two 16 GiB + 32 MiB windows |
| removing `pci=nocrs` | with ACPI `_CRS` both GPU windows come back `[disabled]` |
| `mem=8G`, `mem=15G`, pulling RAM sticks | does free slots (that is how the first success happened), but it is fragile, costs RAM and is not needed once the windows are exactly 16 GiB |
| forcing the link to Gen2 | the link is not the problem (and the chipset port negotiates Gen2 x4 on its own) |
| `module_blacklist=` | also blocks manual `modprobe`, so it cannot be used to test one card at a time |
| `setpci` on bridge windows + BARs before the driver loads | writes land, but the kernel resource tree and the hardware disagree, and the next enumeration undoes it |
| moving the NIC BAR by sysfs | always breaks `vmbr0`; recovery needs a physical console. Same for audio/SMBus, which is why the eviction happens in the kernel instead |

## Custom modules

* Writing windows and BARs into config space **and** into `dev->resource[]`
  (with `bus->resource[2]`, `insert_resource()`, flags `0x14220c` so
  `IORESOURCE_MEM_64` stays set) works on paper, but `pci_claim_resource()`
  returns `-22` because the kernel's own parent hierarchy is not what the module
  planted, and the device then fails `pci_enable_device()`.
* Inserting the bridge window with `insert_resource_conflict()` from a module
  trips `WARNING at kernel/resource.c: __insert_resource (duplicated insertion)`.

Conclusion: the decision has to be made while the kernel enumerates, which is
what the patches do. A module (or a firmware DXE driver) is the wrong layer.

## Other kernels and drivers

| attempt | outcome |
|---|---|
| `min_align` clamp to 32 MiB in `__pci_bus_size_bridges()` | counterproductive: the window stops being 16 GiB aligned and the BAR never fits |
| driver 570 / 580 | same `RmInitAdapter failed! (0x24:0x72:1603)` = `NV_ERR_MEMORY_ERROR` while the BAR was unplaced; the driver was never the problem |
| `NVreg_EnableMSI=0`, AER bit clearing, FLR, `pcie_bus_safe`, IOMMU off | no effect |
