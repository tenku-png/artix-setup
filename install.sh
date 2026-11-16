#!/bin/bash
# Artix (dinit) installer: minimal base + lilith and/or SwayFX desktop.
# Run as root from the Artix base ISO (dinit):
#   curl -fsSL https://raw.githubusercontent.com/tenku-png/artix-setup/main/install.sh -o install.sh
#   bash install.sh
set -euo pipefail

REPO_URL=https://github.com/tenku-png/artix-setup
LIWM_URL=https://github.com/tenku-png/liwm
LIWM_BRANCH=stable          # tested build; new features land in hyprland-config first
SWAYFX_AUR_COMMIT=9add1cd   # swayfx 0.5.3 (wlroots0.19, scenefx0.4)
MNT=/mnt

# ---------------------------------------------------------------- helpers
DRY_RUN=n; [ "${1:-}" = "--dry-run" ] && DRY_RUN=y
RESUME_INSTALL=n
case "${1:-}" in --resume|--resume-swayfx) RESUME_INSTALL=y ;; esac
MIRRORS_ONLY=n; [ "${1:-}" = "--repair-mirrors" ] && MIRRORS_ONLY=y
c_b=$'\e[1m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_c=$'\e[36m'; c_0=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$c_g$c_b" "$c_0" "$*"; }
warn() { printf '%s==> %s%s\n' "$c_y" "$*" "$c_0" >&2; }
die()  { printf '%s==> %s%s\n' "$c_r" "$*" "$c_0" >&2; exit 1; }
step() { printf '\n%s=== %s ===%s\n' "$c_c$c_b" "$*" "$c_0" >&2; }
ask()  { local a; read -rp "$1 [${2:-}]: " a; printf '%s' "${a:-${2:-}}"; }
yes_no() { # yes_no "question" y|n
	local a def=$2
	read -rp "$1 [$([ "$def" = y ] && echo Y/n || echo y/N)]: " a
	a=${a:-$def}; [[ $a =~ ^[Yy] ]]
}
ask_pass() {
	local p1 p2
	while :; do
		read -rsp "$1: " p1; echo >&2
		read -rsp "repeat: " p2; echo >&2
		[ -n "$p1" ] && [ "$p1" = "$p2" ] && { printf '%s' "$p1"; return; }
		warn "password is empty or does not match, try again"
	done
}
# pick "title" item... -> prints the chosen item (menu goes to stderr)
pick() {
	local title=$1; shift
	local items=("$@") i n
	[ ${#items[@]} -gt 0 ] || die "nothing to choose from: $title"
	echo "$title" >&2
	for i in "${!items[@]}"; do printf '  %s%2d)%s %s\n' "$c_b" $((i+1)) "$c_0" "$(describe "${items[$i]}")" >&2; done
	while :; do
		read -rp "Number: " n
		[[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#items[@]} ] && { printf '%s' "${items[$((n-1))]}"; return; }
		warn "enter a number from 1 to ${#items[@]}"
	done
}
# "/dev/sda4  306G  btrfs  'label'  (now: /)"
describe() {
	local d=$1 size fs label mnt model
	size=$(lsblk -dno SIZE "$d" | tr -d ' ')
	if [ "$(lsblk -dno TYPE "$d")" = disk ]; then
		model=$(lsblk -dno MODEL "$d" | sed 's/ *$//')
		printf '%-12s %7s  disk %s' "$d" "$size" "${model:+($model)}"
	else
		fs=$(lsblk -dno FSTYPE "$d"); label=$(lsblk -dno LABEL "$d"); mnt=$(lsblk -dno MOUNTPOINTS "$d" | head -1)
		printf '%-12s %7s  %-6s %s%s' "$d" "$size" "${fs:-empty}" "${label:+\"$label\" }" "${mnt:+(now: $mnt)}"
	fi
}
part_dev() { case $1 in *nvme*|*mmcblk*|*loop*) echo "${1}p$2" ;; *) echo "${1}$2" ;; esac; }
in_chroot() { artix-chroot "$MNT" /bin/bash -euo pipefail -c "$1"; }
retry() { local i; for i in 1 2 3; do "$@" && return 0; warn "failed (try $i/3), retrying..."; sleep 3; done; return 1; }
as_user()   { artix-chroot "$MNT" /bin/su -s /bin/bash - "$USERNAME" -c "set -euo pipefail; $1"; }
link() { ln -sf "/etc/dinit.d/$1" "$MNT/etc/dinit.d/boot.d/$1"; }
# Read a package group file: prints "repo" or "aur" packages
pkgs() { # pkgs file repo|aur
	sed 's/#.*//' "$REPO/packages/$1" | tr -s ' \t' '\n' | sed '/^$/d' |
	if [ "$2" = aur ]; then sed -n 's/^aur://p'; else grep -v '^aur:' || true; fi
}
save_resume_state() {
	STATE_FILE="$MNT/root/.artix-setup-state"
	{
		printf '# Non-secret choices for safe package-stage recovery.\n'
		declare -p USERNAME GPU WMSEL DEFAULT_WM OPT AMNEZIA SSHD
	} > "$STATE_FILE.tmp"
	chmod 600 "$STATE_FILE.tmp"
	mv "$STATE_FILE.tmp" "$STATE_FILE"
}
WLROOTS_SIGNING_FPR=34FF9526CFEF0E97A340E2E40FDE7BE0E88F5E48
prepare_wlroots_signing_key() {
	local keyfile="$MNT/tmp/wlroots-0.19-signing-key.asc" actual
	say "Fetching and verifying wlroots signing key fingerprint"
	mkdir -p "$MNT/tmp"
	curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
		"https://keys.openpgp.org/vks/v1/by-fingerprint/$WLROOTS_SIGNING_FPR" -o "$keyfile" ||
		die "Could not fetch the wlroots signing key from keys.openpgp.org."
	actual=$(artix-chroot "$MNT" /usr/bin/gpg --batch --show-keys --with-colons /tmp/wlroots-0.19-signing-key.asc |
		awk -F: '$1 == "fpr" {print $10; exit}')
	[ "$actual" = "$WLROOTS_SIGNING_FPR" ] ||
		die "wlroots signing key fingerprint mismatch (expected $WLROOTS_SIGNING_FPR, got ${actual:-none})."
	as_user "install -d -m 700 ~/.gnupg && gpg --batch --import /tmp/wlroots-0.19-signing-key.asc"
}

# Probe Artix repository databases and put the fastest working mirrors first.
# Pacman still verifies package signatures; curl here only downloads files.
prepare_artix_mirrors() { # pacman root (/, or /mnt)
	local root=$1 list="$1/etc/pacman.d/mirrorlist" tmp raw server probe elapsed
	[ -f "$list" ] || die "Artix mirror list not found: $list"
	tmp=$(mktemp)
	{
		awk '$1 == "Server" {print $3; n++; if (n == 5) exit}' "$list"
		printf '%s\n' \
			'https://mirror1.artixlinux.org/repos/$repo/os/$arch' \
			'https://mirror2.artixlinux.org/repos/$repo/os/$arch' \
			'https://mirror3.artixlinux.org/repos/$repo/os/$arch'
	} | sed 's/#.*//' | sed '/^[[:space:]]*$/d' | sort -u > "$tmp.input"
	say "Checking Artix mirrors in parallel (up to 6 seconds)..."
	while IFS= read -r raw; do
		server=${raw//\$repo/system}; server=${server//\$arch/x86_64}
		probe=${server%/}/system.db
		(
			if elapsed=$(curl -fsSL --connect-timeout 3 --max-time 6 -o /dev/null \
				-w '%{time_total}' "$probe" 2>/dev/null); then
				printf '%s\t%s\n' "$elapsed" "$raw" >> "$tmp"
			fi
		) &
	done < "$tmp.input"
	wait
	rm -f "$tmp.input"
	[ -s "$tmp" ] || { rm -f "$tmp"; die "No Artix mirrors passed the system.db check. Check network/DNS; no mass package install was started."; }
	{
		sort -n "$tmp" | sed -n '1,6p' | cut -f2- | while IFS= read -r server; do
			printf 'Server = %s\n' "$server"
		done
	} > "$list.new"
	mv "$list.new" "$list"
	rm -f "$tmp"
	# Drop the previously configured curl XferCommand and restore pacman's
	# built-in downloader for this root.
	[ ! -f "$root/etc/pacman.conf" ] || sed -i '/^XferCommand[[:space:]]*=/d' "$root/etc/pacman.conf"
	say "Artix mirrors ready (fastest reachable mirrors first): $(sed -n 's/^Server = //p' "$list" | paste -sd ' ' -)"
}

# ---------------------------------------------------------------- checks
[ "$(id -u)" = 0 ] || die "run as root"
[ -d /sys/firmware/efi/efivars ] || die "not booted in UEFI mode (enable UEFI in the VM/PC firmware settings)"
command -v basestrap >/dev/null || die "basestrap not found: run this from the Artix ISO"
# HTTPS check (ping/ICMP is blocked on some networks even when the web works)
curl -fsS --max-time 15 -o /dev/null https://github.com 2>/dev/null ||
	curl -fsS --max-time 15 -o /dev/null https://artixlinux.org 2>/dev/null ||
	die "no network (try: dinitctl start dhcpcd)"

prepare_artix_mirrors /
retry pacman -Syy --needed --noconfirm git || die "Live ISO package sync failed after mirror retries; see pacman output above."
# A stalled connection makes git hang forever; abort slow transfers after
# 20 s so retry() can try again (also written to the new system below)
GITCONF='[http]
	version = HTTP/1.1
	lowSpeedLimit = 1000
	lowSpeedTime = 20'
printf '%s\n' "$GITCONF" > /etc/gitconfig
if [ -f "$(dirname "$0")/packages/base.txt" ]; then
	REPO=$(cd "$(dirname "$0")" && pwd)
else
	REPO=/tmp/artix-setup
	rm -rf "$REPO"
	retry git clone --depth 1 "$REPO_URL" "$REPO"
fi

# Repair package sources in an already installed target, without running any
# installation, mount, partition, or format steps.
if [ "$MIRRORS_ONLY" = y ]; then
	[ -f "$MNT/etc/pacman.conf" ] || die "mount the existing installed root at /mnt first"
	prepare_artix_mirrors "$MNT"
	in_chroot "pacman -Syy" || die "Repository database sync failed. Review the mirror list and network above; no packages were changed."
	say "Repository databases synced. You can retry the package command that failed; installed packages and disks were not changed."
	exit 0
fi

if [ "$RESUME_INSTALL" = y ]; then
	mountpoint -q "$MNT" || die "$MNT is not a mountpoint; mount the existing Artix root there before resuming"
	[ -f "$MNT/etc/pacman.conf" ] || die "mount the existing installed root at /mnt first"
	[ -x "$MNT/usr/bin/pacman" ] || die "installed pacman not found under /mnt"
	STATE_FILE="$MNT/root/.artix-setup-state"
	if [ -f "$STATE_FILE" ]; then
		# State contains only setup choices, never passwords.
		. "$STATE_FILE"
		say "Restored installer choices from $STATE_FILE"
	else
		warn "No checkpoint exists (this installation started before checkpoints were added); repeat a few choices. Existing users, files and packages will be kept."
		mapfile -t EXISTING_USERS < <(find "$MNT/home" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^lost+found$' || true)
		USERNAME=$(ask "Existing username" "${EXISTING_USERS[0]:-}")
		[ -n "$USERNAME" ] && [ -d "$MNT/home/$USERNAME" ] || die "user home not found under $MNT/home"
		HOST=$(cat "$MNT/etc/hostname" 2>/dev/null || echo artix)
		GPU=$(ask "GPU (1 NVIDIA, 2 AMD, 3 other/VM)" 1)
		echo "Desktop selection: 1 lilith, 2 SwayFX, 3 both" >&2
		WMSEL=$(ask "Desktop" 3)
		DEFAULT_WM=$(ask "Default compositor (lilith/sway)" "$([ "$WMSEL" = 2 ] && echo sway || echo lilith)")
		declare -A OPT
		for g in dev android reverse games virt printer; do
			def=n; [ "$g" = android ] && def=y
			yes_no "Retry optional package group: $g?" "$def" && OPT[$g]=y || OPT[$g]=n
		done
		AMNEZIA=n; yes_no "Install AmneziaVPN?" n && AMNEZIA=y
		SSHD=n; yes_no "Install SSH server?" n && SSHD=y
		save_resume_state
	fi
	[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "invalid saved username"
	[ -d "$MNT/home/$USERNAME" ] || die "saved user home is missing: $MNT/home/$USERNAME"
	artix-chroot "$MNT" id "$USERNAME" >/dev/null 2>&1 || die "saved user does not exist in the installed system"
	case "$GPU" in 1|2|3) ;; *) die "invalid saved GPU selection: $GPU" ;; esac
	case "$WMSEL" in 1|2|3) ;; *) die "invalid saved desktop selection: $WMSEL" ;; esac
	case "$DEFAULT_WM" in lilith|sway) ;; *) die "invalid saved default compositor: $DEFAULT_WM" ;; esac
	for g in dev android reverse games virt printer; do
		case "${OPT[$g]:-n}" in y|n) ;; *) die "invalid saved package selection for $g" ;; esac
	done
	prepare_artix_mirrors "$MNT"
	in_chroot "pacman -Syy" || die "Target repository database sync failed; no install stage was resumed."
fi

# Disk the ISO was booted from: never offered for wiping
if [ "$RESUME_INSTALL" != y ]; then
ISO_DISK=
src=$(findmnt -no SOURCE /run/artix/bootmnt 2>/dev/null || true)
# Walk up to the physical disk: also works for Ventoy (/dev/mapper/ventoy)
[ -n "$src" ] && ISO_DISK=$(lsblk -nspo NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk"{print $1; exit}')
mapfile -t DISKS < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v -e zram -e loop | grep -vx "${ISO_DISK:-NONE}" || true)
mapfile -t PARTS < <(lsblk -pnlo NAME,TYPE | awk '$2=="part"{print $1}' | grep -v "^${ISO_DISK:-NONE}" || true)

clear 2>/dev/null || true
cat <<EOF
${c_b}Artix (dinit) + lilith / SwayFX installer${c_0}

First come only questions. ${c_b}Nothing is changed${c_0} until the very end:
you will see a plan (what gets erased, what stays) and have to
confirm it. You can quit any time with Ctrl+C.
$( [ "$DRY_RUN" = y ] && echo "${c_y}Dry run (--dry-run): the script exits after showing the plan.${c_0}" )
EOF

# ---------------------------------------------------------------- questions
step "Step 1/5: where to install"
echo "Your disks and partitions:" >&2
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS >&2
cat >&2 <<EOF

  ${c_b}1)${c_0} Erase a ${c_r}WHOLE disk${c_0} (clean VM or empty disk)
  ${c_b}2)${c_0} Install into ${c_g}one partition${c_0}, leave all other partitions alone (PC)
EOF
MODE=$(ask "Choice" 2)
if [ "$MODE" != 1 ] && [ ${#PARTS[@]} -eq 0 ]; then
	warn "There are no partitions yet (empty disk), so option 2 has nothing to use."
	yes_no "Erase a whole disk instead (option 1)?" y && MODE=1 || die "nothing to do; create partitions first or choose option 1"
fi

if [ "$MODE" = 1 ]; then
	DISK=$(pick "Which disk should be erased completely?" "${DISKS[@]}")
	echo "This disk currently contains:" >&2; lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK" >&2
	EFI=$(part_dev "$DISK" 1); ROOT=$(part_dev "$DISK" 2); FORMAT_EFI=y
else
	EFI_CAND=(); for p in "${PARTS[@]}"; do [ "$(lsblk -dno FSTYPE "$p")" = vfat ] && EFI_CAND+=("$p"); done
	[ ${#EFI_CAND[@]} -gt 0 ] || EFI_CAND=("${PARTS[@]}")
	EFI=$(pick "EFI boot partition (small, FAT32, ~1 GB):" "${EFI_CAND[@]}")
	ROOT_CAND=(); for p in "${PARTS[@]}"; do [ "$p" != "$EFI" ] && ROOT_CAND+=("$p"); done
	ROOT=$(pick "Partition to install the system into? ${c_r}It will be completely erased.${c_0}" "${ROOT_CAND[@]}")
	fs=$(lsblk -dno FSTYPE "$ROOT")
	[ -n "$fs" ] && warn "$ROOT currently holds a $fs filesystem. Every file on it will be lost."
	FORMAT_EFI=n
	echo "The EFI partition is ${c_g}not formatted${c_0}: other bootloaders on it stay." >&2
	yes_no "Format the EFI partition anyway? (usually not needed)" n && FORMAT_EFI=y

	EXTRA_MOUNTS=()
	echo >&2; echo "Other partitions are ${c_g}left alone${c_0}. You can mount them at boot (no formatting):" >&2
	for p in "${PARTS[@]}"; do
		[ "$p" = "$EFI" ] || [ "$p" = "$ROOT" ] && continue
		[ -n "$(lsblk -dno FSTYPE "$p")" ] || continue
		if yes_no "  Mount $(describe "$p")?" n; then
			label=$(lsblk -dno LABEL "$p")
			dir=$(ask "    Mount point" "/mnt/${label:-$(basename "$p")}")
			EXTRA_MOUNTS+=("$p:$dir")
		fi
	done
fi
EXTRA_MOUNTS=("${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"}")

SWAP_GB=$(ask "Swap size in GB (0 = no swap; 8 is good for Minecraft)" 8)
[[ $SWAP_GB =~ ^[0-9]+$ ]] || die "swap size must be a number"

step "Step 2/5: user"
HOST=$(ask "Hostname" "")
[ -n "$HOST" ] || die "hostname is required"
USERNAME=$(ask "Username" "")
[ -n "$USERNAME" ] || die "username is required"
TIMEZONE=$(ask "Timezone (e.g. Europe/Berlin)" "")
[ -n "$TIMEZONE" ] && [ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "unknown timezone: ${TIMEZONE:-empty} (see ls /usr/share/zoneinfo)"
ROOT_PASS=$(ask_pass "root password")
USER_PASS=$(ask_pass "$USERNAME password")

step "Step 3/5: hardware and network"
echo "GPU: 1) NVIDIA  2) AMD  3) other / virtual machine" >&2
GPU=$(ask "GPU" 1)
echo "Network: 1) automatic (DHCP)  2) static IP" >&2
NET=$(ask "Network" 1)
if [ "$NET" = 2 ]; then
	IFACE=$(ask "Interface" "$(ip -o link | awk -F': ' '$2!="lo"{print $2; exit}')")
	ADDR=$(ask "Address/prefix" 192.168.1.50/24)
	GW=$(ask "Gateway" 192.168.1.1)
	DNS=$(ask "DNS" 1.1.1.1)
fi

echo "Mirror for Arch packages (Steam, ghidra, ...): 1) default list  2) mirror.yandex.ru  3) mirror.truenetwork.ru  4) other URL" >&2
case $(ask "Mirror" 2) in
	2) ARCH_MIRROR='https://mirror.yandex.ru/archlinux/$repo/os/$arch' ;;
	3) ARCH_MIRROR='https://mirror.truenetwork.ru/archlinux/$repo/os/$arch' ;;
	4) ARCH_MIRROR=$(ask "Server URL (with \$repo/os/\$arch)" "") ;;
	*) ARCH_MIRROR= ;;
esac

step "Step 4/5: desktop"
echo "1) lilith (lightest)  2) SwayFX (blur, tiling)  3) both" >&2
WMSEL=$(ask "Desktop" 3)
DEFAULT_WM=lilith; [ "$WMSEL" = 2 ] && DEFAULT_WM=sway
[ "$WMSEL" = 3 ] && DEFAULT_WM=$(ask "Start after login (lilith/sway)" lilith)

step "Step 5/5: software"
declare -A OPT
for g in dev android reverse games virt printer; do OPT[$g]=n; done
yes_no "Development (languages, C++/Qt build deps, lite-xl)?" y && OPT[dev]=y
yes_no "Android (Studio, adb, scrcpy, jadx, apktool)?"         y && OPT[android]=y
yes_no "Reverse engineering (ghidra, il2cpp-dumper)?"          y && OPT[reverse]=y
yes_no "Games (Steam, Prism Launcher, Flatpak + Sober)?"       y && OPT[games]=y
yes_no "Virtual machines (QEMU + virt-manager)?"               y && OPT[virt]=y
yes_no "Printer/scanner (only started when needed)?"           n && OPT[printer]=y
AMNEZIA=n; yes_no "AmneziaVPN?" y && AMNEZIA=y
SSHD=n; yes_no "SSH server (log in to this machine over the network)?" n && SSHD=y

# ---------------------------------------------------------------- plan
step "Plan"
echo "${c_b}Disks:${c_0}"
for d in $(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v -e zram -e loop); do
	if [ "$MODE" = 1 ] && [ "$d" = "$DISK" ]; then
		printf '  %s%-12s ERASE WHOLE DISK%s -> EFI 1 GB + system (btrfs)\n' "$c_r$c_b" "$d" "$c_0"; continue
	fi
	printf '  %s\n' "$(describe "$d")"
	for p in $(lsblk -pnlo NAME,TYPE "$d" | awk '$2=="part"{print $1}'); do
		act="${c_g}leave alone${c_0}"
		[ "$p" = "$ROOT" ] && act="${c_r}${c_b}ERASE${c_0}${c_r} -> Artix system (btrfs)${c_0}"
		if [ "$p" = "$EFI" ]; then
			if [ "$FORMAT_EFI" = y ]; then act="${c_r}${c_b}ERASE${c_0}${c_r} -> new EFI${c_0}"; else act="${c_g}keep${c_0}, add Artix boot entry"; fi
		fi
		for m in "${EXTRA_MOUNTS[@]}"; do [ "${m%%:*}" = "$p" ] && act="${c_g}leave alone${c_0}, mount at ${m#*:}"; done
		printf '     %-48s %s\n' "$(describe "$p")" "$act"
	done
done
cat <<EOF

${c_b}System:${c_0} $HOST, user $USERNAME, timezone $TIMEZONE, swap ${SWAP_GB} GB
${c_b}Desktop:${c_0} $(case $WMSEL in 1) echo lilith;; 2) echo SwayFX;; *) echo "lilith + SwayFX";; esac), starts: $DEFAULT_WM
${c_b}GPU:${c_0} $(case $GPU in 1) echo NVIDIA;; 2) echo AMD;; *) echo "other/VM";; esac)   ${c_b}Network:${c_0} $([ "$NET" = 1 ] && echo DHCP || echo "static $ADDR")
${c_b}Groups:${c_0} $(for g in dev android reverse games virt printer; do [ "${OPT[$g]}" = y ] && printf '%s ' "$g"; done)$([ "$AMNEZIA" = y ] && printf 'amnezia ')$([ "$SSHD" = y ] && printf 'sshd')
EOF

[ "$DRY_RUN" = y ] && { say "Dry run: nothing was changed."; exit 0; }

TARGET=$([ "$MODE" = 1 ] && basename "$DISK" || basename "$ROOT")
echo
echo "${c_r}${c_b}To confirm, type the name of what will be erased: $TARGET${c_0}"
echo "(anything else cancels, nothing will be changed)"
[ "$(ask "Erase" "")" = "$TARGET" ] || die "cancelled, nothing was changed"
for i in 5 4 3 2 1; do printf '\rStarting in %s... (Ctrl+C to cancel) ' "$i"; sleep 1; done; echo

# ---------------------------------------------------------------- disks
say "Partitioning and formatting"
# Leftovers from an earlier (failed) run keep the disk busy
swapoff -a 2>/dev/null || true
umount -R "$MNT" 2>/dev/null || true
if [ "$MODE" = 1 ]; then
	wipefs -af "$DISK"
	sfdisk "$DISK" <<-EOF
	label: gpt
	size=1G, type=U
	type=L
	EOF
	partprobe "$DISK" 2>/dev/null || true; sleep 1
fi
[ "$FORMAT_EFI" = y ] && mkfs.fat -F32 "$EFI"
mkfs.btrfs -f -L artix "$ROOT"

mount "$ROOT" "$MNT"
for sv in @ @home @swap @snapshots; do btrfs subvolume create "$MNT/$sv"; done
umount "$MNT"
O=noatime,compress=zstd:1,space_cache=v2
mount -o "subvol=@,$O" "$ROOT" "$MNT"
mount --mkdir -o "subvol=@home,$O" "$ROOT" "$MNT/home"
mount --mkdir -o "subvol=@snapshots,$O" "$ROOT" "$MNT/.snapshots"
mount --mkdir -o "subvol=@swap,noatime" "$ROOT" "$MNT/swap"
mount --mkdir "$EFI" "$MNT/boot"
# Kernels/microcode left by a previous Linux on a reused EFI partition
# clash with the new packages: move them aside (not deleted)
old=$(cd "$MNT/boot" && ls -d vmlinuz-* initramfs-* amd-ucode.img intel-ucode.img 2>/dev/null || true)
if [ -n "$old" ]; then
	mkdir -p "$MNT/boot/old-linux"
	for f in $old; do mv "$MNT/boot/$f" "$MNT/boot/old-linux/"; done
	warn "moved old kernel files on the EFI partition to /boot/old-linux: $(echo $old)"
fi
if [ "$SWAP_GB" -gt 0 ]; then
	btrfs filesystem mkswapfile --size "${SWAP_GB}g" "$MNT/swap/swapfile"
	swapon "$MNT/swap/swapfile"
fi
for m in "${EXTRA_MOUNTS[@]}"; do mkdir -p "$MNT${m#*:}"; done

# ---------------------------------------------------------------- base
say "Installing the base system"
UCODE=amd-ucode; grep -q GenuineIntel /proc/cpuinfo && UCODE=intel-ucode
BASE=(base base-devel dinit linux-zen linux-zen-headers linux-firmware "$UCODE"
	mkinitcpio btrfs-progs dosfstools efibootmgr seatd-dinit dbus-dinit
	opendoas nano git)
[ "$NET" = 1 ] && BASE+=(dhcpcd-dinit)
[ "$SSHD" = y ] && BASE+=(openssh openssh-dinit)
retry basestrap "$MNT" "${BASE[@]}"
fstabgen -U "$MNT" >> "$MNT/etc/fstab"
for m in "${EXTRA_MOUNTS[@]}"; do
	dev=${m%%:*}; dir=${m#*:}
	uuid=$(blkid -s UUID -o value "$dev"); fs=$(blkid -s TYPE -o value "$dev")
	sed -i "\|[[:space:]]${dir}[[:space:]]|d" "$MNT/etc/fstab"
	echo "UUID=$uuid  $dir  $fs  defaults,nofail,noatime  0 2" >> "$MNT/etc/fstab"
done
# swap is added by fstabgen when active; make sure the path is right
if [ "$SWAP_GB" -gt 0 ] && ! grep -q '/swap/swapfile' "$MNT/etc/fstab"; then
	echo "/swap/swapfile none swap defaults 0 0" >> "$MNT/etc/fstab"
fi

say "Configuring the system"
in_chroot "
	ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && hwclock --systohc
	printf 'en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8\n' > /etc/locale.gen && locale-gen
	echo LANG=en_US.UTF-8 > /etc/locale.conf
	echo '$HOST' > /etc/hostname
	printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOST\n' > /etc/hosts
	useradd -m -G wheel,video,input,audio,seat '$USERNAME'
"
printf 'root:%s\n%s:%s\n' "$ROOT_PASS" "$USERNAME" "$USER_PASS" | artix-chroot "$MNT" chpasswd
# doas: persistent for wheel; temporarily passwordless for the install
printf '%s\n' "$GITCONF" > "$MNT/etc/gitconfig"
printf 'permit persist :wheel\npermit nopass %s\n' "$USERNAME" > "$MNT/etc/doas.conf"
chmod 600 "$MNT/etc/doas.conf"
echo 'PACMAN_AUTH=(doas)' >> "$MNT/etc/makepkg.conf"
sed -i "s/^#\?MAKEFLAGS=.*/MAKEFLAGS=\"-j$(nproc)\"/" "$MNT/etc/makepkg.conf"

# Repositories: Artix lib32 + Arch extra/multilib (Steam, many desktop packages)
say "Enabling lib32 and Arch repositories"
prepare_artix_mirrors "$MNT"
sed -i '/^#\[lib32\]/{s/^#//;n;s/^#//}' "$MNT/etc/pacman.conf"
in_chroot "pacman -Syy --needed --noconfirm artix-archlinux-support" || die "Could not sync/install Artix repository support; see mirror diagnostics above."
[ -n "$ARCH_MIRROR" ] && sed -i "1i Server = $ARCH_MIRROR" "$MNT/etc/pacman.d/mirrorlist-arch"
grep -q '^\[extra\]' "$MNT/etc/pacman.conf" || cat >> "$MNT/etc/pacman.conf" <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
in_chroot "pacman-key --populate archlinux && pacman -Syyu --noconfirm" || die "Target repositories failed preflight/update; package installation stopped before desktop package groups."

# ---------------------------------------------------------------- boot
say "Boot entry (EFISTUB, no GRUB)"
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
EFI_DISK=/dev/$(lsblk -no PKNAME "$EFI" | head -1)
EFI_NUM=$(cat "/sys/class/block/$(basename "$EFI")/partition")
# "ro": dinit-rc's root-ro service remounts / read-only early in boot; on a
# root already mounted rw (Btrfs) that fails with EBUSY (mount exit 32) and
# takes down early-root-rw.target and the whole boot. root-rw remounts rw later.
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=@ ro quiet loglevel=3"
[ "$GPU" = 1 ] && CMDLINE+=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
in_chroot "efibootmgr --create --disk $EFI_DISK --part $EFI_NUM --label 'Artix' \
	--loader /vmlinuz-linux-zen \
	--unicode '$CMDLINE initrd=\\$UCODE.img initrd=\\initramfs-linux-zen.img'"

# Preflight: verify the boot configuration before the user reboots
say "Checking boot configuration"
grep -qw ro <<<"$CMDLINE" && ! grep -qw rw <<<"$CMDLINE" || die "kernel cmdline must use 'ro' (dinit root-ro/root-rw), got: $CMDLINE"
[ "$(awk '$1!~/^#/ && $2=="/"' "$MNT/etc/fstab" | wc -l)" = 1 ] || die "/etc/fstab must contain exactly one entry for /"
grep -q "^UUID=$ROOT_UUID[[:space:]]\+/[[:space:]]" "$MNT/etc/fstab" || die "/etc/fstab root UUID does not match $ROOT_UUID"
for f in vmlinuz-linux-zen initramfs-linux-zen.img "$UCODE.img"; do
	[ -s "$MNT/boot/$f" ] || die "missing /boot/$f on the EFI partition"
done
efibootmgr -v | grep -F "$ROOT_UUID" | grep -qw ro || die "EFI boot entry with root=UUID=$ROOT_UUID and 'ro' not found"
in_chroot "dinit-check boot" || die "dinit-check boot reported problems"

# ---------------------------------------------------------------- services
say "Services"
cp "$REPO/dinit/agetty" "$REPO/dinit/tty1" "$MNT/etc/dinit.d/"
link() { ln -sf "/etc/dinit.d/$1" "$MNT/etc/dinit.d/boot.d/$1"; }
link tty1; link seatd; link dbus
[ "$SSHD" = y ] && link sshd
if [ "$NET" = 1 ]; then
	link dhcpcd
else
	cat > "$MNT/etc/dinit.d/staticnet" <<-EOF
	type      = scripted
	command   = /etc/dinit.d/staticnet.sh
	waits-for = udev-settle
	EOF
	cat > "$MNT/etc/dinit.d/staticnet.sh" <<-EOF
	#!/bin/sh
	i=0; while [ ! -e /sys/class/net/$IFACE ] && [ \$i -lt 50 ]; do sleep 0.1; i=\$((i+1)); done
	ip link set lo up
	ip link set $IFACE up
	ip addr replace $ADDR dev $IFACE
	ip route replace default via $GW
	exit 0
	EOF
	chmod +x "$MNT/etc/dinit.d/staticnet.sh"
	echo "nameserver $DNS" > "$MNT/etc/resolv.conf"
	link staticnet
fi

# ---------------------------------------------------------------- packages
save_resume_state
fi

# Package phase is safe to repeat: all pacman calls use --needed, and the
# --resume path skips disk, base, user, boot, and service setup entirely.
install_group() { # install_group group [optional]; returns failure, never exits
	local p; p=$(pkgs "$1" repo | tr '\n' ' ')
	[ -n "$p" ] || return 0
	retry in_chroot "pacman -S --needed --noconfirm --ask=4 $p"
}
AUR_PKGS=()
AUR_FAILED=()
FAILED_OPTIONAL=()
FAILED_PACKAGES=()
declare -A OPTIONAL_GROUP_FAILED=()
AMNEZIA_FAILED=n
INSTALL_LOG="$MNT/var/log/artix-setup-install.log"
record_optional_failure() {
	local component=$1 detail=${2:-$1}
	FAILED_OPTIONAL+=("$component")
	mkdir -p "$(dirname "$INSTALL_LOG")"
	printf '%s optional component failed: %s\n' "$(date -Is)" "$detail" | tee -a "$INSTALL_LOG" >&2
}
required_group() {
	install_group "$1" || die "Required package group $1 failed after retries. See $INSTALL_LOG."
}
add_aur() { local p; while read -r p; do [ -n "$p" ] && AUR_PKGS+=("$p"); done < <(pkgs "$1" aur); }
install_amneziavpn_dinit() {
	if artix-chroot "$MNT" pacman -Q amneziavpn-bin >/dev/null 2>&1; then
		return 0
	fi
	# Upstream's ALPM scriptlet calls systemctl. Remove only those service
	# management lines from the local build; the dinit service is installed below.
	as_user "cd /tmp && rm -rf amneziavpn-bin && git clone https://aur.archlinux.org/amneziavpn-bin.git && cd amneziavpn-bin &&
		sed -i '/^_srvname=/d; /^post_install() {/,/^}/d; /^post_upgrade() {/,/^}/d; /^pre_remove() {/,/^}/d' amneziavpn.install &&
		sed -i '/AmneziaVPN\.service/d' PKGBUILD &&
		! grep -Eq 'systemctl|AmneziaVPN\.service' amneziavpn.install PKGBUILD &&
		makepkg -si --noconfirm"
}

say "GPU drivers"
case $GPU in
1) retry in_chroot "pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver" || die "NVIDIA package installation failed after three attempts."
   if [ ! -e "$MNT/etc/modprobe.d/nvidia.conf" ]; then
	   printf 'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\n' > "$MNT/etc/modprobe.d/nvidia.conf"
	   fi ;;
2) retry in_chroot "pacman -S --needed --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon" || die "AMD package installation failed after three attempts." ;;
*) retry in_chroot "pacman -S --needed --noconfirm mesa lib32-mesa vulkan-swrast lib32-vulkan-swrast" || die "Generic GPU package installation failed after three attempts." ;;
esac

say "Desktop packages"
# Install the preferred providers first so --noconfirm never picks the wrong
# one (jack2 instead of pipewire-jack, a random ttf-font, ...)
retry in_chroot "pacman -S --needed --noconfirm ttf-dejavu pipewire pipewire-jack pipewire-pulse" || die "Core desktop package installation failed after three attempts."
required_group audio.txt;   add_aur audio.txt
required_group desktop.txt; add_aur desktop.txt
if [ "$WMSEL" != 2 ]; then required_group lilith.txt; add_aur lilith.txt; fi
if [ "$WMSEL" != 1 ]; then required_group swayfx.txt; add_aur swayfx.txt; fi
required_group net.txt
for g in dev android reverse games virt printer; do
	[ "${OPT[$g]}" = y ] || continue
	say "Group: $g"
	if install_group "$g.txt"; then
		add_aur "$g.txt"
	else
		mapfile -t group_packages < <(pkgs "$g.txt" repo)
		FAILED_PACKAGES+=("${group_packages[@]}")
		OPTIONAL_GROUP_FAILED[$g]=y
		record_optional_failure "$g.txt" "packages failed: ${group_packages[*]}"
	fi
done
[ "$AMNEZIA" = y ] && AUR_PKGS+=(amneziavpn-bin)

# ---------------------------------------------------------------- AUR
say "paru (AUR helper)"
mkdir -p "$MNT/home/$USERNAME/.config/paru"
printf '[bin]\nSudo = doas\n' > "$MNT/home/$USERNAME/.config/paru/paru.conf"
in_chroot "chown -R $USERNAME: /home/$USERNAME/.config"
if [ ! -x "$MNT/usr/bin/paru" ]; then
	retry as_user "cd /tmp && rm -rf paru-bin && git clone https://aur.archlinux.org/paru-bin.git && cd paru-bin && makepkg -si --noconfirm" || die "Could not install required AUR helper paru after retries."
fi

# wlroots0.19 is built as an AUR dependency for either selected compositor.
# Import and fingerprint-check its signing key before the generic AUR loop.
prepare_wlroots_signing_key

if [ ${#AUR_PKGS[@]} -gt 0 ]; then
	say "AUR packages: ${AUR_PKGS[*]}"
	# One by one: a single failing package must not take the others down
	for p in "${AUR_PKGS[@]}"; do
		say "AUR: $p"
		if [ "$p" = amneziavpn-bin ]; then
			if install_amneziavpn_dinit; then
				:
			else
				FAILED_PACKAGES+=("$p")
				AMNEZIA_FAILED=y
				record_optional_failure "$p" "AUR package build/install failed with dinit-compatible scriptlet"
			fi
			continue
		fi
		retry as_user "paru -S --needed --noconfirm --skipreview $p" || { AUR_FAILED+=("$p"); FAILED_PACKAGES+=("$p"); record_optional_failure "$p" "AUR package install failed"; }
	done
fi

if [ "$WMSEL" != 1 ] && [ ! -e "$MNT/usr/share/artix-setup/swayfx-middle-drag" ]; then
	say "SwayFX $SWAYFX_AUR_COMMIT with the middle-drag patch"
	cp "$REPO/configs/swayfx/middle-drag.patch" "$MNT/tmp/"
	as_user "paru -S --needed --noconfirm --skipreview wlroots0.19 scenefx0.4 &&
		cd /tmp && rm -rf swayfx && git clone https://aur.archlinux.org/swayfx.git && cd swayfx &&
		git checkout -f $SWAYFX_AUR_COMMIT &&
		sed -i \"s/'scenefx[^']*'/'scenefx0.4'/; s/-Dsd-bus-provider=libsystemd/-Dtray=disabled/\" PKGBUILD &&
		makepkg -o --noconfirm &&
		patch -d src/swayfx-0.5.3 -p1 < /tmp/middle-drag.patch &&
		makepkg -efi --noconfirm &&
		doas install -Dm644 /dev/null /usr/share/artix-setup/swayfx-middle-drag" || die "SwayFX installation failed; the install is incomplete. After mounting the existing root at /mnt, run install.sh --resume."
fi

if [ "$WMSEL" != 2 ] && ! artix-chroot "$MNT" /bin/bash -c 'command -v lilith >/dev/null 2>&1'; then
	say "lilith (liwm, branch $LIWM_BRANCH)"
	retry as_user "rm -rf ~/liwm && git clone -b $LIWM_BRANCH $LIWM_URL ~/liwm && cd ~/liwm && make && doas make install" ||
		die "lilith installation failed; the install is incomplete. After mounting the existing root at /mnt, repair its dependencies and retry the build in ~/liwm."
fi

# ---------------------------------------------------------------- configs
say "Configs"
H="$MNT/home/$USERNAME"
cp -an "$REPO"/bin/. "$MNT/usr/local/bin/"
mkdir -p "$H/.config/sway" "$H/.config/pipewire/pipewire.conf.d" "$H/.config/fish/conf.d" \
	"$H/.config/xdg-desktop-portal"
cp -n "$REPO/configs/swayfx/config" "$H/.config/sway/config"
cp -n "$REPO/configs/pipewire/pipewire.conf.d/"*.conf "$H/.config/pipewire/pipewire.conf.d/"
[ -e "$H/.config/wm" ] || echo "$DEFAULT_WM" > "$H/.config/wm"
[ -e "$H/.config/xdg-desktop-portal/portals.conf" ] ||
	printf '[preferred]\ndefault=wlr;gtk\n' > "$H/.config/xdg-desktop-portal/portals.conf"
# Start the compositor after logging in on tty1
if [ ! -e "$H/.config/fish/conf.d/10-start-wm.fish" ]; then
cat > "$H/.config/fish/conf.d/10-start-wm.fish" <<'EOF'
if status is-login; and test (tty) = /dev/tty1; and not set -q WAYLAND_DISPLAY
    exec start-wm
end
EOF
fi
if [ ! -e "$H/.bash_profile" ]; then
cat > "$H/.bash_profile" <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ]; then exec start-wm; fi
EOF
fi
if [ "$(in_chroot "getent passwd $USERNAME | cut -d: -f7")" = /bin/bash ]; then
	in_chroot "chsh -s /usr/bin/fish $USERNAME" || die "Could not set the user's login shell to fish."
fi

# Monitor brightness over DDC/CI (bar brightness module): i2c-dev + i2c group
mkdir -p "$MNT/etc/modules-load.d" "$MNT/etc/udev/rules.d"
[ -e "$MNT/etc/modules-load.d/i2c-dev.conf" ] || echo i2c-dev > "$MNT/etc/modules-load.d/i2c-dev.conf"
[ -e "$MNT/etc/udev/rules.d/60-i2c-group.rules" ] ||
	echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' > "$MNT/etc/udev/rules.d/60-i2c-group.rules"
in_chroot "getent group i2c >/dev/null || groupadd -r i2c; usermod -aG i2c $USERNAME"

mkdir -p "$MNT/etc/polkit-1/rules.d"
[ -e "$MNT/etc/polkit-1/rules.d/50-wheel-noauth.rules" ] ||
	cp "$REPO/configs/polkit/50-wheel-noauth.rules" "$MNT/etc/polkit-1/rules.d/"

if [ "${OPT[virt]}" = y ] && [ "${OPTIONAL_GROUP_FAILED[virt]:-n}" != y ]; then
	grep -Fq 'unix_sock_group = "libvirt"' "$MNT/etc/libvirt/libvirtd.conf" 2>/dev/null || cat "$REPO/configs/libvirt/libvirtd.conf.d-socket" >> "$MNT/etc/libvirt/libvirtd.conf"
	in_chroot "usermod -aG libvirt,kvm $USERNAME"
	if [ -e "$MNT/etc/dinit.d/libvirtd" ]; then link libvirtd; else record_optional_failure libvirt "dinit libvirtd service definition missing"; fi
	if [ -e "$MNT/etc/dinit.d/virtlogd" ]; then link virtlogd; fi
fi
if [ "$AMNEZIA" = y ] && [ "$AMNEZIA_FAILED" != y ]; then
	[ -e "$MNT/etc/dinit.d/amneziavpn" ] || cp "$REPO/dinit/amneziavpn" "$MNT/etc/dinit.d/"
	link amneziavpn || record_optional_failure amneziavpn "could not enable dinit service"
fi
if [ "${OPT[games]}" = y ] && [ "${OPTIONAL_GROUP_FAILED[games]:-n}" != y ]; then
	in_chroot "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ||
		record_optional_failure flathub "could not add Flatpak remote"
fi

# First login tasks that need a running session
if [ ! -e "$H/first-login.sh" ]; then
cat > "$H/first-login.sh" <<EOF
#!/bin/sh
# One-time setup after the first boot. Run it, then delete it.
set -e
$( [ "${OPT[games]}" = y ] && echo 'flatpak install -y flathub org.vinegarhq.Sober' )
echo "first-login: done"
EOF
chmod +x "$H/first-login.sh"
fi
in_chroot "chown -R $USERNAME: /home/$USERNAME"

# Back to password-prompting doas
grep -Fxq 'permit persist :wheel' "$MNT/etc/doas.conf" ||
	printf '%s\n' 'permit persist :wheel' >> "$MNT/etc/doas.conf"
sed -i "/^permit nopass $USERNAME$/d" "$MNT/etc/doas.conf"

say "Done."
if [ ${#AUR_FAILED[@]} -gt 0 ]; then
	warn "These AUR packages did not install: ${AUR_FAILED[*]}"
	warn "After the first boot retry them with: paru -S ${AUR_FAILED[*]}"
fi
if [ ${#FAILED_OPTIONAL[@]} -gt 0 ]; then
	warn "Optional components not installed: ${FAILED_OPTIONAL[*]}"
	warn "Packages to retry: ${FAILED_PACKAGES[*]}"
	warn "Failure details: $INSTALL_LOG"
fi
cat <<EOF

  Reboot, remove the ISO, log in as $USERNAME on tty1: $DEFAULT_WM starts.
  Switch compositor:  start-wm sway  |  start-wm lilith  (or edit ~/.config/wm)
  Then run once:      ~/first-login.sh
  Printer on demand:  doas dinitctl start cupsd
  Used RAM:           mem

EOF
yes_no "Unmount and reboot now?" n && { swapoff -a || true; umount -R "$MNT"; reboot; }
