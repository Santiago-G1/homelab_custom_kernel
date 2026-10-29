#!/bin/sh
# Print what the allocator did: the PCI windows and the GPUs behind them.
set -eu

echo "== kernel"
uname -r
cat /proc/cmdline

echo
echo "== PCI windows above 2 GiB"
grep -E "^[0-9a-f]+-[0-9a-f]+ : PCI Bus" /proc/iomem | while read -r range _rest; do
    start=${range%-*}
    end=${range#*-}
    sp=$((0x$start))
    sz=$((0x$end - sp + 1))
    [ "$sz" -ge 16777216 ] || continue
    if [ "$sz" -ge 1073741824 ]; then
        printf '%5d GiB start, %4d GiB   %s\n' $((sp / 1073741824)) $((sz / 1073741824)) "${_rest#: }"
    else
        printf '%5d GiB start, %4d MiB   %s\n' $((sp / 1073741824)) $((sz / 1048576)) "${_rest#: }"
    fi
done

echo
echo "== GPUs"
nvidia-smi --query-gpu=index,pci.bus_id,pcie.link.gen.current,pcie.link.width.current,memory.total \
    --format=csv
