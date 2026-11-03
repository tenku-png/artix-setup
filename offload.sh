#!/bin/bash
# Find whether NIC/tunnel offloads break VPN downloads.   fix offload
set -u
speed() { curl -s -o /dev/null --max-time 12 -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=20000000' | awk '{printf "%.1f MB/s", $1/1048576}'; }
ip link show amn0 >/dev/null 2>&1 || { echo "Connect the VPN first (amn0 is not up)."; exit 1; }
command -v ethtool >/dev/null || doas pacman -S --needed --noconfirm ethtool >/dev/null
ETH=$(ip route show default | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' | grep -v amn0 | head -1)
ETH=${ETH:-eth0}

echo "1) as is:                          $(speed)"
doas ethtool -K amn0 tso off gso off gro off sg off tx off >/dev/null 2>&1
echo "2) amn0 offloads off:              $(speed)"
doas ethtool -K "$ETH" tso off gso off gro off >/dev/null 2>&1
echo "3) + $ETH offloads off:            $(speed)"
doas ip link set amn0 mtu 1280
echo "4) + amn0 MTU 1280:                $(speed)"
echo
echo "Photo this. The first line that is not 0.0 shows the fix."
echo "(Everything goes back to normal after reconnecting the VPN / rebooting.)"
