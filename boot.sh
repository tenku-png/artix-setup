#!/bin/bash
# fix boot: make the old bootloader on the EFI partition start Artix-mini.
B=/boot
K=$(cd $B && ls vmlinuz-*mini* 2>/dev/null | head -1); MK=${K#vmlinuz-}
echo "== now running: $(uname -r)   mini kernel file: ${K:-NONE}"
efibootmgr | grep -E '^Boot(Current|Order|[0-9A-F]{4})' | cut -c1-60
echo "== EFI: $(ls $B/EFI 2>/dev/null | tr '\n' ' ')"
[ -n "$K" ] || { echo "!! no mini kernel in /boot (run: fix kernel)"; exit 1; }

# 1) firmware: Artix-mini entry first (the firmware may still prefer systemd-boot)
m=$(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{print substr($1,5,4); exit}')
if [ -n "$m" ]; then
	rest=$(efibootmgr | awk -F': ' '/^BootOrder/{print $2}' | tr ',' '\n' | grep -v "^$m$" | paste -sd,)
	doas efibootmgr -q -o "$m${rest:+,$rest}" && echo "==> BIOS order: Artix-mini first"
fi
if [ -f $B/loader/loader.conf ]; then
	# 2) systemd-boot: own entry built from the running command line
	echo "== systemd-boot entries: $(ls $B/loader/entries 2>/dev/null | tr '\n' ' ') | EFI/Linux: $(ls $B/EFI/Linux 2>/dev/null | tr '\n' ' ')"
	CMD=$(sed -e 's/initrd=[^ ]*//g' -e 's/BOOT_IMAGE=[^ ]*//' /proc/cmdline | tr -s ' ')
	UC=; [ -f $B/amd-ucode.img ] && UC="initrd  /amd-ucode.img"
	doas mkdir -p $B/loader/entries
	printf 'title   Artix mini\nlinux   /%s\n%s\ninitrd  /initramfs-%s.img\noptions %s\n' "$K" "$UC" "$MK" "$CMD" |
		grep -v '^$' | doas tee $B/loader/entries/artix-mini.conf
	doas sed -i '/^default/d' $B/loader/loader.conf
	echo 'default artix-mini.conf' | doas tee -a $B/loader/loader.conf >/dev/null
	# a default picked in the menu (key d) is stored in an EFI variable and wins over loader.conf
	v=/sys/firmware/efi/efivars/LoaderEntryDefault-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
	[ -e $v ] && { doas chattr -i $v; doas rm -f $v; echo "==> removed the menu-saved default"; }
	echo "==> systemd-boot default: Artix mini. Reboot: doas reboot"
elif ls $B/EFI/refind >/dev/null 2>&1; then
	echo "== rEFInd found: send a photo of this screen"
elif ls $B/grub $B/EFI/*/grubx64.efi >/dev/null 2>&1; then
	echo "== GRUB found: send a photo of this screen"
	ls $B/grub 2>/dev/null | head
else
	echo "== unknown loader: send a photo of this screen"
fi
