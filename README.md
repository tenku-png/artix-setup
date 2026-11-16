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

Nothing is changed until the end: disks and partitions are picked from a
numbered list, then a plan shows every partition as ERASE / keep / mount,
and you must type the name of what gets erased (e.g. `sda4`) to start.
Try it safely first:

```sh
bash install.sh --dry-run     # asks everything, prints the plan, changes nothing
```

The installer asks for:
- **mode**: wipe a whole disk (clean VM) or use existing partitions. In
  partition mode only the chosen root partition is formatted; the EFI
  partition is reused without formatting unless you say so, and any other
  partition can be mounted at boot without being touched
  (e.g. `/dev/sda3:/mnt/ports`)
- swap file size (btrfs swapfile in the `@swap` subvolume)
- hostname, user, passwords, timezone
- GPU (AMD RX 6650 XT / other or VM), network (DHCP or static)
- desktop (lilith, SwayFX or both) and optional groups

What it sets up: btrfs (`@`, `@home`, `@swap`, `@snapshots`, zstd),
linux-zen, EFISTUB boot entry (no GRUB), seatd, a single tty1 console,
doas, Artix lib32 + Arch extra/multilib, paru, the package groups from
`packages/`, swayfx 0.5.3 with the middle-drag patch, lilith from
`tenku-png/liwm`, PipeWire Clean Mic, polkit rules without an agent,
libvirt over its socket, and optional AmneziaWG kernel support with a dinit
tunnel service. No Amnezia GUI app is installed by this option.

When AmneziaWG is selected, the installer adds `amneziawg-dkms`,
`amneziawg-tools`, and `openresolv`. Mount the USB at `/mnt/usb` in the live
ISO; the profile path prompt defaults to
`/mnt/usb/amnz hoist.conf` and also accepts the Amnezia
`.backup` file. The installer validates/extracts it into a mode-`0600` temporary
file before formatting, removes that temporary file on exit, stores the profile
as `/etc/amnezia/amneziawg/awg0.conf` with mode `0600`, and enables the dinit
tunnel at boot. No GUI app is installed. If the profile is unavailable during
installation, run `fix awg /path/to/profile.conf` after first boot. The
profile's key is never put in the repository; `.gitignore` and the pre-commit
scanner also cover Amnezia config and backup filenames.

After the first boot: log in on tty1 (the default compositor starts),
then run `~/first-login.sh` once (Sober).

## Custom kernel

See [`kernel/README.md`](kernel/README.md) for the `linux-mini` build, checks,
and safe installation flow. A normal `./kernel.sh` only builds and verifies
artifacts; `./kernel.sh --install` asks before installing alongside zen and
never changes bootloader entries or boot order.

## Repository privacy checks

The committed `kernel/modprobed.db` lists modules used on one desktop and can
reveal hardware details. Review it before reusing or sharing this repository.
To enable the repository's pre-commit secret scan in a clone:

```sh
git config core.hooksPath .githooks
```

The hook scans staged files for common private-key blocks, WireGuard private
keys, provider tokens and credential assignments. It is a guardrail, not a
replacement for reviewing changes before publishing. GitHub also publishes the
author email recorded in each commit; if you want to keep a personal address
private, select the GitHub-provided noreply address in
[email settings](https://github.com/settings/emails) and set it locally with
`git config user.email` before creating future commits.

## Layout

| Path | |
|---|---|
| `install.sh` | the installer |
| `packages/` | package groups (`aur:` prefix = AUR) |
| `bin/` | `start-wm`, `session-apps`, `clip-pick`, `mic-monitor`, `mem` |
| `dinit/` | services: tty1, AmneziaWG module and optional tunnel autostart |
| `configs/` | swayfx, pipewire, polkit, libvirt |
| `kernel/` | safe custom-kernel build, artifact checks, and module inventory |

## Keys (both compositors)

Super+V clipboard history, Super+Shift+V emoji, Super+M hear yourself,
Super+R launcher, the rest follows the old Hyprland binds.
