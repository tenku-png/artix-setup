#!/bin/bash
# Make the custom kernel (Artix-mini) the default boot entry.   fix keepmini
m=$(efibootmgr | awk '/ Artix-mini([[:space:]]|$)/{print substr($1,5,4); exit}')
[ -n "$m" ] || { echo "no Artix-mini entry"; exit 1; }
rest=$(efibootmgr | awk -F': ' '/^BootOrder/{print $2}' | tr ',' '\n' | grep -v "^$m$" | paste -sd,)
doas efibootmgr -q -o "$m${rest:+,$rest}" && echo "==> default boot: Artix-mini. zen (Artix) stays as a fallback in the BIOS boot menu / fix zen."
