# Custom kernel

`kernel.sh` builds a `linux-mini` kernel from the latest installed `linux-zen` headers/configuration, regardless of which kernel is currently running. It does not run `localmodconfig`: drivers that are not loaded during this boot can still be needed for a later NVMe drive, GPU replacement, Wi-Fi adapter, Bluetooth device, USB storage, or filesystem image. It keeps zen's broader hardware and security support, drops debug/tracing overhead, and uses `-march=znver3` for Ryzen 5000 (including the Ryzen 7 5700X).

The config explicitly keeps NVMe and Btrfs built in. That allows a Btrfs root on an NVMe device to be discovered before initramfs module loading. It also enables AMDGPU/KMS and firmware loading for RDNA2 (RX 6650 XT). Image-related drivers (loop, device-mapper, FUSE, SquashFS, ISO9660, UDF, ext4, NBD, HFS/HFS+) are modules. USB mass storage/UAS and SATA remain available. Wi-Fi, Bluetooth and other device drivers from the zen config are retained.

The kernel supplies the AMDGPU kernel driver, not Mesa or RADV. On an Arch-compatible system with multilib enabled, the userspace stack for the RX 6650 XT is `mesa`, `vulkan-radeon`, `linux-firmware-amdgpu`, and optionally `lib32-mesa` plus `lib32-vulkan-radeon` for 32-bit apps. The installer already selects Mesa/RADV when its AMD GPU option is chosen.

## Build and install

Run from a full clone of this repository, with the build dependencies installed (`base-devel bc cpio libelf xz python kmod mkinitcpio linux-firmware linux-zen-headers`; `flex`, `bison`, `perl`, and `openssl` must also be available). DKMS is needed only for external modules such as AmneziaWG. The script performs a build and checks the config and required module objects without installing anything:

```sh
./kernel.sh
```

Review the built artifacts and build log. To install the kernel/modules and build a temporary initramfs, run:

```sh
./kernel.sh --install
```

The install mode asks before copying files, runs DKMS for the new release, verifies module dependency resolution and validates the generated initramfs before copying `vmlinuz-linux-mini` and `initramfs-linux-mini.img` into `/boot`. It does not create or edit any firmware/bootloader entry, one-shot boot choice, or boot order. `linux-zen` and its existing entry remain the fallback. Add a separate test entry using the installed bootloader's normal procedure, and keep zen selected until the mini kernel has passed the checks below.

## Checks and first boot

The script verifies required `.config` values, the built image-handling and AMDGPU modules, the installed dependency map and any installed AmneziaWG DKMS module, and that `lsinitcpio` can inspect the generated initramfs. If AmneziaWG DKMS is installed, install mode also enables a dinit service to load the module at boot. NVMe is deliberately built in (`CONFIG_BLK_DEV_NVME=y`), so it will not appear as `nvme.ko` and `modprobe nvme` is not the right check for this config. After booting the test entry, check `lspci -nnk`, `lsblk`, `dmesg -T | grep -iE 'nvme|amdgpu|firmware'`, `modinfo amdgpu`, `dkms status` when DKMS is used, and VPN connectivity. Test loop-mounted ISO/DMG images and the filesystems you use. Switch the default only after a successful test boot and retain the zen entry.

For an EFISTUB setup, first record the current `efibootmgr` output, then create a separate entry with `--create-only` (this leaves `BootOrder` unchanged). The command below reuses the current kernel parameters and adds the AMD microcode and new initramfs:

```sh
EFI_SRC=$(findmnt -no SOURCE /boot)
EFI_DISK=/dev/$(lsblk -no PKNAME "$EFI_SRC" | head -n1)
EFI_NUM=$(cat "/sys/class/block/$(basename "$EFI_SRC")/partition")
CMD=$(sed -e 's/initrd=[^ ]*//g' -e 's/BOOT_IMAGE=[^ ]*//' /proc/cmdline | tr -s ' ')
doas efibootmgr --create-only --disk "$EFI_DISK" --part "$EFI_NUM" \
  --label "Artix-mini" --loader "/vmlinuz-linux-mini" \
  --unicode "$CMD initrd=\\amd-ucode.img initrd=\\initramfs-linux-mini.img"
```

Select that entry once from the motherboard's boot menu. Do not remove or reorder the existing `Artix`/zen entry during testing.

A missing NVMe device can also be caused by a disabled M.2 slot, PCIe lane sharing, BIOS storage mode, or hardware seating; kernel support alone cannot diagnose those. With the custom kernel, `CONFIG_BLK_DEV_NVME=y` means a missing `/dev/nvme*` should be investigated with `lspci -nnk` and the kernel log rather than by expecting `modprobe nvme` to load a module.

## Disk images and Apple formats

Kernel support enables the common block and filesystem building blocks, but the container format still needs a userspace tool:

- ISO: `loop` plus `iso9660`/`udf`; use `mount -o loop` or an archive tool such as `7zip` to inspect files.
- SquashFS images: `loop` plus `squashfs-tools` (mount read-only or use `unsquashfs`).
- Raw `.img`: `losetup --find --show --partscan` (or `udisksctl loop-setup`), then mount the contained filesystem. Device-mapper is available for tools/images that need mapped block devices; NBD is available for userspace block servers.
- UDIF `.dmg`: [`dmg2img`](https://github.com/Lekensteyn/dmg2img) converts supported DMGs to raw images; then inspect with loop devices. HFS/HFS+ volumes can use the kernel HFS/HFS+ drivers and HFS utilities (`hfsprogs`).
- APFS: there is no in-tree Linux APFS driver. [`apfs-fuse`](https://github.com/sgan81/apfs-fuse) is a community read-only FUSE driver; [`libfsapfs`](https://github.com/libyal/libfsapfs) provides experimental read-only access for some APFS v2 volumes. Neither is a safe general-purpose writable APFS implementation. Encrypted or newer Apple images may need Apple-specific keys/tools and may not be mountable on Linux.
- iPadOS IPSW files are ZIP containers; use `7zip`/`unzip` to inspect or extract them. IMG4 firmware payloads are a separate userspace format and require tools such as `img4tool`; [`libirecovery`](https://github.com/libimobiledevice/libirecovery) and related libimobiledevice tools are for device communication and recovery workflows. Kernel filesystem options alone do not decode IMG4 or decrypt Apple firmware.

The `kernel/modprobed.db` file records modules used on one desktop and can fingerprint installed hardware. It remains tracked as supplied; this build no longer downloads or uses it to remove drivers.
