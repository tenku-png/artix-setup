# Package groups

One file per group; the installer asks which optional groups to install.

| File | Contents |
|---|---|
| base.txt | base system, dinit services, doas |
| desktop.txt | shared Wayland desktop bits (terminal, launcher, screenshots, clipboard, notifications, thunar, fonts) |
| lilith.txt / swayfx.txt | compositor build deps |
| audio.txt | PipeWire (easyeffects replaced by configs/pipewire) |
| dev.txt | languages, toolchains, moegram build deps, lite-xl |
| android.txt, reverse.txt | Android and reverse engineering |
| games.txt | Steam; flatpak only for Sober (`flatpak install flathub org.vinegarhq.Sober`) |
| net.txt | network and archive tools; torrents via `aria2c file.torrent` |
| virt.txt | QEMU + virt-manager (libvirt group, no polkit agent) |
| printer.txt | optional printing/scanning |
| aur.txt | AUR packages via paru |

Not packaged: moegram (`curl -fsSL https://raw.githubusercontent.com/tenku-png/moegram/main/install.sh | sh`),
Claude Code and other CLI tools the user installs.

Dropped from the Arch setup: hyprland stack, quickshell/noctalia/matugen,
awww/mpvpaper, uwsm, ly, wofi, polkit-kde-agent, ufw, zram-generator,
reflector, bluez, ananicy, nss-mdns, GNOME apps, chromium/librewolf,
telegram-desktop, spotify, qbittorrent, obs-studio, onlyoffice, AI desktop
apps, happ, easyeffects, sudo.
