#!/bin/bash
# Load the AmneziaWG kernel module on the running kernel and restart the VPN.   fix awgmod
K=$(uname -r)
echo "==> kernel $K"
doas depmod -a "$K"
if ! doas modprobe amneziawg 2>/tmp/awg.err; then
	echo "==> modprobe failed: $(cat /tmp/awg.err)"
	echo "==> rebuilding amneziawg with dkms"
	doas dkms autoinstall -k "$K" 2>&1 | tail -4
	doas depmod -a "$K"
	doas modprobe amneziawg || { echo "==> still failing:"; doas dmesg | grep -iE 'amneziawg|symbol' | tail -6; exit 1; }
fi
echo "==> amneziawg loaded"
# load it at every boot, before the tunnel starts
echo amneziawg | doas tee /etc/modules-load.d/amneziawg.conf >/dev/null
doas dinitctl restart awg >/dev/null 2>&1 || doas dinitctl start awg
sleep 3
doas awg show awg0 | grep -E 'endpoint|handshake|transfer' | sed 's/^/    /'
echo "==> outside IP now: $(curl -s --max-time 8 https://ifconfig.me) (should be the VPN server)"
