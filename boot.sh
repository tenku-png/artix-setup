#!/bin/bash
# fix boot: make the old bootloader on the EFI partition start Artix-mini.
B=/boot
K=$(cd $B && ls vmlinuz-*mini* 2>/dev/null | head -1); MK=${K#vmlinuz-}
echo "== now running: $(uname -r)   mini kernel file: ${K:-NONE}"
efibootmgr | grep -E '^Boot(Current|Order|[0-9A-F]{4})' | cut -c1-60
echo "== EFI: $(ls $B/EFI 2>/dev/null | tr '\n' ' ')"
[ -n "$K" ] || { echo "!! no mini kernel in /boot (run: fix kernel)"; exit 1; }

if [ -f $B/loader/loader.conf ]; then
	echo "== systemd-boot found"
	src=$(grep -l 'linux-zen' $B/loader/entries/*.conf 2>/dev/null | head -1)
	[ -n "$src" ] || { echo "!! no zen entry in $B/loader/entries"; ls $B/loader/entries; exit 1; }
	sed -e "s/linux-zen/$MK/g" -e 's/^title.*/title Artix mini/' "$src" | doas tee $B/loader/entries/artix-mini.conf >/dev/null
	doas sed -i '/^default/d' $B/loader/loader.conf
	echo 'default artix-mini.conf' | doas tee -a $B/loader/loader.conf >/dev/null
	echo "==> default: Artix mini (zen stays in the menu, from: $(basename "$src"))"
	cat $B/loader/entries/artix-mini.conf
elif ls $B/EFI/refind >/dev/null 2>&1; then
	echo "== rEFInd found: send a photo of this screen"
elif ls $B/grub $B/EFI/*/grubx64.efi >/dev/null 2>&1; then
	echo "== GRUB found: send a photo of this screen"
	ls $B/grub 2>/dev/null | head
else
	echo "== unknown loader: send a photo of this screen"
fi
