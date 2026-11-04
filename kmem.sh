#!/bin/bash
# fix kmem: what the kernel itself holds in RAM (made for a photo).
m() { awk -v k="$1:" '$1==k{print int($2/1024)}' /proc/meminfo; }
echo "== used $(mem | cut -d' ' -f2-)  anon $(m AnonPages)M  slab-unrecl $(m SUnreclaim)M  vmalloc $(m VmallocUsed)M  percpu $(m Percpu)M"
echo "== top slab caches (MiB):"
doas awk 'NR>2{printf "%7.1f %s\n",$3*$4/1048576,$1}' /proc/slabinfo | sort -rn | head -8 | paste - -
echo "== top vmalloc callers (MiB):"
doas awk '/ioremap/{next}{for(i=3;i<=NF;i++)if($i~/\+0x/){sub(/\+.*/,"",$i);s[$i]+=$2;break}}
END{for(k in s)printf "%7.1f %s\n",s[k]/1048576,k}' /proc/vmallocinfo | sort -rn | head -6 | paste - -
echo "== why elogind is installed:"
pacman -Qi elogind 2>/dev/null | grep -E '^(Required By|Install Reason)' | cut -c1-110
