#!/bin/bash
# Fix "VPN connected but video/downloads stall" (MTU/MSS).   fix vpnfix
set -e
R="https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}"
doas pacman -S --needed --noconfirm nftables >/dev/null
doas mkdir -p /etc/nftables.d
curl -fsSL "$R/configs/nftables/vpn-mss.nft" | doas tee /etc/nftables.d/vpn-mss.nft >/dev/null
curl -fsSL "$R/dinit/vpn-mss" | doas tee /etc/dinit.d/vpn-mss >/dev/null
doas nft delete table inet vpn_mss 2>/dev/null || true
doas nft -f /etc/nftables.d/vpn-mss.nft
doas ln -sf /etc/dinit.d/vpn-mss /etc/dinit.d/boot.d/vpn-mss
echo "==> MSS clamp active (also at every boot)."
if ip link show amn0 >/dev/null 2>&1; then
	doas ip link set amn0 mtu 1280 && echo "==> amn0 MTU set to 1280 for this connection"
fi
echo "==> testing download through the VPN..."
curl -s -o /dev/null --max-time 15 -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=30000000' |
	awk '{printf "    %.1f MB/s\n", $1/1048576}'
echo "Reload YouTube now."
