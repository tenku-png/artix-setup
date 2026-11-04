#!/bin/bash
# fix pcp: free pages parked in per-CPU lists are shown as "used".
# 16 CPU threads x big lists = tens of MiB. Shrink the lists and keep it.
pcp() { awk '$1=="count:"{s+=$2}END{print int(s*4/1024)}' /proc/zoneinfo; }
echo "before: $(mem)   per-CPU lists: $(pcp) MiB"
doas sysctl -q vm.percpu_pagelist_high_fraction=100000
sleep 1
echo "after:  $(mem)   per-CPU lists: $(pcp) MiB"
echo 'vm.percpu_pagelist_high_fraction = 100000' | doas tee /etc/sysctl.d/90-pcp.conf >/dev/null
echo "==> kept in /etc/sysctl.d/90-pcp.conf (undo: doas rm it)"
