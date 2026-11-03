#!/bin/bash
# Add keepalive + watchdog to an existing AmneziaWG setup.   fix awgwatch
set -e
R="https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}"
C=/etc/amnezia/amneziawg/awg0.conf
doas test -f "$C" || { echo "no $C, run: fix awg FILE"; exit 1; }
if ! doas grep -q '^PersistentKeepalive' "$C"; then
	doas sed -i '/^\[Peer\]/a PersistentKeepalive = 25' "$C"
	doas awg set awg0 peer "$(doas awg show awg0 peers | head -1)" persistent-keepalive 25 2>/dev/null || true
	echo "==> PersistentKeepalive = 25 added"
fi
curl -fsSL "$R/bin/awg-watch" | doas tee /usr/local/bin/awg-watch >/dev/null
doas chmod +x /usr/local/bin/awg-watch
curl -fsSL "$R/dinit/awg-watch" | doas tee /etc/dinit.d/awg-watch >/dev/null
doas ln -sf /etc/dinit.d/awg-watch /etc/dinit.d/boot.d/awg-watch
doas dinitctl start awg-watch
echo "==> watchdog running; the tunnel is checked every 30 s"
