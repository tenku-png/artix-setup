#!/bin/bash
# fix ramtop: one screen of "where does idle RAM go" (made for a photo).
m() { awk -v k="$1:" '$1==k{print int($2/1024)}' /proc/meminfo; }
echo "== used: $(mem 2>/dev/null | cut -d' ' -f2-)"
echo "kernel: slab-unrecl $(m SUnreclaim)M  stacks $(m KernelStack)M  pagetbl $(m PageTables)M  vmalloc $(m VmallocUsed)M"
echo "shmem(tmpfs/gpu) $(m Shmem)M  anon $(m AnonPages)M  zswap $(m Zswap 2>/dev/null)M"
echo "processes: $(ps -e --no-headers | wc -l) (kernel threads not counted below)"
echo "== top by RSS (MiB):"
ps -eo rss=,comm= --sort=-rss | awk '$1>0{n[$2]+=$1;c[$2]++}
END{for(p in n)printf "%6.1f %s%s\n",n[p]/1024,p,(c[p]>1?" x"c[p]:"")}' |
	sort -rn | head -18 | paste - -
echo "== sum of all RSS: $(ps -eo rss= | awk '{s+=$1}END{print int(s/1024)}')M"
lsmod | awk 'NR>1{s+=$2}END{printf "modules: %d, %d MiB code\n",NR-1,s/1048576}'
[ -r /proc/driver/nvidia/version ] && echo "nvidia: loaded"
dinitctl list 2>/dev/null | grep -cE '^\[.\+' | sed 's/^/dinit services up: /'
