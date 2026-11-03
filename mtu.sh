#!/bin/bash
# Lower the AmneziaWG tunnel MTU (pages/videos that never finish loading).
#   fix mtu [value]   default 1280
V=${1:-1280}
C=/etc/amnezia/amneziawg/awg0.conf
doas test -f "$C" || { echo "no $C"; exit 1; }
if doas grep -q '^MTU' "$C"; then
	doas sed -i "s/^MTU.*/MTU = $V/" "$C"
else
	doas sed -i "/^\[Interface\]/a MTU = $V" "$C"
fi
echo "==> MTU = $V in $C"
doas dinitctl status vpn-mss 2>/dev/null | grep -i -E 'state|fail' | sed 's/^/    vpn-mss: /'
doas dinitctl restart awg >/dev/null 2>&1 || { doas awg-quick down awg0; doas awg-quick up awg0; }
sleep 2
curl -s -o /dev/null --max-time 12 -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=20000000' |
	awk '{printf "==> speed through the tunnel: %.1f MB/s\n", $1/1048576}'
