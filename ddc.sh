#!/bin/bash
# fix ddc: let the bar change desktop monitor brightness (DDC/CI, ddcutil).
set -u
doas modprobe i2c-dev || echo "!! no i2c-dev module in this kernel"
echo i2c-dev | doas tee /etc/modules-load.d/i2c-dev.conf >/dev/null
getent group i2c >/dev/null || doas groupadd -r i2c
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | doas tee /etc/udev/rules.d/60-i2c.rules >/dev/null
doas udevadm control --reload; doas udevadm trigger --subsystem-match=i2c-dev
doas usermod -aG i2c "$USER"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}/bin/bri" -o /tmp/bri &&
	doas install -m755 /tmp/bri /usr/local/bin/bri
rm -f "${XDG_RUNTIME_DIR:-/tmp}/bri.displays"
echo "== monitors with DDC/CI:"
if doas ddcutil detect --brief 2>&1 | grep -E '^Display|connector'; then
	echo "==> ok. Reboot (new group), then scroll on the bar brightness."
else
	echo "!! no monitor answered: enable DDC/CI in the monitor menu (OSD) and send a photo"
fi
