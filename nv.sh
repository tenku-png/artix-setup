#!/bin/bash
# Make the NVIDIA module work on the running kernel.   fix nv
K=$(uname -r)
echo "==> kernel $K"
ls /usr/lib/modules/"$K"/updates/dkms/ 2>/dev/null | sed 's/^/  /'
doas depmod -a "$K"
if doas modprobe nvidia_drm 2>/tmp/nv.err; then
	echo "==> NVIDIA loaded. Rebooting in 5 s (Ctrl+C to stay)."
	sleep 5 && doas reboot
else
	echo "==> still failing:"; cat /tmp/nv.err
	echo "==> rebuilding with dkms"
	doas dkms remove nvidia/"$(dkms status nvidia | head -1 | cut -d/ -f2 | cut -d, -f1)" -k "$K" >/dev/null 2>&1
	doas dkms autoinstall -k "$K" 2>&1 | tail -8
	doas depmod -a "$K"
	doas modprobe nvidia_drm && { echo "==> loaded now. Rebooting in 5 s."; sleep 5; doas reboot; } ||
		{ echo "==> photo this screen"; doas dmesg | grep -iE 'nvidia|symbol' | tail -8; }
fi
