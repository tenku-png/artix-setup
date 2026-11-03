#!/bin/bash
# Stop background services that do not need to run all the time.
#   curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/trim.sh | bash
set -u
ask() { local a; read -rp "$1 [y/N]: " a < /dev/tty; [[ $a =~ ^[Yy] ]]; }

echo "==> libvirt: no longer started at boot (~70 MiB)."
echo "    Before using virt-manager run:  vm-on"
for s in libvirtd virtlogd virtlockd; do
	doas rm -f "/etc/dinit.d/boot.d/$s"
	doas dinitctl stop "$s" >/dev/null 2>&1
done
printf '#!/bin/sh\n# start libvirt for virt-manager\ndoas dinitctl start virtlogd; doas dinitctl start libvirtd\n' |
	doas tee /usr/local/bin/vm-on >/dev/null
doas chmod +x /usr/local/bin/vm-on

if ask "Remove thumbnails in thunar (tumbler, ~45 MiB while it hangs around)?"; then
	pkill -x tumblerd
	doas pacman -Rns --noconfirm tumbler ffmpegthumbnailer
fi

if ask "Start AmneziaVPN only when needed instead of at boot (~60 MiB)?"; then
	doas rm -f /etc/dinit.d/boot.d/amneziavpn
	doas dinitctl stop amneziavpn >/dev/null 2>&1
	printf '#!/bin/sh\ndoas dinitctl start amneziavpn\n' | doas tee /usr/local/bin/vpn-on >/dev/null
	doas chmod +x /usr/local/bin/vpn-on
	echo "    Before using the VPN run:  vpn-on"
fi

# Only the wlr portal: one portal process instead of two
mkdir -p ~/.config/xdg-desktop-portal
printf '[preferred]\ndefault=wlr\n' > ~/.config/xdg-desktop-portal/portals.conf
pkill -f xdg-desktop-portal-gtk

echo
mem 2>/dev/null
echo "Done."
