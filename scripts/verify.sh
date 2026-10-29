#!/bin/sh
# Print what the allocator did: the huge PCI windows and the GPUs behind them.
set -eu

echo "== kernel"
uname -r
cat /proc/cmdline

echo
echo "== PCI windows above 2 GiB"
grep -E "^[0-9a-f]+-[0-9a-f]+ : PCI Bus" /proc/iomem | while read -r range _rest; do
    start=${range%-*}
    end=${range#*-}
    [ $((0x$start)) -gt $((0x80000000)) ] || continue
    printf '%5d GiB - %5d GiB   %s\n' \
        $((0x$start / 1073741824)) $(((0x$end + 1) / 1073741824)) "${_rest#: }"
done

echo
echo "== GPUs"
nvidia-smi --query-gpu=index,pci.bus_id,pcie.link.gen.current,pcie.link.width.current,memory.total \
    --format=csv
