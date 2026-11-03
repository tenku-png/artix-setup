#!/bin/bash
# Make the zen kernel ("Artix") the default boot entry again.   fix zen
z=$(efibootmgr | awk '/ Artix([[:space:]]|$)/{print substr($1,5,4); exit}')
[ -n "$z" ] || { echo "no Artix boot entry found"; efibootmgr; exit 1; }
rest=$(efibootmgr | awk -F': ' '/^BootOrder/{print $2}' | tr ',' '\n' | grep -v "^$z$" | paste -sd,)
doas efibootmgr -q -o "$z${rest:+,$rest}" && echo "==> default boot: Artix (zen). Artix-mini stays in the BIOS boot menu."
echo "Reboot when ready: doas reboot"
