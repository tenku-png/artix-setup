#!/bin/bash
# fix ddc: let the bar change desktop monitor brightness (DDC/CI, ddcutil).
# i2c-dev is NOT loaded at boot (DDC/CI while lilith starts froze the
# screen); bri loads it on the first brightness change via this doas rule.
set -u
doas rm -f /etc/modules-load.d/i2c-dev.conf
getent group i2c >/dev/null || doas groupadd -r i2c
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | doas tee /etc/udev/rules.d/60-i2c.rules >/dev/null
doas udevadm control --reload
doas usermod -aG i2c "$USER"
rule='permit nopass :wheel cmd modprobe args i2c-dev'
doas grep -qxF "$rule" /etc/doas.conf || echo "$rule" | doas tee -a /etc/doas.conf >/dev/null
curl -fsSL --retry 3 "https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}/bin/bri" -o /tmp/bri &&
	doas install -m755 /tmp/bri /usr/local/bin/bri
rm -f "${XDG_RUNTIME_DIR:-/tmp}"/bri.*
echo "==> done. In lilith scroll on the bar brightness (first time takes ~2 s)."
