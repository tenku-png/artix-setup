#!/bin/bash
# Build a trimmed kernel (same version as the running linux-zen) next to zen.
#   fix kernel
# zen stays installed as the fallback boot entry "Artix".
set -euo pipefail
R="https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}"
W=$HOME/.cache/kernel
NAME=linux-mini

ZVER=$(uname -r)                      # e.g. 7.2.11-zen1-1-zen
VER=${ZVER%%-*}                       # 7.2.11
MAJ=${VER%%.*}
echo "==> building $VER ($NAME) with the config of $ZVER, trimmed to this PC"
echo "    takes ~15-30 min on a Ryzen 1700X; zen stays as the fallback"

doas pacman -S --needed --noconfirm base-devel bc cpio pahole xz git >/dev/null
mkdir -p "$W" && cd "$W"
TAR=linux-$VER.tar.xz
if [ ! -d "linux-$VER" ]; then
	curl -fL --retry 3 -o "$TAR" "https://cdn.kernel.org/pub/linux/kernel/v$MAJ.x/$TAR"
	tar xf "$TAR" && rm -f "$TAR"
fi
cd "linux-$VER"

# Base: the running zen config
zcat /proc/config.gz > .config 2>/dev/null || cp "/usr/lib/modules/$ZVER/build/.config" .config
make olddefconfig >/dev/null
cp .config zen.config

# Keep only modules used on this PC: loaded now + the list from the old Arch
{
	lsmod | awk 'NR>1{print $1}'
	curl -fsSL "$R/kernel/modprobed.db" || true
	printf '%s\n' usb_storage uas exfat vfat ntfs3 tun amneziawg uinput \
		kvm kvm_amd vhost_net tap bridge snd_usb_audio hid_generic usbhid
} | sort -u | awk '{print $1, 0, 0}' > lsmod.txt
# (yes exits with SIGPIPE when make is done; only make's status matters)
set +o pipefail
yes "" | make LSMOD="$PWD/lsmod.txt" localmodconfig >/dev/null
[ "${PIPESTATUS[1]}" = 0 ] || { echo "localmodconfig failed"; exit 1; }
set -o pipefail

S=scripts/config
# GPU drivers in use right now (e.g. amdgpu for the RX 6650 XT): never drop them
GPUDRV=$(for d in /sys/class/drm/card*/device/driver; do basename "$(readlink "$d")"; done 2>/dev/null | sort -u | tr '\n' ' ')
echo "==> GPU driver(s) in use: ${GPUDRV:-none}"
keep() { case " $GPUDRV " in *" $1 "*) return 0 ;; esac; return 1; }
DROP="" ; DROPRE=""
for pair in amdgpu:AMDGPU radeon:RADEON i915:I915 xe:XE nouveau:NOUVEAU; do
	drv=${pair%%:*}; cfg=${pair#*:}
	if keep "$drv"; then $S -m "DRM_$cfg"; else DROP="$DROP -d DRM_$cfg"; DROPRE="$DROPRE|$cfg"; fi
done
# not used on this PC
$S -d BT -d WLAN -d WIRELESS -d CFG80211 -d MAC80211 -d NFC -d WWAN -d CAN -d HAMRADIO
[ -n "$DROP" ] && $S $DROP
$S -d CPU_SUP_INTEL -d CPU_SUP_HYGON -d CPU_SUP_CENTAUR -d CPU_SUP_ZHAOXIN -d MICROCODE_INTEL
# debugging / tracing
$S -d DEBUG_KERNEL -e DEBUG_INFO_NONE -d DEBUG_INFO_BTF -d FTRACE -d KPROBES -d PROFILING \
	-d KEXEC -d KEXEC_FILE -d KEXEC_HANDOVER -d CRASH_DUMP -d DEBUG_FS -d SLUB_DEBUG -d IKHEADERS
# keep what the system relies on
$S -e SECURITY -e SECURITY_LANDLOCK -e MODULES -e BLK_DEV_INITRD -e IKCONFIG -e IKCONFIG_PROC \
	-e NAMESPACES -e USER_NS -e CGROUPS -e TUN -e BTRFS_FS -e VFAT_FS -e EXFAT_FS -e NTFS3_FS \
	-m WIREGUARD -e DRM -e DRM_FBDEV_EMULATION -e SYSFB_SIMPLEFB -e DRM_SIMPLEDRM -e INPUT_UINPUT
$S --set-str LOCALVERSION "-mini" -d LOCALVERSION_AUTO
# Graphics stack as in zen (localmodconfig drops DRM/fbdev helpers that
# amdgpu and the out-of-tree NVIDIA driver need); unused GPU drivers stay off
grep -E '^CONFIG_(DRM|FB|FRAMEBUFFER|FONT|VT|DUMMY_CONSOLE|DMA_SHARED|DMABUF|SYNC_FILE|SW_SYNC|UDMABUF|VIDEO|BACKLIGHT|HDMI|AGP|VGA|SYSFB|AUXDISPLAY|I2C|EFI)[A-Z0-9_]*=[ym]' zen.config |
	grep -vE "^CONFIG_DRM_(${DROPRE#|}${DROPRE:+|}VMWGFX|QXL|BOCHS|VIRTIO|VBOXVIDEO|GMA500|MGAG200|AST|HISI|HYPERV|XEN)" >> .config
# Netfilter as in zen: localmodconfig keeps only loaded nft modules, so
# awg-quick's rules (table ip ..., ct mark, fib) failed with "No such file"
grep -E '^CONFIG_(NETFILTER|NF_|NFT_|IP_NF|IP6_NF|NF_TABLES|IP_ADVANCED_ROUTER|IP_MULTIPLE_TABLES|IPV6_MULTIPLE_TABLES|FIB_RULES)[A-Z0-9_]*=[ym]' zen.config >> .config
# awg-quick nft rules need these explicitly (fib, ct mark, inet)
$S -e NF_TABLES_IPV4 -e NF_TABLES_IPV6 -e NF_TABLES_INET -m NFT_CT -m NFT_FIB -m NFT_FIB_IPV4 \
	-m NFT_FIB_IPV6 -m NFT_FIB_INET -e IP_MULTIPLE_TABLES -e IPV6_MULTIPLE_TABLES
make olddefconfig >/dev/null
echo "==> config: $(grep -c '=y' .config) built-in, $(grep -c '=m' .config) modules"

time make -j"$(nproc)" KCFLAGS="-march=znver1 -O2"
KVER=$(make -s kernelrelease)

echo "==> installing $KVER"
doas make modules_install >/dev/null
doas install -m644 arch/x86/boot/bzImage "/boot/vmlinuz-$NAME"
# dkms modules (nvidia, amneziawg) need the build tree: /usr/lib/modules/$KVER/build
doas ln -sfn "$PWD" "/usr/lib/modules/$KVER/build"
# modules_install wiped earlier dkms modules: drop stale dkms records first
if command -v dkms >/dev/null; then
	for m in $(dkms status -k "$KVER" 2>/dev/null | cut -d, -f1 | sort -u); do doas dkms remove "$m" -k "$KVER" >/dev/null 2>&1; done
	doas dkms autoinstall -k "$KVER" || echo "!! dkms failed: out-of-tree modules may be missing on $NAME"
fi
doas depmod -a "$KVER"
# Only autoload modules that exist, or dinit's early-modules.target fails
modinfo -k "$KVER" amneziawg >/dev/null 2>&1 &&
	echo amneziawg | doas tee /etc/modules-load.d/amneziawg.conf >/dev/null
modinfo -k "$KVER" amdgpu >/dev/null 2>&1 || ! keep amdgpu || { echo "!! amdgpu missing in $KVER, not installing a boot entry"; exit 1; }
doas mkinitcpio -k "$KVER" -g "/boot/initramfs-$NAME.img"

echo "==> boot entry \"Artix-mini\" (zen entry \"Artix\" is kept)"
EFI_SRC=$(findmnt -no SOURCE /boot)
EFI_DISK=/dev/$(lsblk -no PKNAME "$EFI_SRC" | head -1)
EFI_NUM=$(cat "/sys/class/block/$(basename "$EFI_SRC")/partition")
CMD=$(sed -e 's/initrd=[^ ]*//g' -e 's/BOOT_IMAGE=[^ ]*//' /proc/cmdline | tr -s ' ')
# dinit's root-ro must be able to remount / read-only: boot with "ro", never "rw"
CMD=$(printf ' %s ' "$CMD" | sed -e 's/ rw / ro /g' -e 's/^ *//;s/ *$//')
case " $CMD " in *" ro "*) ;; *) CMD="$CMD ro" ;; esac
UC=amd-ucode.img; [ -f /boot/intel-ucode.img ] && ! [ -f /boot/amd-ucode.img ] && UC=intel-ucode.img
for n in $(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{sub(/Boot/,"");sub(/\*.*/,"");print}'); do doas efibootmgr -q -b "$n" -B; done
doas efibootmgr -q --create --disk "$EFI_DISK" --part "$EFI_NUM" --label "Artix-mini" \
	--loader "/vmlinuz-$NAME" --unicode "$CMD initrd=\\$UC initrd=\\initramfs-$NAME.img"
MINI=$(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{sub(/Boot/,"");sub(/\*.*/,"");print; exit}')
ORDER=$(efibootmgr | awk -F': ' '/^BootOrder/{print $2}')
# Try it once on the next boot only; the normal order stays as it is
doas efibootmgr -q -n "$MINI"

cat <<MSG

==> Done: $KVER installed. The NEXT boot (once) uses Artix-mini.
    Works?  make it the default:  doas efibootmgr -o $MINI,${ORDER//$MINI,/}
    Broken? just reboot: the boot after that is zen again.
MSG
