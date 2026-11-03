#!/bin/bash
# AmneziaWG without the GUI: kernel module + awg-quick + dinit service.
#   fix awg /path/to/exported.conf
set -e
CONF=${1:-}
if [ -z "$CONF" ] || [ ! -f "$CONF" ]; then
	echo "usage: fix awg /path/to/config.conf"
	echo "Export it in the Amnezia app: server -> Share -> AmneziaWG format (.conf)."
	exit 1
fi
echo "==> installing amneziawg (kernel module via dkms), tools, openresolv"
doas pacman -S --needed --noconfirm openresolv linux-zen-headers dkms >/dev/null
for i in 1 2 3; do paru -S --needed --noconfirm --skipreview amneziawg-dkms amneziawg-tools && break; echo "retry $i/3"; sleep 3; done
doas modprobe amneziawg

echo "==> config -> /etc/amnezia/amneziawg/awg0.conf"
doas install -Dm600 "$CONF" /etc/amnezia/amneziawg/awg0.conf

echo "==> stop the Amnezia GUI service (no longer needed)"
doas dinitctl stop amneziavpn >/dev/null 2>&1 || true
doas rm -f /etc/dinit.d/boot.d/amneziavpn

printf '%s\n' '# AmneziaWG tunnel awg0. /etc/dinit.d/awg' 'type         = scripted' \
	'command      = /usr/bin/awg-quick up awg0' 'stop-command = /usr/bin/awg-quick down awg0' \
	'depends-on   = network.target' | doas tee /etc/dinit.d/awg >/dev/null
doas ln -sf /etc/dinit.d/awg /etc/dinit.d/boot.d/awg
doas dinitctl restart awg 2>/dev/null || doas dinitctl start awg

sleep 2
doas awg show awg0 | head -8
echo "==> speed through the tunnel:"
curl -s -o /dev/null --max-time 12 -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=20000000' |
	awk '{printf "    %.1f MB/s\n", $1/1048576}'
cat <<'MSG'
Done. The VPN now starts at boot by itself (no app, no background process).
  off:  doas dinitctl stop awg      on:  doas dinitctl start awg
MSG
