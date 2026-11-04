#!/bin/bash
# fix nvcost: how much RAM the NVIDIA driver holds. Run from "3) shell" (no compositor).
# The screen may go black for ~5 s while the driver is unloaded.
snap() { awk '{v[$1]=int($2/1024)} END{
	used=v["MemTotal:"]-v["MemFree:"]-v["Buffers:"]-v["Cached:"]-v["SReclaimable:"]
	known=v["AnonPages:"]+v["SUnreclaim:"]+v["VmallocUsed:"]+v["Percpu:"]+v["PageTables:"]+v["KernelStack:"]+v["SecPageTables:"]
	printf "used %d  hidden %d  (iommu-pt %d hugetlb %d kreclaim %d)", used, used-known, v["SecPageTables:"], v["Hugetlb:"], v["KReclaimable:"]-v["SReclaimable:"]}' /proc/meminfo; }
[ -n "${WAYLAND_DISPLAY:-}" ] && { echo "run this from the shell (start-wm menu: 3), not inside lilith"; exit 1; }
doas true || exit 1
B=$(snap)
doas modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/tmp/nvcost.err; ok=$?
sleep 2; A=$(snap)
doas modprobe nvidia_drm 2>/dev/null; doas modprobe nvidia_uvm 2>/dev/null
clear; echo "with nvidia:    $B"; echo "without nvidia: $A"
[ $ok -eq 0 ] || { echo "!! could not unload:"; cat /tmp/nvcost.err; }
