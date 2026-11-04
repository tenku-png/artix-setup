#!/bin/bash
# fix compress [level]: stronger btrfs compression (zstd, default level 6).
# New writes are compressed at once; old files only if you agree to recompress.
set -u
L=${1:-6}
ask() { local a; read -rp "$1 [y/N]: " a < /dev/tty; [[ $a =~ ^[Yy] ]]; }
echo "== now:"; findmnt -t btrfs -no TARGET,OPTIONS | sed 's/,subvolid.*//'
doas cp /etc/fstab /etc/fstab.bak
doas sed -i -E "/[[:space:]]btrfs[[:space:]]/ { s/compress(-force)?=[a-z]+(:[0-9]+)?/compress=zstd:$L/; /compress=/! s/(btrfs[[:space:]]+)([^[:space:]]+)/\1\2,compress=zstd:$L/ }" /etc/fstab
for t in $(findmnt -t btrfs -no TARGET); do doas mount -o remount,compress=zstd:$L "$t"; done
echo "== after (fstab saved, backup /etc/fstab.bak):"; findmnt -t btrfs -no TARGET,OPTIONS | sed 's/,subvolid.*//'
command -v compsize >/dev/null && doas compsize -x / 2>/dev/null | head -4
if [ "$(doas btrfs subvolume list -s / 2>/dev/null | wc -l)" -gt 0 ]; then
	echo "!! you have snapshots: recompressing old files would copy them (more space). Skipped."
	exit 0
fi
if ask "Recompress existing files now (takes long, PC stays usable)?"; then
	doas nice -n 19 ionice -c3 btrfs filesystem defragment -r -czstd -L "$L" / 2>/dev/null ||
		doas nice -n 19 ionice -c3 btrfs filesystem defragment -r -czstd /
	command -v compsize >/dev/null && doas compsize -x / 2>/dev/null | head -4
fi
echo "Done."
