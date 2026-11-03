#!/bin/bash
# Boot the custom kernel (Artix-mini) once on the next reboot.   fix mini
n=$(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{print substr($1,5,4); exit}')
[ -n "$n" ] || { echo "no Artix-mini boot entry (run: fix kernel)"; exit 1; }
doas efibootmgr -q -n "$n" && echo "Next boot: Artix-mini (once). Rebooting in 3 s, Ctrl+C to stay."
sleep 3 && doas reboot
