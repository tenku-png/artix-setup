#!/bin/sh
# Repair an installed system that fails at boot with
#   "Service root-ro command failed with exit code 32"
# Cause: the EFISTUB cmdline had "rw", so dinit's root-ro (remount / ro)
# fails with EBUSY on Btrfs. This adds a new EFI entry with "ro" (old entry
# is kept as a fallback). Touches no partitions, subvolumes or packages.
# Run as root from dinit recovery on the installed system.
set -eu

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

# leftover diagnostic override
[ -e /etc/dinit.d/root-ro ] && rm -v /etc/dinit.d/root-ro

[ -d /sys/firmware/efi ] || { echo "not booted in UEFI mode"; exit 1; }
ls /sys/firmware/efi/efivars >/dev/null 2>&1 && [ -n "$(ls /sys/firmware/efi/efivars)" ] ||
	mount -t efivarfs efivarfs /sys/firmware/efi/efivars

CMD=$(sed -e 's/^rw /ro /' -e 's/ rw / ro /' -e 's/ rw$/ ro/' /proc/cmdline)
case " $CMD " in *" ro "*) ;; *) echo "could not build cmdline: $CMD"; exit 1 ;; esac
case " $CMD " in *" rw "*) echo "cmdline still has rw: $CMD"; exit 1 ;; esac
case "$CMD" in *initramfs-linux-zen.img*) ;; *) echo "initrd missing in: $CMD"; exit 1 ;; esac

EFI=$(findmnt -no SOURCE /boot) || { echo "/boot not mounted (run: mount /boot)"; exit 1; }
DISK=/dev/$(lsblk -no PKNAME "$EFI" | head -1)
PART=$(cat "/sys/class/block/$(basename "$EFI")/partition")
[ -s /boot/vmlinuz-linux-zen ] || { echo "/boot/vmlinuz-linux-zen missing"; exit 1; }

echo "disk=$DISK part=$PART"
echo "cmdline: $CMD"
printf 'Create EFI entry? [y/N] '; read -r a; [ "$a" = y ] || exit 0

efibootmgr --create --disk "$DISK" --part "$PART" --label 'Artix' \
	--loader /vmlinuz-linux-zen --unicode "$CMD"
efibootmgr | head -4
sync
echo "Done. Reboot with: reboot"
