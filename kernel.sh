#!/bin/bash
# Build a compatible, trimmed kernel alongside linux-zen.
# By default this only builds and verifies artifacts in ~/.cache/kernel.
# Pass --install to copy the verified kernel/modules/initramfs into the system.
# This script never changes bootloader entries or boot order.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

case "${1:-}" in
	"") INSTALL=n ;;
	--install) INSTALL=y ;;
	*) echo "usage: $0 [--install]" >&2; exit 2 ;;
esac

NAME=linux-mini
W=${KERNEL_WORKDIR:-$HOME/.cache/kernel}
JOBS=${JOBS:-$(nproc)}
KCFLAGS=${KCFLAGS:--march=znver3 -O2}

command -v make >/dev/null || { echo "make is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

ZVER=$(for d in /usr/lib/modules/*-zen; do
	[ -f "$d/build/.config" ] && basename "$d"
done | sort -V | tail -n1)
[ -n "$ZVER" ] || {
	echo "no installed linux-zen build config; install linux-zen-headers first" >&2
	exit 1
}
VER=${ZVER%%-*}
MAJ=${VER%%.*}
echo "==> building $VER ($NAME) from the installed linux-zen $ZVER config"
echo "    no localmodconfig: devices and removable media may be attached later"
echo "    zen remains the installed fallback; no bootloader entry/order is changed"

for cmd in make gcc curl tar zcat nproc flex bison perl openssl; do
	command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
done
for pkg in bc cpio libelf xz python kmod mkinitcpio linux-firmware linux-zen-headers; do
	pacman -Q "$pkg" >/dev/null 2>&1 || {
		echo "missing package: $pkg (install it before running this script)" >&2
		exit 1
	}
done
if command -v dkms >/dev/null && ! pacman -Q dkms >/dev/null 2>&1; then
	echo "dkms command exists but its package is not registered with pacman" >&2
	exit 1
fi
if [ "$INSTALL" = y ]; then
	for cmd in doas lsinitcpio; do
		command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
	done
fi

mkdir -p "$W"
cd "$W"
TAR=linux-$VER.tar.xz
if [ ! -d "linux-$VER" ]; then
	curl -fL --retry 3 -o "$TAR" "https://cdn.kernel.org/pub/linux/kernel/v$MAJ.x/$TAR"
	tar xf "$TAR" && rm -f "$TAR"
fi
cd "linux-$VER"

# Start with the known working kernel config. Do not reduce it based on loaded
# modules: NVMe, AMDGPU, Wi-Fi, Bluetooth, USB and image formats may be needed
# only after a device is connected or the machine boots with different hardware.
cp "/usr/lib/modules/$ZVER/build/.config" .config
make olddefconfig >/dev/null
cp .config zen.config
S=scripts/config

# Root storage and filesystem support must be built in so the root device can
# be reached before initramfs module discovery. Other image handlers stay modular.
$S -e PCI -e PCIEPORTBUS -e BLK_DEV_NVME -e NVME_CORE -e BTRFS_FS
$S -m ATA -m SATA_AHCI -m BLK_DEV_SD -m USB_STORAGE -m USB_UAS
$S -m BLK_DEV_LOOP -m BLK_DEV_DM -m DM_CRYPT -m DM_SNAPSHOT
$S -m FUSE_FS -m SQUASHFS -m ISO9660_FS -m UDF_FS -m EXT4_FS -m BLK_DEV_NBD
$S -m HFS_FS -m HFSPLUS_FS -m OVERLAY_FS
$S -m VFAT_FS -m EXFAT_FS -m NTFS3_FS

# Keep broad device coverage and the graphics/KMS stack for AMD RDNA2
# (RX 6650 XT / Navi 23).
$S -e DRM -e DRM_KMS_HELPER -e DRM_FBDEV_EMULATION -e SYSFB_SIMPLEFB \
	-e DRM_SIMPLEDRM -m DRM_AMDGPU -e FW_LOADER
$S -e DRM_AMD_DC
$S -e TUN -e WIREGUARD -e BTRFS_FS -e MODULES -e BLK_DEV_INITRD \
	-e SECURITY -e SECURITY_LANDLOCK -e NAMESPACES -e USER_NS -e CGROUPS \
	-e IKCONFIG -e IKCONFIG_PROC -e INPUT_UINPUT -e KVM -e KVM_AMD \
	-e VHOST_NET -e BRIDGE -e NETFILTER -e NF_TABLES -e USB \
	-e SND -e SND_HDA_INTEL -e SND_HDA_CODEC_REALTEK -e SND_HDA_CODEC_HDMI
$S -m BT -m WLAN -m WIRELESS -m CFG80211 -m MAC80211

# Keep debug info and tracing out of the release build, without dropping
# runtime security, namespaces, cgroups, or device support.
$S -d DEBUG_KERNEL -e DEBUG_INFO_NONE -d DEBUG_INFO_BTF -d FTRACE \
	-d KPROBES -d PROFILING -d KEXEC -d KEXEC_FILE -d KEXEC_HANDOVER \
	-d CRASH_DUMP -d DEBUG_FS -d SLUB_DEBUG -d IKHEADERS
$S --set-str LOCALVERSION "-mini" -d LOCALVERSION_AUTO
make olddefconfig >/dev/null

python3 "$SCRIPT_DIR/kernel/check.py" config .config

echo "==> config: $(grep -c '=y' .config) built-in, $(grep -c '=m' .config) modules"
time make -j"$JOBS" KCFLAGS="$KCFLAGS"
KVER=$(make -s kernelrelease)
python3 "$SCRIPT_DIR/kernel/check.py" build --source "$PWD" --kver "$KVER"

if [ "$INSTALL" != y ]; then
	cat <<MSG

==> Build verified: $KVER
    artifacts: $PWD/arch/x86/boot/bzImage and the module tree in the build directory
    Run again with --install to install the kernel and build/initramfs after review.
    The --install mode still does not alter firmware/bootloader entries or order.
MSG
	exit 0
fi

read -rp "Install $KVER alongside linux-zen? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "cancelled; no system files changed"; exit 1; }

# Install modules for this distinct release, then build external modules and
# verify the dependency map before writing kernel/initramfs files under /boot.
doas make modules_install >/dev/null
doas ln -sfn "$PWD" "/usr/lib/modules/$KVER/build"
if command -v dkms >/dev/null; then
	# modules_install replaced the release tree; clear DKMS's prior records for
	# this exact kernel release so it rebuilds them against the new objects.
	for module in $(dkms status -k "$KVER" 2>/dev/null | cut -d, -f1 | sort -u); do
		doas dkms remove "$module" -k "$KVER" >/dev/null 2>&1 || true
	done
	doas dkms autoinstall -k "$KVER"
fi
doas depmod -a "$KVER"
python3 "$SCRIPT_DIR/kernel/check.py" installed --kver "$KVER"
if command -v dkms >/dev/null && dkms status | grep -q '^amneziawg/'; then
	doas install -Dm644 "$SCRIPT_DIR/dinit/amneziawg-module" /etc/dinit.d/amneziawg-module
	doas install -d -m755 /etc/dinit.d/boot.d
	doas ln -sfn /etc/dinit.d/amneziawg-module /etc/dinit.d/boot.d/amneziawg-module
fi

IMGDIR=$(mktemp -d "$W/initramfs-$NAME.XXXXXX")
IMG=$IMGDIR/initramfs.img
trap 'rm -rf "$IMGDIR"' EXIT
doas mkinitcpio -k "$KVER" -g "$IMG"
lsinitcpio -a "$IMG" >/dev/null
python3 "$SCRIPT_DIR/kernel/check.py" initramfs --image "$IMG"

doas install -m644 arch/x86/boot/bzImage "/boot/vmlinuz-$NAME"
doas install -m644 "$IMG" "/boot/initramfs-$NAME.img"
cat <<MSG

==> Installed and verified $KVER as $NAME. linux-zen is untouched.
    No bootloader entries or boot order were changed.
    Add a test entry using your bootloader's documented method, then verify
    NVMe, graphics, networking, VPN/DKMS and image mounting before changing defaults.
MSG
