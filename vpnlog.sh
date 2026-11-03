#!/bin/bash
# What AmneziaVPN is doing on this system.   fix vpnlog
set -u
b=$'\e[1m'; z=$'\e[0m'
echo "${b}== protocol (Amnezia container):${z}"
grep -rhoE '"(defaultContainer|container)"[^,]*' ~/.config/AmneziaVPN.ORG 2>/dev/null | sort -u | head -5 | sed 's/^/  /' ||
	echo "  config not found"
echo "${b}== tools Amnezia uses for routes/firewall:${z}"
for t in iptables ip6tables resolvconf ip nft; do
	printf '  %-11s %s\n' "$t" "$(command -v $t || echo MISSING)"
done
echo "${b}== interface:${z}"
ip -d link show amn0 2>/dev/null | head -3 | sed 's/^/  /' || echo "  amn0 not up"
echo "${b}== routes:${z}"
ip route | head -8 | sed 's/^/  /'
echo "${b}== DNS:${z} $(grep nameserver /etc/resolv.conf | tr '\n' ' ')"
echo "${b}== service log (last 15 lines):${z}"
doas tail -15 /var/log/amneziavpn.log 2>/dev/null | sed 's/^/  /'
echo "${b}== app log (last 10 lines):${z}"
f=$(ls -t ~/.local/share/AmneziaVPN.ORG/AmneziaVPN/log/* 2>/dev/null | head -1)
[ -n "$f" ] && tail -10 "$f" | cut -c1-160 | sed 's/^/  /' || echo "  none"
