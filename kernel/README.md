# Kernel

`modprobed.db` is the list of modules loaded on the desktop PC (Arch,
`modprobed-db`), used with `make localmodconfig` to build a kernel that
only contains this hardware.

Hardware notes from the list:
- Ethernet: Realtek `r8169` (+ `realtek` PHY), needs `rtl_nic` firmware
- Audio: Realtek ALC662 codec + NVIDIA HDMI audio (`nvhdmi`)
- GPU: GTX 1660 Super; the proprietary `nvidia*` modules come from dkms
  and are not in this list
- Virtualization: `kvm_amd`, `vhost_net`, `tap`, `bridge` (virt-manager)
- Netfilter (`nf_tables`, `xt_*`) and `tun`: AmneziaVPN and libvirt NAT

To drop when building (not used): Bluetooth (`bluetooth`, `bt*`,
`rfcomm`, `bnep`), Wi-Fi (`cfg80211`, `rfkill`), GPU USB-C
(`typec*`, `ucsi_ccg`, `thunderbolt`), `sp5100_tco`, `pcspkr`.

To add (not captured): `usb_storage`, `uas` for flash drives.
