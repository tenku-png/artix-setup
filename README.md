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
- GPU (NVIDIA proprietary / AMD / VM), network (DHCP or static)
- desktop (lilith, SwayFX or both) and optional groups

What it sets up: btrfs (`@`, `@home`, `@swap`, `@snapshots`, zstd),
linux-zen, EFISTUB boot entry (no GRUB), seatd, a single tty1 console,
doas, Artix lib32 + Arch extra/multilib, paru, the package groups from
`packages/`, swayfx 0.5.3 with the middle-drag patch, lilith from
`tenku-png/liwm`, PipeWire Clean Mic, polkit rules without an agent,
libvirt over its socket, AmneziaVPN as a dinit service.

After the first boot: log in on tty1 (the default compositor starts),
then run `~/first-login.sh` once (Sober).

### Recover an interrupted installation

From the Artix Live ISO, mount the existing Linux Btrfs root at `/mnt` using
its existing `@` subvolume, then mount the existing EFI partition at `/mnt/boot`.
Do not run the normal installer again. Download the current script and run:

```sh
curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/install.sh -o install.sh
bash install.sh --resume
```

Recovery resumes the package/configuration stages, including SwayFX, lilith,
and final configuration. It never partitions, formats, recreates Btrfs
subvolumes, changes `fstab`, recreates the user, or unmounts a device. It
preserves existing user configuration files. Saved choices are read from
`/mnt/root/.artix-setup-state`; older partial installs without a checkpoint
prompt for the existing username, compositor, and optional groups. Optional
package failures are logged to `/mnt/var/log/artix-setup-install.log` and
reported at the end; the next groups still run.

Before building wlroots0.19, the installer fetches Simon Ser's public key from
keys.openpgp.org and verifies the full fingerprint
`34FF9526CFEF0E97A340E2E40FDE7BE0E88F5E48`. Pacman/makepkg signature checks
remain enabled. The AmneziaVPN AUR build removes its upstream systemctl-only
service scriptlet calls; the installer uses the repository's dinit service.

For `target not found: wlroots0.19`: `wlroots0.19` is an AUR package, not an
Artix repository package. It was incorrectly listed as a repository dependency
and sent to `pacman`. Pinned SwayFX 0.5.3 uses `wlroots0.19` and `scenefx0.4`;
current upstream AUR SwayFX 0.6.1 instead targets `wlroots0.20` and `scenefx0.5`.
These versions must not be mixed.

This repository targets **dinit**, including service definitions and package
names.

### Repair package mirrors in a partial installation

Boot the Live ISO, mount the existing root at `/mnt`, then run:

```sh
bash install.sh --repair-mirrors
```

The installer probes current Artix mirror entries and three official fallback
mirrors for the `system.db` repository database, sorts reachable servers by
response time, removes any old custom downloader setting, then syncs repository
databases inside the mounted target with pacman's built-in downloader. Package
signature checks remain enabled. This repair mode does not format, repartition,
unmount, or install/remove packages; after a successful sync, retry the pacman
command that failed. A full installer run remains destructive to its selected
Linux root partition, so do not use it to resume a partial install.

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
