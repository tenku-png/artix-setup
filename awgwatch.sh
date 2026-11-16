#!/bin/bash
# Refresh the dinit-managed AmneziaWG retry/recovery service.   fix awgwatch
set -euo pipefail
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
curl -fsSL "$R/dinit/amneziawg-module" | doas tee /etc/dinit.d/amneziawg-module >/dev/null
curl -fsSL "$R/dinit/awg" | doas tee /etc/dinit.d/awg >/dev/null
doas ln -sf /etc/dinit.d/amneziawg-module /etc/dinit.d/boot.d/amneziawg-module
doas ln -sf /etc/dinit.d/awg /etc/dinit.d/boot.d/awg
doas dinitctl restart awg 2>/dev/null || doas dinitctl start awg
echo "==> dinit now waits for a route, retries tunnel setup and checks peer handshakes"
