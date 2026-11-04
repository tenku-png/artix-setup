#!/bin/bash
# fix slim: stop services that sit in RAM for nothing.
set -u
ask() { local a; read -rp "$1 [y/N]: " a < /dev/tty; [[ $a =~ ^[Yy] ]]; }

echo "==> libvirt off at boot (~70 MiB). For virt-manager first run: vm-on"
for s in libvirtd virtlogd virtlockd libvirtd-socket; do
	doas rm -f "/etc/dinit.d/boot.d/$s"
	doas dinitctl stop "$s" >/dev/null 2>&1
done
printf '#!/bin/sh\n# start libvirt for virt-manager\ndoas dinitctl start virtlogd; doas dinitctl start libvirtd\n' |
	doas tee /usr/local/bin/vm-on >/dev/null
doas chmod +x /usr/local/bin/vm-on

if ask "Remove thumbnails in thunar (tumbler, ~45 MiB)?"; then
	pkill -x tumblerd
	doas pacman -Rns --noconfirm tumbler ffmpegthumbnailer
fi

echo
mem 2>/dev/null
echo "Done. Reboot, open NOTHING, then: fix ramtop"
