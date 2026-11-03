#!/bin/bash
# Diagnose (and fix the common case of) a missing NVIDIA driver.
#   curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/gpu-check.sh | bash
set -u
b=$'\e[1m'; r=$'\e[31m'; g=$'\e[32m'; z=$'\e[0m'

echo "${b}== kernel:${z} $(uname -r)"
echo "${b}== DRM devices (driver per card):${z}"
for c in /sys/class/drm/card[0-9]; do
	[ -e "$c/device/driver" ] && echo "  $(basename "$c"): $(basename "$(readlink "$c/device/driver")")"
done
ls /dev/dri/ 2>/dev/null | sed 's/^/  \/dev\/dri\//'

echo "${b}== NVIDIA modules:${z}"
if lsmod | grep -q '^nvidia_drm '; then
	echo "  ${g}nvidia_drm loaded${z}, modeset=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)"
	NV=ok
else
	echo "  ${r}nvidia is NOT loaded${z}"
	NV=missing
fi
echo "${b}== dkms:${z}"
dkms status 2>/dev/null | sed 's/^/  /' || echo "  dkms not found"

echo "${b}== running compositor:${z}"
for p in $(pgrep -x lilith; pgrep -x sway); do
	echo "  $(cat /proc/$p/comm) pid $p, $(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -E '^WLR_RENDERER=' || echo 'WLR_RENDERER unset')"
done

if [ "$NV" = missing ]; then
	echo
	echo "${b}==> building the NVIDIA module for $(uname -r) (takes a few minutes)${z}"
	doas pacman -S --needed --noconfirm linux-zen-headers nvidia-open-dkms nvidia-utils
	doas dkms autoinstall -k "$(uname -r)"
	doas mkinitcpio -P >/dev/null
	if modinfo nvidia_drm >/dev/null 2>&1; then
		echo "${g}NVIDIA module is built. Reboot now: doas reboot${z}"
	else
		echo "${r}NVIDIA module still missing; send a photo of the output above.${z}"
	fi
fi
