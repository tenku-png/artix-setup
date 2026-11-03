#!/bin/bash
# Why does the NVIDIA module not load on this kernel?   fix nvdiag
K=$(uname -r); D=/usr/lib/modules/$K
echo "== kernel: $K   modules dir: $(ls -d "$D" 2>/dev/null || echo MISSING)"
echo "== nvidia files:"
find "$D" -name 'nvidia*' 2>/dev/null | sed 's/^/  /'
echo "== in modules.dep: $(grep -c nvidia "$D/modules.dep" 2>/dev/null)"
echo "== depmod search: $(cat /usr/lib/depmod.d/*.conf /etc/depmod.d/*.conf 2>/dev/null | grep -v '^#' | tr '\n' ' ')"
echo "== module compression in this kernel: $(grep -E '^CONFIG_MODULE_(COMPRESS|DECOMPRESS)' /proc/config.gz 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep -E '^CONFIG_MODULE_(COMPRESS_[A-Z]+|DECOMPRESS)=' | tr '\n' ' ')"
f=$(find "$D" -name 'nvidia.ko*' | head -1)
if [ -n "$f" ]; then
	echo "== modinfo vermagic: $(modinfo -F vermagic "$f" 2>&1)"
	echo "== trying insmod $f"
	doas insmod "$f" 2>&1 | sed 's/^/  /'
	doas dmesg | grep -iE 'nvidia|symbol|module' | tail -8 | sed 's/^/  /'
fi
