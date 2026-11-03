# artix-setup

Minimal Artix Linux (dinit) with lilith and/or SwayFX, built for low RAM.

## Install

Boot the **Artix base ISO (dinit)** in **UEFI** mode, log in as root
(password `artix`), get network (`dinitctl start dhcpcd` if needed), then:

```sh
curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/install.sh -o install.sh
bash install.sh
```

Do not pipe it into `bash` (`curl | bash`): the script asks questions.

The installer asks for:
- **mode**: wipe a whole disk (clean VM) or use existing partitions. In
  partition mode only the chosen root partition is formatted; the EFI
  partition is reused without formatting unless you say so, and any other
  partition can be mounted at boot without being touched
  (e.g. `/dev/sda3:/mnt/ports`)
- swap file size (btrfs swapfile in the `@swap` subvolume)
- hostname, user, passwords, timezone (default `Asia/Novosibirsk`, GMT+7)
- GPU (NVIDIA proprietary / AMD / VM), network (DHCP or static)
- desktop (lilith, SwayFX or both) and optional groups

What it sets up: btrfs (`@`, `@home`, `@swap`, `@snapshots`, zstd),
linux-zen, EFISTUB boot entry (no GRUB), seatd, a single tty1 console,
doas, Artix lib32 + Arch extra/multilib, paru, the package groups from
`packages/`, swayfx 0.5.3 with the middle-drag patch, lilith from
`tenku-png/liwm`, PipeWire Clean Mic, polkit rules without an agent,
libvirt over its socket, AmneziaVPN as a dinit service.

After the first boot: log in on tty1 (the default compositor starts),
then run `~/first-login.sh` once (moegram, Sober).

## Layout

| Path | |
|---|---|
| `install.sh` | the installer |
| `packages/` | package groups (`aur:` prefix = AUR) |
| `bin/` | `start-wm`, `session-apps`, `clip-pick`, `mic-monitor`, `mem` |
| `dinit/` | services: single tty1, AmneziaVPN |
| `configs/` | swayfx, pipewire, polkit, libvirt |
| `kernel/` | module list of the desktop for a custom kernel (later) |

## Keys (both compositors)

Super+V clipboard history, Super+Shift+V emoji, Super+M hear yourself,
Super+R launcher, the rest follows the old Hyprland binds.
