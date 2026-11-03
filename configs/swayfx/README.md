# SwayFX

`config` is the Hyprland setup ported to SwayFX (sway + blur/effects).

Install on Artix (built from AUR; the current AUR swayfx 0.6 needs
scenefx 0.5, which is not packaged yet):

```sh
doas pacman -S --needed swaybg foot grim slurp wl-clipboard bemenu-wayland
paru -S scenefx0.4
git clone https://aur.archlinux.org/swayfx.git /tmp/swayfx && cd /tmp/swayfx
git checkout -f 9add1cd          # swayfx 0.5.3, wlroots0.19
sed -i "s/'scenefx[^']*'/'scenefx0.4'/" PKGBUILD
sed -i 's/-Dsd-bus-provider=libsystemd/-Dtray=disabled/' PKGBUILD   # no systemd on Artix
makepkg -o                       # download and extract only
patch -d src/swayfx-0.5.3 -p1 < ~/artix-setup/configs/swayfx/middle-drag.patch
makepkg -ei                      # build the patched tree and install
mkdir -p ~/.config/sway && cp ~/artix-setup/configs/swayfx/config ~/.config/sway/config
sway --validate
```

`middle-drag.patch` makes a middle-button drag without modifiers move
windows (floating and tiled), like Hyprland's `mouse:274` bind.

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
- middle-button drag needs `middle-drag.patch` (applied in the build above)
- dwindle needs `autotiling-rs` (commented out in the autostart)
