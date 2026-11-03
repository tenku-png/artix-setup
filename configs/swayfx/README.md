# SwayFX

`config` is the Hyprland setup ported to SwayFX (sway + blur/effects).

Install on Artix:

```sh
doas pacman -S --needed swayfx swaybg foot grim slurp wl-clipboard bemenu-wayland
mkdir -p ~/.config/sway && cp config ~/.config/sway/config
sway --validate
```

Start from a TTY (no elogind; seatd provides the seat):

```sh
export XDG_RUNTIME_DIR=/tmp/runtime-$USER XDG_CURRENT_DESKTOP=sway
mkdir -p -m 700 "$XDG_RUNTIME_DIR"
sway
```

On the PC with the proprietary NVIDIA driver start it with
`sway --unsupported-gpu`.

Differences from Hyprland:
- Super+S uses the sway scratchpad (floating overlay), not a tiled
  special workspace
- no maximize: Super+D toggles the tabbed layout instead
- no middle-button drag without a modifier: use Super+left drag
- dwindle needs `autotiling-rs` (commented out in the autostart)
