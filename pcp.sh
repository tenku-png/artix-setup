#!/bin/bash
# fix pcp: free pages parked in per-CPU lists are shown as "used".
# 16 CPU threads x big lists = tens of MiB. Shrink the lists and keep it.
pcp() { awk '$1=="count:"{s+=$2}END{print int(s*4/1024)}' /proc/zoneinfo; }
echo "before: $(mem)   per-CPU lists: $(pcp) MiB"
doas sysctl -q vm.percpu_pagelist_high_fraction=100000
sleep 1
echo "after:  $(mem)   per-CPU lists: $(pcp) MiB"
doas mkdir -p /etc/sysctl.d
echo 'vm.percpu_pagelist_high_fraction = 100000' | doas tee /etc/sysctl.d/90-pcp.conf >/dev/null
echo "==> kept in /etc/sysctl.d/90-pcp.conf (undo: doas rm it)"
grep -rqs sysctl /usr/lib/dinit.d /etc/dinit.d /usr/lib/dinit 2>/dev/null &&
	echo "==> dinit applies sysctl.d at boot" || echo "!! no sysctl step found in dinit: tell Claude"
