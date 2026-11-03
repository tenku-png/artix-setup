#!/bin/bash
# Network check for "sites work, YouTube does not".   fix net
set -u
b=$'\e[1m'; z=$'\e[0m'
speed() { curl -s -o /dev/null --max-time 15 -w '%{speed_download}' "$@" | awk '{printf "%.1f MB/s", $1/1048576}'; }

echo "${b}== network cards (driver, MTU, speed):${z}"
for i in /sys/class/net/*; do
	n=$(basename "$i"); [ "$n" = lo ] && continue
	drv=$(basename "$(readlink "$i/device/driver" 2>/dev/null)" 2>/dev/null)
	printf '  %-10s driver=%-8s mtu=%-5s speed=%sMb/s state=%s\n' "$n" "${drv:--}" "$(cat "$i/mtu")" \
		"$(cat "$i/speed" 2>/dev/null || echo ?)" "$(cat "$i/operstate")"
done
echo "${b}== recent NIC errors in the kernel log:${z}"
dmesg 2>/dev/null | grep -iE 'r8169|r8168|link (up|down)|tx timeout|eth[0-9]|enp' | tail -5 | sed 's/^/  /' ||
	doas dmesg | grep -iE 'r8169|r8168|link (up|down)|tx timeout' | tail -5 | sed 's/^/  /'
echo "${b}== VPN interfaces:${z}"
ip -br link | grep -Ei 'amn|wg|tun|awg' || echo "  none found (is the VPN connected?)"
echo "${b}== IPv6:${z}"
if ip -6 route show default 2>/dev/null | grep -q default; then
	echo "  IPv6 default route present: $(ip -6 route show default | head -1)"
	V6=yes
else
	echo "  no IPv6 route"
	V6=no
fi
echo "${b}== your IPv4 address as seen outside:${z} $(curl -4 -s --max-time 8 https://ifconfig.me || echo '?')"
[ "$V6" = yes ] && echo "${b}== your IPv6 address as seen outside:${z} $(curl -6 -s --max-time 8 https://ifconfig.me || echo '?')"
echo "${b}== download speed (15 s each):${z}"
echo "  cloudflare IPv4: $(speed -4 'https://speed.cloudflare.com/__down?bytes=30000000')"
[ "$V6" = yes ] && echo "  cloudflare IPv6: $(speed -6 'https://speed.cloudflare.com/__down?bytes=30000000')"
echo "  youtube (googlevideo) IPv4 reach: $(curl -4 -s -o /dev/null --max-time 8 -w '%{http_code} in %{time_total}s' https://redirector.googlevideo.com/report_mapping)"

if [ "$V6" = yes ]; then
	echo
	echo "IPv6 is active. If your VPN only tunnels IPv4, YouTube goes around the VPN over IPv6."
	read -rp "Turn IPv6 off (now and at boot)? [Y/n]: " a < /dev/tty
	if [[ ! $a =~ ^[Nn] ]]; then
		printf 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\n' |
			doas tee /etc/sysctl.d/40-no-ipv6.conf >/dev/null
		doas sysctl -q -p /etc/sysctl.d/40-no-ipv6.conf
		echo "IPv6 is off. Reload YouTube. (Undo: doas rm /etc/sysctl.d/40-no-ipv6.conf and reboot)"
	fi
fi
