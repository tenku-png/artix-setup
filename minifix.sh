#!/bin/sh
# Recreate the Artix-mini EFI entry with "ro" (the old one had "rw" copied
# from the zen cmdline, so dinit's root-ro failed with EBUSY). No rebuild.
set -eu
[ -s /boot/vmlinuz-linux-mini ] || { echo "/boot/vmlinuz-linux-mini missing (run: fix kernel)"; exit 1; }
EFI=$(findmnt -no SOURCE /boot)
DISK=/dev/$(lsblk -no PKNAME "$EFI" | head -1)
PART=$(cat "/sys/class/block/$(basename "$EFI")/partition")
UC=amd-ucode.img; [ -f /boot/intel-ucode.img ] && ! [ -f /boot/amd-ucode.img ] && UC=intel-ucode.img
CMD=$(printf ' %s ' "$(cat /proc/cmdline)" | sed -e 's/initrd=[^ ]*//g' -e 's/ rw / ro /g' | tr -s ' ' | sed 's/^ //;s/ $//')
case " $CMD " in *" ro "*) ;; *) CMD="$CMD ro" ;; esac
echo "cmdline: $CMD initrd=\\$UC initrd=\\initramfs-linux-mini.img"
for n in $(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{sub(/Boot/,"");sub(/\*.*/,"");print}'); do doas efibootmgr -q -b "$n" -B; done
doas efibootmgr -q --create --disk "$DISK" --part "$PART" --label Artix-mini \
	--loader /vmlinuz-linux-mini --unicode "$CMD initrd=\\$UC initrd=\\initramfs-linux-mini.img"
n=$(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{print substr($1,5,4); exit}')
doas efibootmgr -q -n "$n"
echo "==> Artix-mini recreated with ro; it boots once on the next reboot (zen stays default)."
printf 'Reboot now? [y/N] '; read -r a </dev/tty; [ "$a" = y ] && doas reboot
