#!/bin/bash
# fix theme: wallpaper picker (Super+Shift+W) + matugen colors for lilith,
# foot and fastfetch. Your edited templates are kept.
set -u
R=https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}
get() { curl -fsSL --retry 5 --retry-delay 2 -m 60 "$R/$1" -o "$2"; }
if ! command -v matugen >/dev/null; then
	echo "==> installing matugen"
	doas pacman -S --needed --noconfirm matugen 2>/dev/null ||
		for i in 1 2 3; do paru -S --needed --noconfirm matugen-bin && break; echo "retrying..."; sleep 3; done
fi
mkdir -p ~/.config/matugen/templates ~/.config/foot ~/.config/lilith ~/Pictures/wallpapers
[ -f ~/.config/matugen/config.toml ] || get configs/matugen/config.toml ~/.config/matugen/config.toml
for t in lilith-colors foot.ini fastfetch.fish; do
	[ -f ~/.config/matugen/templates/$t ] || get configs/matugen/templates/$t ~/.config/matugen/templates/$t
done
# foot reads the generated colors through an include
grep -qs 'colors.ini' ~/.config/foot/foot.ini ||
	{ printf 'include=~/.config/foot/colors.ini\n'; cat ~/.config/foot/foot.ini 2>/dev/null; } > /tmp/foot.ini &&
	mv /tmp/foot.ini ~/.config/foot/foot.ini
touch ~/.config/foot/colors.ini
get bin/wall /tmp/wall && doas install -m755 /tmp/wall /usr/local/bin/wall
command -v matugen >/dev/null && echo "==> matugen $(matugen --version 2>/dev/null)" || echo "!! matugen not installed"
echo "==> put pictures (png/jpg) into ~/Pictures/wallpapers, then Super+Shift+W"
echo "    (needs: fix lilith-new). New terminals get the colors after re-login."
