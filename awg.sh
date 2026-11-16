#!/bin/bash
# AmneziaWG without the GUI: kernel module + awg-quick + dinit service.
#   fix awg /path/to/exported.conf
set -euo pipefail
CONF=${1:-}
TMP_CONF=
cleanup() { [ -z "$TMP_CONF" ] || rm -f -- "$TMP_CONF"; }
trap cleanup EXIT
if [ -z "$CONF" ] || [ ! -f "$CONF" ]; then
	echo "usage: fix awg /path/to/config.conf   (or an Amnezia .backup file)"
	echo "Export it in the Amnezia app: server -> Share -> AmneziaWG format (.conf)."
	exit 1
fi
# An Amnezia app backup (JSON) instead of a .conf: pull the AmneziaWG config out
if grep -q '"containers"' "$CONF" 2>/dev/null || ! grep -q '^\[Interface\]' "$CONF"; then
	echo "==> reading AmneziaWG config from the Amnezia backup"
	out=$(mktemp)
	TMP_CONF=$out
	python3 - "$CONF" "$out" <<'PY' || { echo "No AmneziaWG config found in this backup."; exit 1; }
import json, sys
data = json.load(open(sys.argv[1]))
found = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "last_config" and isinstance(v, str):
                try:
                    c = json.loads(v).get("config", "")
                except Exception:
                    c = ""
                if "[Interface]" in c:
                    found.append(c)
            else:
                walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
    elif isinstance(o, str) and o.lstrip()[:1] in ("{", "["):
        try:
            walk(json.loads(o))
        except Exception:
            pass
walk(data)
if not found:
    sys.exit(1)
if len(found) > 1:
    print(f"{len(found)} configs found, using the first one", file=sys.stderr)
open(sys.argv[2], "w").write(found[0].strip() + "\n")
PY
	CONF=$out
fi

echo "==> installing amneziawg (kernel module via dkms), tools, openresolv"
doas pacman -S --needed --noconfirm openresolv linux-zen-headers dkms >/dev/null
for i in 1 2 3; do paru -S --needed --noconfirm --skipreview amneziawg-dkms amneziawg-tools && break; echo "retry $i/3"; sleep 3; done
pacman -Q amneziawg-dkms amneziawg-tools >/dev/null 2>&1 || {
	echo "AmneziaWG packages failed to install; check paru output and matching kernel headers." >&2
	exit 1
}
doas modprobe amneziawg

echo "==> config -> /etc/amnezia/amneziawg/awg0.conf"
doas install -Dm600 "$CONF" /etc/amnezia/amneziawg/awg0.conf
# keep NAT mappings alive (prevents the tunnel going quiet behind the router)
doas grep -q '^PersistentKeepalive' /etc/amnezia/amneziawg/awg0.conf ||
	doas sed -i '/^\[Peer\]/a PersistentKeepalive = 25' /etc/amnezia/amneziawg/awg0.conf

R="https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}"
curl -fsSL "$R/dinit/amneziawg-module" | doas tee /etc/dinit.d/amneziawg-module >/dev/null
curl -fsSL "$R/dinit/awg" | doas tee /etc/dinit.d/awg >/dev/null
doas ln -sf /etc/dinit.d/amneziawg-module /etc/dinit.d/boot.d/amneziawg-module
doas ln -sf /etc/dinit.d/awg /etc/dinit.d/boot.d/awg
# refresh DNS after the tunnel profile's resolver settings are installed
doas resolvconf -u 2>/dev/null || true

echo "==> boot service with network wait/retry and tunnel recovery"
curl -fsSL "$R/bin/awg-watch" | doas tee /usr/local/bin/awg-watch >/dev/null
doas chmod +x /usr/local/bin/awg-watch
doas dinitctl restart awg 2>/dev/null || doas dinitctl start awg

sleep 2
doas awg show awg0 | head -8
echo "==> speed through the tunnel:"
curl -s -o /dev/null --max-time 12 -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=20000000' |
	awk '{printf "    %.1f MB/s\n", $1/1048576}'
cat <<'MSG'
Done. The AmneziaWG tunnel is managed by dinit and retries while the network comes up.
  off:  doas dinitctl stop awg      on:  doas dinitctl start awg
MSG
