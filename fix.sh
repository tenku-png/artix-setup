#!/bin/bash
# Update the helper scripts from GitHub and show what uses memory.
#   curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/fix.sh | bash
set -u
REPO=https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}
tmp=$(mktemp -d)
echo "==> updating start-wm, session-apps, clip-pick, mic-monitor, mem, bri"
for f in start-wm session-apps clip-pick mic-monitor mem bri wall fix; do
	curl -fsSL --retry 3 "$REPO/bin/$f" -o "$tmp/$f" || { echo "download of $f failed"; exit 1; }
done
doas install -m755 "$tmp"/* /usr/local/bin/ && echo "==> installed to /usr/local/bin"
rm -rf "$tmp"

echo
echo "==> memory"
mem 2>/dev/null || free -m
echo
echo "==> biggest processes (RSS MiB)"
ps -eo rss,comm --sort=-rss | awk 'NR==1{next} NR<=14{printf "%6.0f  %s\n", $1/1024, $2}'
echo
echo "==> GPU"
lsmod | grep -E '^nvidia(_drm|_modeset)? ' | awk '{print "  module:", $1}'
cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null | sed 's/^/  nvidia_drm modeset: /'
echo
echo "Done. Log out of the compositor (Super+Shift+Alt+Q) and log in again."
echo "lilith now renders on the GPU (WLR_RENDERER=gles2) instead of the CPU."
