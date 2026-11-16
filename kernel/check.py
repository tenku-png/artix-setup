#!/usr/bin/env python3
"""Offline sanity checks for the custom kernel build/install artifacts."""
from __future__ import annotations
import argparse
import pathlib
import re
import subprocess
import sys

REQUIRED = {
    "BLK_DEV_NVME": "y", "NVME_CORE": "y", "BTRFS_FS": "y",
    "PCI": "y", "PCIEPORTBUS": "y", "DRM": "y", "DRM_AMDGPU": "m",
    "DRM_AMD_DC": "y", "DRM_KMS_HELPER": "y", "DRM_FBDEV_EMULATION": "y",
    "DRM_SIMPLEDRM": "y", "SYSFB_SIMPLEFB": "y",
    "FW_LOADER": "y", "SECURITY": "y", "MODULES": "y",
    "BLK_DEV_INITRD": "y", "TUN": "y", "WIREGUARD": "y",
    "KVM_AMD": "y", "VHOST_NET": "y", "NF_TABLES": "y",
}
MODULE_CONFIGS = {
    "loop": "BLK_DEV_LOOP", "dm_mod": "BLK_DEV_DM", "dm_crypt": "DM_CRYPT",
    "fuse": "FUSE_FS", "squashfs": "SQUASHFS", "isofs": "ISO9660_FS",
    "udf": "UDF_FS", "ext4": "EXT4_FS", "nbd": "BLK_DEV_NBD", "hfs": "HFS_FS",
    "hfsplus": "HFSPLUS_FS", "overlay": "OVERLAY_FS",
    "usb_storage": "USB_STORAGE", "uas": "USB_UAS",
}
IMAGE_MODULES = tuple(MODULE_CONFIGS)


def fail(message: str) -> None:
    print(f"kernel-check: ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_config(path: pathlib.Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"config not found: {path}")
    values = {}
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r"CONFIG_([A-Z0-9_]+)=(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2).strip('"')
            continue
        m = re.match(r"# CONFIG_([A-Z0-9_]+) is not set$", line)
        if m:
            values[m.group(1)] = "n"
    return values


def config(path: pathlib.Path) -> None:
    values = parse_config(path)
    missing = [f"CONFIG_{key} expected {want}, got {values.get(key, 'undefined')}"
               for key, want in REQUIRED.items() if values.get(key) != want]
    missing += [f"CONFIG_{symbol} must be modular, got {values.get(symbol, 'undefined')}"
                for symbol in MODULE_CONFIGS.values() if values.get(symbol) != "m"]
    if missing:
        fail("required options are missing or have unexpected values:\n  " + "\n  ".join(missing))
    print(f"kernel-check: config OK ({len(REQUIRED) + len(IMAGE_MODULES)} required options)")


def modules(source: pathlib.Path) -> None:
    missing = []
    for name in IMAGE_MODULES + ("amdgpu",):
        variants = {name, name.replace("_", "-"), name.replace("-", "_")}
        matches = [path for variant in variants for suffix in (".ko", ".ko.xz", ".ko.zst")
                   for path in source.rglob(variant + suffix)]
        if not matches:
            missing.append(name)
    if missing:
        fail("built module files missing: " + ", ".join(missing))
    print("kernel-check: required image and AMDGPU modules are built")


def modprobe_dependencies(kver: str) -> None:
    for name in IMAGE_MODULES + ("amdgpu",):
        result = subprocess.run(["modprobe", "--set-version", kver, "--show-depends", name],
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            fail(f"module dependency resolution failed for {name} (exit {result.returncode})")
        if not result.stdout.strip():
            fail(f"module dependency map returned no entries for {name}")
    print("kernel-check: module dependency resolution OK")


def dkms_dependencies(kver: str) -> None:
    try:
        result = subprocess.run(["dkms", "status"], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        print("kernel-check: DKMS is not installed; no external DKMS modules to check")
        return
    if result.returncode:
        fail(f"dkms status failed (exit {result.returncode})")

    checked = []
    for name in ("amneziawg",):
        entries = [line for line in result.stdout.splitlines()
                   if line.split("/", 1)[0] == name]
        if not entries:
            continue
        installed = any(
            re.search(rf",\s*{re.escape(kver)},.*:\s*installed(?:\s|$|\()", line)
            for line in entries
        )
        if not installed:
            fail(f"DKMS did not install {name} for {kver}")
        dep = subprocess.run(["modprobe", "--set-version", kver, "--show-depends", name],
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if dep.returncode or not dep.stdout.strip():
            fail(f"DKMS dependency resolution failed for {name}")
        checked.append(name)
    print("kernel-check: optional DKMS dependencies OK" +
          (f" ({', '.join(checked)})" if checked else " (none installed)"))


def image(path: pathlib.Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"initramfs missing or empty: {path}")
    result = subprocess.run(["lsinitcpio", "-a", str(path)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        fail(f"initramfs archive validation failed (exit {result.returncode})")
    print("kernel-check: initramfs archive OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    p = sub.add_parser("config"); p.add_argument("path", type=pathlib.Path)
    p = sub.add_parser("build"); p.add_argument("--source", type=pathlib.Path, required=True); p.add_argument("--kver", required=True)
    p = sub.add_parser("installed"); p.add_argument("--kver", required=True)
    p = sub.add_parser("initramfs"); p.add_argument("--image", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.mode == "config":
        config(args.path)
    elif args.mode == "build":
        modules(args.source)
    elif args.mode == "installed":
        root = pathlib.Path("/usr/lib/modules") / args.kver
        if not (root / "modules.dep").is_file():
            fail(f"modules.dep missing for {args.kver}; run depmod first")
        modprobe_dependencies(args.kver)
        dkms_dependencies(args.kver)
    else:
        image(args.image)

if __name__ == "__main__":
    main()
