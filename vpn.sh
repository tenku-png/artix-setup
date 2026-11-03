#!/bin/bash
# Install AmneziaVPN (AUR) with its dinit service.   fix vpn
set -e
if ! pacman -Q amneziavpn-bin >/dev/null 2>&1; then
	echo "==> installing amneziavpn-bin (AUR, may take a while)"
	for i in 1 2 3; do paru -S --needed --noconfirm --skipreview amneziavpn-bin && break; echo "retry $i/3..."; sleep 3; done
fi
pacman -Q amneziavpn-bin >/dev/null 2>&1 || { echo "AmneziaVPN did not install, send a photo of the error"; exit 1; }

echo "==> dinit service"
curl -fsSL "https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}/dinit/amneziavpn" |
	doas tee /etc/dinit.d/amneziavpn >/dev/null
doas ln -sf /etc/dinit.d/amneziavpn /etc/dinit.d/boot.d/amneziavpn
doas dinitctl start amneziavpn || true
doas dinitctl status amneziavpn | head -3

cat <<'MSG'

==> Done. Open the app:  Super+Space, type "amnezia"   (or run: AmneziaVPN &)
    then add your key / config and connect.
MSG
