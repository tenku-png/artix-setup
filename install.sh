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
in_chroot() { artix-chroot "$MNT" /bin/bash -c "$1"; }
retry() { local i; for i in 1 2 3; do "$@" && return 0; warn "failed (try $i/3), retrying..."; sleep 3; done; return 1; }
as_user()   { artix-chroot "$MNT" /bin/su - "$USERNAME" -c "$1"; }
# Read a package group file: prints "repo" or "aur" packages
pkgs() { # pkgs file repo|aur
	sed 's/#.*//' "$REPO/packages/$1" | tr -s ' \t' '\n' | sed '/^$/d' |
	if [ "$2" = aur ]; then sed -n 's/^aur://p'; else grep -v '^aur:' || true; fi
}

# ---------------------------------------------------------------- checks
[ "$(id -u)" = 0 ] || die "run as root"
[ -d /sys/firmware/efi/efivars ] || die "not booted in UEFI mode (enable UEFI in the VM/PC firmware settings)"
command -v basestrap >/dev/null || die "basestrap not found: run this from the Artix ISO"
ping -c1 -W3 artixlinux.org >/dev/null 2>&1 || die "no network (try: dinitctl start dhcpcd)"

pacman -Sy --needed --noconfirm git >/dev/null
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

# Disk the ISO was booted from: never offered for wiping
ISO_DISK=
src=$(findmnt -no SOURCE /run/artix/bootmnt 2>/dev/null || true)
[ -n "$src" ] && ISO_DISK=/dev/$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
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
sed -i '/^#\[lib32\]/{s/^#//;n;s/^#//}' "$MNT/etc/pacman.conf"
in_chroot "pacman -Sy --needed --noconfirm artix-archlinux-support"
grep -q '^\[extra\]' "$MNT/etc/pacman.conf" || cat >> "$MNT/etc/pacman.conf" <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
in_chroot "pacman-key --populate archlinux; pacman -Syu --noconfirm"

# ---------------------------------------------------------------- boot
say "Boot entry (EFISTUB, no GRUB)"
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
EFI_DISK=/dev/$(lsblk -no PKNAME "$EFI" | head -1)
EFI_NUM=$(cat "/sys/class/block/$(basename "$EFI")/partition")
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=@ rw quiet loglevel=3"
[ "$GPU" = 1 ] && CMDLINE+=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
in_chroot "efibootmgr --create --disk $EFI_DISK --part $EFI_NUM --label 'Artix' \
	--loader /vmlinuz-linux-zen \
	--unicode '$CMDLINE initrd=\\$UCODE.img initrd=\\initramfs-linux-zen.img'"

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
install_group() { # repo packages of a group
	local p; p=$(pkgs "$1" repo | tr '\n' ' ')
	if [ -n "$p" ]; then in_chroot "pacman -S --needed --noconfirm --ask=4 $p"; fi
}
AUR_PKGS=()
AUR_FAILED=()
add_aur() { local p; while read -r p; do [ -n "$p" ] && AUR_PKGS+=("$p"); done < <(pkgs "$1" aur); }

say "GPU drivers"
case $GPU in
1) in_chroot "pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver"
   printf 'options nvidia_drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\n' \
	> "$MNT/etc/modprobe.d/nvidia.conf" ;;
2) in_chroot "pacman -S --needed --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon" ;;
*) in_chroot "pacman -S --needed --noconfirm mesa lib32-mesa vulkan-swrast lib32-vulkan-swrast" ;;
esac

say "Desktop packages"
# Install the preferred providers first so --noconfirm never picks the wrong
# one (jack2 instead of pipewire-jack, a random ttf-font, ...)
in_chroot "pacman -S --needed --noconfirm ttf-dejavu pipewire pipewire-jack pipewire-pulse"
install_group audio.txt;   add_aur audio.txt
install_group desktop.txt; add_aur desktop.txt
[ "$WMSEL" != 2 ] && install_group lilith.txt
[ "$WMSEL" != 1 ] && install_group swayfx.txt
install_group net.txt
for g in dev android reverse games virt printer; do
	[ "${OPT[$g]}" = y ] || continue
	say "Group: $g"
	install_group "$g.txt"; add_aur "$g.txt"
done
[ "$AMNEZIA" = y ] && AUR_PKGS+=(amneziavpn-bin)

# ---------------------------------------------------------------- AUR
say "paru (AUR helper)"
mkdir -p "$MNT/home/$USERNAME/.config/paru"
printf '[bin]\nSudo = doas\n' > "$MNT/home/$USERNAME/.config/paru/paru.conf"
in_chroot "chown -R $USERNAME: /home/$USERNAME/.config"
retry as_user "cd /tmp && rm -rf paru-bin && git clone https://aur.archlinux.org/paru-bin.git && cd paru-bin && makepkg -si --noconfirm"

if [ ${#AUR_PKGS[@]} -gt 0 ]; then
	say "AUR packages: ${AUR_PKGS[*]}"
	# One by one: a single failing package must not take the others down
	for p in "${AUR_PKGS[@]}"; do
		say "AUR: $p"
		retry as_user "paru -S --needed --noconfirm --skipreview $p" || AUR_FAILED+=("$p")
	done
fi

if [ "$WMSEL" != 1 ]; then
	say "SwayFX $SWAYFX_AUR_COMMIT with the middle-drag patch"
	cp "$REPO/configs/swayfx/middle-drag.patch" "$MNT/tmp/"
	as_user "paru -S --needed --noconfirm --skipreview scenefx0.4 &&
		cd /tmp && rm -rf swayfx && git clone https://aur.archlinux.org/swayfx.git && cd swayfx &&
		git checkout -f $SWAYFX_AUR_COMMIT &&
		sed -i \"s/'scenefx[^']*'/'scenefx0.4'/; s/-Dsd-bus-provider=libsystemd/-Dtray=disabled/\" PKGBUILD &&
		makepkg -o --noconfirm &&
		patch -d src/swayfx-0.5.3 -p1 < /tmp/middle-drag.patch &&
		makepkg -efi --noconfirm" || warn "SwayFX build failed (see configs/swayfx/README.md)"
fi

if [ "$WMSEL" != 2 ]; then
	say "lilith (liwm, branch $LIWM_BRANCH)"
	retry as_user "rm -rf ~/liwm && git clone -b $LIWM_BRANCH $LIWM_URL ~/liwm && cd ~/liwm && make && doas make install" ||
		warn "lilith build failed; retry in ~/liwm with: make && doas make install"
fi

# ---------------------------------------------------------------- configs
say "Configs"
H="$MNT/home/$USERNAME"
install -m755 "$REPO"/bin/* "$MNT/usr/local/bin/"
mkdir -p "$H/.config/sway" "$H/.config/pipewire/pipewire.conf.d" "$H/.config/fish/conf.d" \
	"$H/.config/xdg-desktop-portal"
cp "$REPO/configs/swayfx/config" "$H/.config/sway/config"
cp "$REPO/configs/pipewire/pipewire.conf.d/"*.conf "$H/.config/pipewire/pipewire.conf.d/"
echo "$DEFAULT_WM" > "$H/.config/wm"
printf '[preferred]\ndefault=wlr;gtk\n' > "$H/.config/xdg-desktop-portal/portals.conf"
# Start the compositor after logging in on tty1
cat > "$H/.config/fish/conf.d/10-start-wm.fish" <<'EOF'
if status is-login; and test (tty) = /dev/tty1; and not set -q WAYLAND_DISPLAY
    exec start-wm
end
EOF
cat > "$H/.bash_profile" <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ]; then exec start-wm; fi
EOF
in_chroot "chsh -s /usr/bin/fish $USERNAME" 2>/dev/null || true

# Monitor brightness over DDC/CI (bar brightness module): i2c-dev + i2c group
mkdir -p "$MNT/etc/modules-load.d" "$MNT/etc/udev/rules.d"
echo i2c-dev > "$MNT/etc/modules-load.d/i2c-dev.conf"
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' > "$MNT/etc/udev/rules.d/60-i2c-group.rules"
in_chroot "getent group i2c >/dev/null || groupadd -r i2c; usermod -aG i2c $USERNAME"

mkdir -p "$MNT/etc/polkit-1/rules.d"
cp "$REPO/configs/polkit/50-wheel-noauth.rules" "$MNT/etc/polkit-1/rules.d/"

if [ "${OPT[virt]}" = y ]; then
	cat "$REPO/configs/libvirt/libvirtd.conf.d-socket" >> "$MNT/etc/libvirt/libvirtd.conf"
	in_chroot "usermod -aG libvirt,kvm $USERNAME"
	link libvirtd 2>/dev/null || true
	[ -e "$MNT/etc/dinit.d/virtlogd" ] && link virtlogd
fi
if [ "$AMNEZIA" = y ]; then
	cp "$REPO/dinit/amneziavpn" "$MNT/etc/dinit.d/"
	link amneziavpn
fi
[ "${OPT[games]}" = y ] && in_chroot "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" || true

# First login tasks that need a running session
cat > "$H/first-login.sh" <<EOF
#!/bin/sh
# One-time setup after the first boot. Run it, then delete it.
set -e
$( [ "${OPT[games]}" = y ] && echo 'flatpak install -y flathub org.vinegarhq.Sober' )
echo "first-login: done"
EOF
chmod +x "$H/first-login.sh"
in_chroot "chown -R $USERNAME: /home/$USERNAME"

# Back to password-prompting doas
printf 'permit persist :wheel\n' > "$MNT/etc/doas.conf"

say "Done."
if [ ${#AUR_FAILED[@]} -gt 0 ]; then
	warn "These AUR packages did not install: ${AUR_FAILED[*]}"
	warn "After the first boot retry them with: paru -S ${AUR_FAILED[*]}"
	printf '%s\n' "paru -S --needed ${AUR_FAILED[*]}" >> "$H/first-login.sh"
fi
cat <<EOF

  Reboot, remove the ISO, log in as $USERNAME on tty1: $DEFAULT_WM starts.
  Switch compositor:  start-wm sway  |  start-wm lilith  (or edit ~/.config/wm)
  Then run once:      ~/first-login.sh
  Printer on demand:  doas dinitctl start cupsd
  Used RAM:           mem

EOF
yes_no "Unmount and reboot now?" n && { swapoff -a || true; umount -R "$MNT"; reboot; }
