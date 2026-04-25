#!/usr/bin/env bash

# assemble-guix-image.sh
#
# Purpose: Build and assemble guix-shimboot disk image for ChromeOS hardware
#
# This module:
# - Builds Guix system configuration via guix system build
# - Harvests ChromeOS drivers from SHIM/recovery images
# - Creates partitioned disk image (GPT, ChromeOS GUIDs)
# - Populates vendor and rootfs partitions
# - Installs bootloader with Guix generation detection
#
# Usage: ./assemble-guix-image.sh --board dedede [OPTIONS]

set -Eeuo pipefail

# === Source shared libs ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source logging first (required by other libs)
if [[ -f "$LIB_DIR/logging.sh" ]]; then
	# shellcheck source=logging.sh
	source "$LIB_DIR/logging.sh"
else
	# Minimal logging fallback if lib not available
	ANSI_CLEAR='\033[0m'
	ANSI_BOLD='\033[1m'
	ANSI_GREEN='\033[1;32m'
	ANSI_BLUE='\033[1;34m'
	ANSI_YELLOW='\033[1;33m'
	ANSI_RED='\033[1;31m'

	log_step() { printf "${ANSI_BOLD}${ANSI_BLUE}[%s] %s${ANSI_CLEAR}\n" "$1" "$2"; }
	log_info() { printf "${ANSI_GREEN}  > %s${ANSI_CLEAR}\n" "$1"; }
	log_warn() { printf "${ANSI_YELLOW}  ! %s${ANSI_CLEAR}\n" "$1"; }
	log_error() { printf "${ANSI_RED}  X %s${ANSI_CLEAR}\n" "$1"; }
	log_success() { printf "${ANSI_GREEN}  OK %s${ANSI_CLEAR}\n" "$1"; }
fi

# Source other libs if available
for lib in args.sh devices.sh firmware.sh mounts.sh runtime.sh; do
	if [[ -f "$LIB_DIR/$lib" ]]; then
		# shellcheck disable=SC1090
		source "$LIB_DIR/$lib"
	fi
done

# === Supported boards ===
readonly SUPPORTED_BOARDS=(dedede octopus zork nissa hatch grunt snappy brya jacuzzi corsola hana trogdor)

# === Defaults (env overrides take precedence) ===
BOARD="${BOARD:-}"
ROOTFS_FLAVOR="${ROOTFS_FLAVOR:-base}"
DRIVERS_MODE="${DRIVERS_MODE:-vendor}"
FIRMWARE_UPSTREAM="${FIRMWARE_UPSTREAM:-1}"
DRY_RUN="${DRY_RUN:-0}"
INSPECT_AFTER="${INSPECT_AFTER:-0}"
CLEANUP_WORKDIR="${CLEANUP_WORKDIR:-1}"
SKIP_SUDO=0
WORKDIR="${WORKDIR:-}"
IMAGE=""
SECONDS=0

# Partition layout (MiB offsets):
#   p1: STATE       1-2
#   p2: KERNEL       2-34
#   p3: BOOT         34-54
#   p4: VENDOR       54-VENDOR_END
#   p5: ROOTFS       VENDOR_END-end
VENDOR_START_MB=54

# === Help ===
show_help() {
	cat <<'HELP'
Usage: ./assemble-guix-image.sh [OPTIONS]

Build a guix-shimboot disk image for ChromeOS hardware.

Required:
  --board BOARD           Target Chromebook board (dedede, octopus, zork, etc.)

Options:
  -h, --help              Show this help message
  --rootfs FLAVOR         Rootfs variant: base (default) or headless
  --drivers MODE          Driver placement: vendor (default), inject, both, none
  --firmware-upstream     Enable upstream firmware (default: enabled)
  --no-firmware-upstream  Disable upstream firmware
  --workdir DIR           Working directory (default: ./work/BOARD)
  --inspect               Inspect final image after build
  --no-cleanup            Preserve work directory after build
  --dry-run               Show what would be done without executing
  --no-sudo               Skip sudo elevation (for testing)

Examples:
  ./assemble-guix-image.sh --board dedede
  ./assemble-guix-image.sh --board zork --rootfs headless --drivers vendor
  ./assemble-guix-image.sh --board dedede --dry-run
HELP
	exit 0
}

# === Save original args before any parsing ===
ORIGINAL_ARGS=("$@")

# === Early arg parsing for --help ===
HELP_MODE=0
while [ $# -gt 0 ]; do
	case "${1:-}" in
	-h | --help)
		HELP_MODE=1
		shift
		;;
	--no-sudo)
		SKIP_SUDO=1
		shift
		;;
	*)
		shift
		;;
	esac
done

if [ "$HELP_MODE" -eq 1 ]; then
	show_help
fi

# Restore original args for full parsing
set -- "${ORIGINAL_ARGS[@]}"

# === Main arg parsing ===
while [ $# -gt 0 ]; do
	case "${1:-}" in
	--board)
		BOARD="${2:-}"
		shift 2
		;;
	--rootfs)
		ROOTFS_FLAVOR="${2:-base}"
		shift 2
		;;
	--drivers)
		DRIVERS_MODE="${2:-vendor}"
		shift 2
		;;
	--firmware-upstream)
		FIRMWARE_UPSTREAM=1
		shift
		;;
	--no-firmware-upstream)
		FIRMWARE_UPSTREAM=0
		shift
		;;
	--workdir)
		WORKDIR="${2:-}"
		shift 2
		;;
	--inspect)
		INSPECT_AFTER=1
		shift
		;;
	--no-cleanup)
		CLEANUP_WORKDIR=0
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--no-sudo)
		SKIP_SUDO=1
		shift
		;;
	*)
		[ -n "${1:-}" ] && log_warn "Unknown option: ${1:-}"
		shift
		;;
	esac
done

# === Interactive onboarding ===
if [ -z "$BOARD" ]; then
	if [ -t 0 ]; then
		echo
		echo "[assemble-guix-image] No board specified. Available boards:"
		for b in "${SUPPORTED_BOARDS[@]}"; do
			echo "  $b"
		done
		read -rp "Enter board name [default=dedede]: " BOARD
		BOARD="${BOARD:-dedede}"
	else
		BOARD="dedede"
	fi
fi

# Validate board
valid_board=0
for b in "${SUPPORTED_BOARDS[@]}"; do
	[ "$b" = "$BOARD" ] && valid_board=1 && break
done
if [ "$valid_board" -eq 0 ]; then
	log_error "Unsupported board: $BOARD"
	log_error "Supported boards: ${SUPPORTED_BOARDS[*]}"
	exit 1
fi

# Validate rootfs flavor
if [ "$ROOTFS_FLAVOR" != "base" ] && [ "$ROOTFS_FLAVOR" != "headless" ]; then
	log_error "Invalid --rootfs value: '${ROOTFS_FLAVOR}'. Use 'base' or 'headless'."
	exit 1
fi

# Validate drivers mode
case "$DRIVERS_MODE" in
vendor | inject | both | none) ;;
*) log_error "Invalid --drivers value: '${DRIVERS_MODE}'. Use vendor, inject, both, or none." && exit 1 ;;
esac

# === Sudo ===
require_sudo() {
	if [ "${SKIP_SUDO:-0}" -eq 1 ]; then
		return 0
	fi
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		log_info "Re-executing with sudo -H..."
		SUDO_ENV=()
		for var in BOARD ROOTFS_FLAVOR DRIVERS_MODE FIRMWARE_UPSTREAM DRY_RUN INSPECT_AFTER CLEANUP_WORKDIR WORKDIR; do
			[ -n "${!var:-}" ] && SUDO_ENV+=("$var=${!var}")
		done
		exec sudo -E -H "${SUDO_ENV[@]}" "$0" --no-sudo
	fi
}

# === Workspace ===
if [ -z "$WORKDIR" ]; then
	WORKDIR="$(pwd)/work/${BOARD}"
fi
IMAGE="$WORKDIR/guix-shimboot.img"

# === Safe execution for dry-run ===
safe_exec() {
	if [ "$DRY_RUN" -eq 1 ]; then
		log_info "[DRY-RUN] Would execute: $*"
	else
		"$@"
	fi
}

# === Dependencies ===
check_dependencies() {
	log_step "Pre-check" "Verifying dependencies"

	local missing=()
	for cmd in guix parted losetup mkfs.ext4 cgpt fallocate pv; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		log_error "Missing dependencies: ${missing[*]}"
		log_error "Install them and re-run. For a dev shell:"
		log_error "  nix develop"
		exit 1
	fi

	# Verify guix is operational
	if ! guix --version >/dev/null 2>&1; then
		log_error "guix command failed. Ensure guix is installed and in PATH."
		log_error "For a dev shell with all dependencies:"
		log_error "  nix develop"
		exit 1
	fi

	log_success "All dependencies available"
}

# === Disk space check ===
check_disk_space() {
	local required_gb="${1:-25}"
	local path="${2:-.}"
	local available_gb
	available_gb=$(df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//')

	if [ "${available_gb:-0}" -lt "$required_gb" ]; then
		log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
		exit 1
	fi
	log_info "Disk space: ${available_gb}GB available (${required_gb}GB required)"
}

# === Loop device tracking ===
LOOPDEV=""
LOOPROOT=""

cleanup_loop_devices() {
	local backing_files=("$IMAGE" "$WORKDIR/rootfs.img")
	for f in "${backing_files[@]}"; do
		[ -f "$f" ] || continue
		while read -r dev; do
			[ -n "$dev" ] || continue
			log_info "Detaching $dev (backed by $(basename "$f"))..."
			sudo losetup -d "$dev" 2>/dev/null || true
		done < <(losetup -j "$f" 2>/dev/null | cut -d: -f1)
	done

	for dev in "$LOOPDEV" "$LOOPROOT"; do
		if [ -n "$dev" ] && losetup "$dev" &>/dev/null; then
			log_info "Detaching tracked device $dev..."
			sudo losetup -d "$dev" 2>/dev/null || true
		fi
	done
}

cleanup() {
	log_info "Cleanup: unmounting and detaching loop devices..."
	set +e

	for mnt in "$WORKDIR/mnt_rootfs" "$WORKDIR/mnt_bootloader" \
		"$WORKDIR/mnt_src_rootfs" "$WORKDIR/mnt_vendor" \
		"$WORKDIR/mnt_guix" "$WORKDIR/inspect_rootfs"; do
		if mountpoint -q "$mnt" 2>/dev/null; then
			log_info "Unmounting $mnt..."
			for i in {1..3}; do
				safe_exec sudo umount "$mnt" 2>/dev/null && break
				sleep 0.5
				[ "$i" -eq 3 ] && safe_exec sudo umount -l "$mnt" 2>/dev/null
			done
		fi
	done

	sync
	sleep 1

	cleanup_loop_devices

	if [ "$CLEANUP_WORKDIR" -eq 1 ]; then
		for d in mnt_rootfs mnt_bootloader mnt_src_rootfs mnt_vendor mnt_guix \
			inspect_rootfs harvested linux-firmware.upstream; do
			rm -rf "${WORKDIR:?}/$d" 2>/dev/null || true
		done
	fi

	set -e
}

handle_interrupt() {
	echo
	log_warn "Keyboard interrupt detected"
	trap - INT
	cleanup
	log_error "Assembly interrupted by user."
	exit 130
}

trap cleanup EXIT TERM
trap handle_interrupt INT

# === Require sudo before destructive operations ===
require_sudo

# === Cleanup stale workspace ===
if [ -d "$WORKDIR" ]; then
	log_info "Cleaning up old work directory..."
	# Detach stale loop devices from previous runs
	while read -r _stale_dev; do
		[ -n "$_stale_dev" ] || continue
		log_info "Detaching stale loop device $_stale_dev from previous run..."
		losetup -d "$_stale_dev" 2>/dev/null || true
	done < <(losetup -l --noheadings -O NAME,BACK-FILE 2>/dev/null |
		awk -v d="$WORKDIR" '$2 ~ "^" d {print $1}')
	unset _stale_dev
	safe_exec rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR" "$WORKDIR/mnt_src_rootfs" "$WORKDIR/mnt_bootloader" "$WORKDIR/mnt_rootfs"

# === Summary (after sudo, so printed once) ===
log_info "Board:             $BOARD"
log_info "Rootfs flavor:     $ROOTFS_FLAVOR"
log_info "Drivers mode:      $DRIVERS_MODE"
log_info "Upstream firmware: $FIRMWARE_UPSTREAM"
log_info "Workspace:         $WORKDIR"
if [ "$DRY_RUN" -eq 1 ]; then
	log_warn "DRY RUN MODE: No destructive operations will be performed"
fi

# === Pre-flight checks ===
check_dependencies
check_disk_space 25 "$WORKDIR"

# === Step 1: Build Guix system ===
CURRENT_STEP="1/12"
log_step "$CURRENT_STEP" "Build Guix system derivation"

GUIX_CONFIG="$PROJECT_ROOT/config/system.scm"
if [ ! -f "$GUIX_CONFIG" ]; then
	log_error "Guix system config not found: $GUIX_CONFIG"
	exit 1
fi

log_info "Building Guix system from $GUIX_CONFIG..."

if [ "$DRY_RUN" -eq 1 ]; then
	log_info "[DRY-RUN] Would run: guix system build $GUIX_CONFIG"
	GUIX_OUT="/tmp/guix-shimboot-dry-run"
else
	GUIX_LOG="$WORKDIR/guix-build.log"
	log_info "Build log: $GUIX_LOG"
	if ! guix system build "$GUIX_CONFIG" >"$GUIX_LOG" 2>&1; then
		log_error "Guix system build failed!"
		log_error "Last 20 lines of build log:"
		tail -20 "$GUIX_LOG" >&2
		exit 1
	fi
	GUIX_OUT=$(tail -1 "$GUIX_LOG")
	if [ ! -d "$GUIX_OUT" ]; then
		log_error "Guix build output is not a directory: $GUIX_OUT"
		log_error "Full build log: $GUIX_LOG"
		exit 1
	fi
fi

log_info "Guix system built: $GUIX_OUT"

# === Step 2: Create raw rootfs from Guix output ===
CURRENT_STEP="2/12"
log_step "$CURRENT_STEP" "Create raw rootfs image from Guix output"

# Guix system build produces a store item; we need to create an ext4 image from it
ROOTFS_SIZE_MB=$(du -sm "$GUIX_OUT" 2>/dev/null | cut -f1 || echo 3000)
# Add 30% growth margin for Guix generations and package additions
ROOTFS_SIZE_MB=$((ROOTFS_SIZE_MB * 130 / 100 + 500))

log_info "Creating rootfs image: ${ROOTFS_SIZE_MB}MB"

safe_exec truncate -s "${ROOTFS_SIZE_MB}M" "$WORKDIR/rootfs.img"
safe_exec mkfs.ext4 -q -L "guix-rootfs" "$WORKDIR/rootfs.img"

# Mount and populate rootfs
mkdir -p "$WORKDIR/mnt_guix"
safe_exec sudo mount -o loop "$WORKDIR/rootfs.img" "$WORKDIR/mnt_guix"

log_info "Copying Guix system to rootfs..."
safe_exec sudo cp -a "$GUIX_OUT/." "$WORKDIR/mnt_guix/"

# Ensure /var/guix/profiles/system symlink exists
safe_exec sudo mkdir -p "$WORKDIR/mnt_guix/var/guix/profiles"
if [ ! -L "$WORKDIR/mnt_guix/var/guix/profiles/system" ]; then
	safe_exec sudo ln -sf "$GUIX_OUT" "$WORKDIR/mnt_guix/var/guix/profiles/system"
fi

# Ensure init symlink for Shepherd
if [ ! -x "$WORKDIR/mnt_guix/var/guix/profiles/system/init" ]; then
	log_warn "Guix init not found at /var/guix/profiles/system/init"
	log_warn "Shepherd may not start correctly"
fi

safe_exec sudo umount "$WORKDIR/mnt_guix"

# Rootfs partition size: content + 15% overhead + 100MB safety margin
ROOTFS_PART_SIZE=$((ROOTFS_SIZE_MB * 115 / 100 + 100))
log_info "Rootfs partition size: ${ROOTFS_PART_SIZE}MB (with safety margin)"

# === Step 3: Fetch ChromeOS SHIM ===
CURRENT_STEP="3/12"
log_step "$CURRENT_STEP" "Fetch ChromeOS SHIM image"

SHIM_PATH="${SHIM_PATH:-}"
if [ -z "$SHIM_PATH" ]; then
	# Check for cached SHIM
	SHIM_CACHE="$PROJECT_ROOT/cache/${BOARD}/shim.bin"
	if [ -f "$SHIM_CACHE" ]; then
		SHIM_PATH="$SHIM_CACHE"
		log_info "Using cached SHIM: $SHIM_PATH"
	else
		log_error "No SHIM image found for board: $BOARD"
		log_error "Set SHIM_PATH or place shim at: $SHIM_CACHE"
		log_error ""
		log_error "To download a ChromeOS recovery image for your board:"
		log_error "  1. Visit https://cros.tech/chromebook-recovery-images/"
		log_error "  2. Or use: tools/build/fetch-recovery.sh --board $BOARD"
		exit 1
	fi
fi

if [ ! -f "$SHIM_PATH" ]; then
	log_error "SHIM image not found: $SHIM_PATH"
	exit 1
fi

log_info "SHIM image: $SHIM_PATH"

# === Step 4: Harvest ChromeOS drivers ===
CURRENT_STEP="4/12"
log_step "$CURRENT_STEP" "Harvest ChromeOS drivers"

HARVEST_OUT="$WORKDIR/harvested"
mkdir -p "$HARVEST_OUT"

HARVEST_SCRIPT="$PROJECT_ROOT/tools/build/harvest-drivers.sh"
# Fallback to nixos-shimboot harvest script if ours doesn't exist
if [ ! -f "$HARVEST_SCRIPT" ]; then
	HARVEST_SCRIPT="$PROJECT_ROOT/shimboot-core/tools/build/harvest-drivers.sh"
fi

if [ -f "$HARVEST_SCRIPT" ]; then
	RECOVERY_PATH="${RECOVERY_PATH:-}"
	if [ -n "$RECOVERY_PATH" ]; then
		safe_exec bash "$HARVEST_SCRIPT" --shim "$SHIM_PATH" --recovery "$RECOVERY_PATH" --out "$HARVEST_OUT"
	else
		safe_exec bash "$HARVEST_SCRIPT" --shim "$SHIM_PATH" --out "$HARVEST_OUT"
	fi
else
	log_warn "harvest-drivers.sh not found; attempting manual driver extraction"
	# Manual fallback: mount SHIM and extract kernel modules
	SHIM_LOOP=$(sudo losetup --show -fP "$SHIM_PATH")
	SHIM_MNT="$WORKDIR/mnt_shim"
	mkdir -p "$SHIM_MNT"

	# Find the largest partition (rootfs) in the SHIM
	for part in "${SHIM_LOOP}p"*; do
		[ -b "$part" ] || continue
		if sudo mount -o ro "$part" "$SHIM_MNT" 2>/dev/null; then
			# Check for kernel modules
			if [ -d "$SHIM_MNT/lib/modules" ]; then
				safe_exec sudo cp -a "$SHIM_MNT/lib/modules" "$HARVEST_OUT/"
				log_info "Extracted kernel modules from $part"
			fi
			if [ -d "$SHIM_MNT/lib/firmware" ]; then
				safe_exec sudo cp -a "$SHIM_MNT/lib/firmware" "$HARVEST_OUT/"
				log_info "Extracted firmware from $part"
			fi
			sudo umount "$SHIM_MNT"
		fi
	done
	sudo losetup -d "$SHIM_LOOP" 2>/dev/null || true
fi

# Detach any leftover loops from harvest
for img in "$SHIM_PATH" "$RECOVERY_PATH"; do
	[ -f "$img" ] || continue
	while read -r dev; do
		[ -n "$dev" ] && sudo losetup -d "$dev" 2>/dev/null || true
	done < <(losetup -j "$img" 2>/dev/null | cut -d: -f1)
done

# === Step 5: Augment firmware with upstream ===
if [ "$FIRMWARE_UPSTREAM" -eq 1 ]; then
	CURRENT_STEP="5/12"
	log_step "$CURRENT_STEP" "Augment firmware with upstream linux-firmware"

	UPSTREAM_FW_DIR="$WORKDIR/linux-firmware.upstream"
	if [ ! -d "$UPSTREAM_FW_DIR" ]; then
		log_info "Cloning upstream linux-firmware (shallow)..."
		git clone --depth=1 https://chromium.googlesource.com/chromiumos/third_party/linux-firmware "$UPSTREAM_FW_DIR" || true
	fi

	mkdir -p "$HARVEST_OUT/lib/firmware"
	safe_exec sudo cp -a "$UPSTREAM_FW_DIR/." "$HARVEST_OUT/lib/firmware/" 2>/dev/null || true
	log_info "Upstream firmware augmentation complete"
else
	log_info "Upstream firmware disabled"
fi

# === Step 6: Calculate vendor partition size ===
CURRENT_STEP="6/12"
log_step "$CURRENT_STEP" "Calculate partition sizes"

VENDOR_SRC_SIZE_MB=0
if [ -d "$HARVEST_OUT/lib/modules" ]; then
	VENDOR_SRC_SIZE_MB=$((VENDOR_SRC_SIZE_MB + $(sudo du -sm "$HARVEST_OUT/lib/modules" | cut -f1)))
fi
if [ -d "$HARVEST_OUT/lib/firmware" ]; then
	VENDOR_SRC_SIZE_MB=$((VENDOR_SRC_SIZE_MB + $(sudo du -sm "$HARVEST_OUT/lib/firmware" | cut -f1)))
fi

# 15% overhead + 20MB safety
VENDOR_PART_SIZE=$((VENDOR_SRC_SIZE_MB * 115 / 100 + 20))

TOTAL_SIZE_MB=$((1 + 32 + 20 + VENDOR_PART_SIZE + ROOTFS_PART_SIZE))

log_info "Vendor partition: ${VENDOR_PART_SIZE}MB"
log_info "Rootfs partition: ${ROOTFS_PART_SIZE}MB"
log_info "Total image size:  ${TOTAL_SIZE_MB}MB"

# === Step 7: Create empty image ===
CURRENT_STEP="7/12"
log_step "$CURRENT_STEP" "Create empty image"

mkdir -p "$(dirname "$IMAGE")"
safe_exec fallocate -l "${TOTAL_SIZE_MB}M" "$IMAGE"

# === Step 8: Partition image ===
CURRENT_STEP="8/12"
log_step "$CURRENT_STEP" "Partition image (GPT, ChromeOS GUIDs)"

if [ "$DRIVERS_MODE" = "inject" ]; then
	HAS_VENDOR_PARTITION=0
	ROOTFS_PARTITION_INDEX=4
	log_info "Inject mode: skipping vendor partition (rootfs -> p4)"
else
	HAS_VENDOR_PARTITION=1
	ROOTFS_PARTITION_INDEX=5
	log_info "Vendor mode: keeping vendor partition (rootfs -> p5)"
fi

VENDOR_END_MB=$((VENDOR_START_MB + VENDOR_PART_SIZE))

if [ "$HAS_VENDOR_PARTITION" -eq 1 ]; then
	log_info "  p1: STATE (1-2 MiB)"
	log_info "  p2: KERNEL (2-34 MiB, ChromeOS kernel)"
	log_info "  p3: BOOT (34-54 MiB, bootloader/initramfs)"
	log_info "  p4: VENDOR (${VENDOR_START_MB}-${VENDOR_END_MB} MiB, drivers/firmware)"
	log_info "  p5: ROOTFS (${VENDOR_END_MB} MiB-end, Guix system)"

	safe_exec parted --script "$IMAGE" \
		mklabel gpt \
		mkpart stateful ext4 1MiB 2MiB \
		name 1 STATE \
		mkpart kernel 2MiB 34MiB \
		name 2 KERNEL \
		type 2 FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
		mkpart bootloader ext2 34MiB 54MiB \
		name 3 BOOT \
		type 3 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC \
		mkpart vendor ext4 ${VENDOR_START_MB}MiB ${VENDOR_END_MB}MiB \
		name 4 "shimboot_rootfs:vendor" \
		type 4 0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
		mkpart rootfs ext4 ${VENDOR_END_MB}MiB 100% \
		name 5 "shimboot_rootfs:guix" \
		type 5 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC
else
	log_info "  p1: STATE (1-2 MiB)"
	log_info "  p2: KERNEL (2-34 MiB, ChromeOS kernel)"
	log_info "  p3: BOOT (34-54 MiB, bootloader/initramfs)"
	log_info "  p4: ROOTFS (54 MiB-end, Guix system)"

	safe_exec parted --script "$IMAGE" \
		mklabel gpt \
		mkpart stateful ext4 1MiB 2MiB \
		name 1 STATE \
		mkpart kernel 2MiB 34MiB \
		name 2 KERNEL \
		type 2 FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
		mkpart bootloader ext2 34MiB 54MiB \
		name 3 BOOT \
		type 3 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC \
		mkpart rootfs ext4 54MiB 100% \
		name 4 "shimboot_rootfs:guix" \
		type 4 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC
fi

log_info "Partition table:"
sudo partx -o NR,START,END,SIZE,TYPE,NAME,UUID -g --show "$IMAGE" 2>/dev/null || true

# === Step 9: Format partitions ===
CURRENT_STEP="9/12"
log_step "$CURRENT_STEP" "Format partitions"

LOOPDEV=$(sudo losetup --show -fP "$IMAGE") || {
	log_error "Failed to setup loop device"
	exit 1
}
log_info "Loop device: $LOOPDEV"

# Verify cgpt is available
if ! command -v cgpt >/dev/null 2>&1; then
	log_error "cgpt not found. Install vboot_reference or run inside guix shell."
	exit 1
fi

# Set ChromeOS boot flags on kernel partition
safe_exec sudo cgpt add -i 2 -S 1 -T 5 -P 10 "$LOOPDEV"

# Conservative ext4 flags for ChromeOS kernel compatibility
MKFS_EXT4_FLAGS=(-O '^orphan_file,^metadata_csum_seed')

safe_exec sudo mkfs.ext4 -q "${MKFS_EXT4_FLAGS[@]}" "${LOOPDEV}p1"
safe_exec sudo dd if="$SHIM_PATH" of="${LOOPDEV}p2" bs=1M conv=fsync status=progress
safe_exec sudo mkfs.ext2 -q "${LOOPDEV}p3"

if [ "$HAS_VENDOR_PARTITION" -eq 1 ]; then
	safe_exec sudo mkfs.ext4 -q -O '^has_journal,^orphan_file,^metadata_csum_seed' \
		-L "shimboot_vendor" "${LOOPDEV}p4"
	safe_exec sudo mkfs.ext4 -q -L "guix" "${MKFS_EXT4_FLAGS[@]}" "${LOOPDEV}p5"
else
	safe_exec sudo mkfs.ext4 -q -L "guix" "${MKFS_EXT4_FLAGS[@]}" "${LOOPDEV}p4"
fi

# === Step 10: Populate bootloader partition ===
CURRENT_STEP="10/12"
log_step "$CURRENT_STEP" "Populate bootloader partition"

BOOTLOADER_SRC="$PROJECT_ROOT/bootloader/bin"

safe_exec sudo mkdir -p "$WORKDIR/mnt_bootloader"
safe_exec sudo mount "${LOOPDEV}p3" "$WORKDIR/mnt_bootloader"

# Copy bootstrap.sh and init script to bootloader partition
if [ -f "$BOOTLOADER_SRC/bootstrap.sh" ]; then
	safe_exec sudo cp "$BOOTLOADER_SRC/bootstrap.sh" "$WORKDIR/mnt_bootloader/bootstrap.sh"
	safe_exec sudo chmod +x "$WORKDIR/mnt_bootloader/bootstrap.sh"
	log_info "Installed bootstrap.sh to boot partition"
fi

# Apply shimboot-core.patch if available
PATCH_FILE="$BOOTLOADER_SRC/shimboot-core.patch"
if [ -f "$PATCH_FILE" ]; then
	log_info "shimboot-core.patch available (to be applied to nixos-shimboot bootstrap.sh)"
	log_info "Apply this patch to shimboot-core/bootstrap.sh before building"
fi

safe_exec sudo umount "$WORKDIR/mnt_bootloader"

# === Step 11: Populate rootfs and vendor partitions ===
CURRENT_STEP="11/12"
log_step "$CURRENT_STEP" "Populate rootfs partition (p${ROOTFS_PARTITION_INDEX})"

safe_exec sudo mkdir -p "$WORKDIR/mnt_rootfs"
safe_exec sudo mount "${LOOPDEV}p${ROOTFS_PARTITION_INDEX}" "$WORKDIR/mnt_rootfs"

# Copy Guix system from rootfs image
LOOPROOT=$(sudo losetup --show -fP "$WORKDIR/rootfs.img")
safe_exec sudo mkdir -p "$WORKDIR/mnt_src_rootfs"
safe_exec sudo mount "${LOOPROOT}p1" "$WORKDIR/mnt_src_rootfs" 2>/dev/null || {
	# If partition detection fails, try the device directly
	log_info "Trying direct mount of rootfs image..."
	safe_exec sudo mount "$WORKDIR/rootfs.img" "$WORKDIR/mnt_src_rootfs"
}

log_info "Copying Guix system to rootfs partition..."
total_bytes=$(sudo du -sb "$WORKDIR/mnt_src_rootfs" | cut -f1)
(cd "$WORKDIR/mnt_src_rootfs" && sudo tar cf - .) |
	pv -s "$total_bytes" |
	(cd "$WORKDIR/mnt_rootfs" && sudo tar xf -)

safe_exec sudo umount "$WORKDIR/mnt_src_rootfs"
safe_exec sudo losetup -d "$LOOPROOT"
LOOPROOT=""

# Write build metadata
safe_exec sudo mkdir -p "$WORKDIR/mnt_rootfs/etc"
safe_exec sudo tee "$WORKDIR/mnt_rootfs/etc/guix-shimboot-build.json" >/dev/null <<EOF
{
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build_host": "$(hostname)",
  "board": "$BOARD",
  "rootfs_flavor": "$ROOTFS_FLAVOR",
  "drivers_mode": "$DRIVERS_MODE",
  "firmware_upstream": "$FIRMWARE_UPSTREAM",
  "guix_commit": "$(guix describe 2>/dev/null | head -1 || echo unknown)",
  "script_version": "1.0",
  "image_size_mb": "$TOTAL_SIZE_MB"
}
EOF

# Driver placement
populate_vendor() {
	safe_exec sudo mkdir -p "$WORKDIR/mnt_vendor"
	safe_exec sudo mount "${LOOPDEV}p4" "$WORKDIR/mnt_vendor"
	safe_exec sudo mkdir -p "$WORKDIR/mnt_vendor/lib/modules" "$WORKDIR/mnt_vendor/lib/firmware"

	if [ -d "$HARVEST_OUT/lib/modules" ]; then
		log_info "Copying modules to vendor..."
		safe_exec sudo cp -a "$HARVEST_OUT/lib/modules/." "$WORKDIR/mnt_vendor/lib/modules/"
	fi

	if [ -d "$HARVEST_OUT/lib/firmware" ]; then
		log_info "Copying firmware to vendor..."
		safe_exec sudo cp -a "$HARVEST_OUT/lib/firmware/." "$WORKDIR/mnt_vendor/lib/firmware/"
	fi

	safe_exec sudo sync
	safe_exec sudo umount "$WORKDIR/mnt_vendor"
}

inject_drivers() {
	log_info "Injecting drivers into rootfs..."
	if [ -d "$HARVEST_OUT/lib/modules" ]; then
		safe_exec sudo mkdir -p "$WORKDIR/mnt_rootfs/lib"
		safe_exec sudo cp -a "$HARVEST_OUT/lib/modules" "$WORKDIR/mnt_rootfs/lib/modules"
	fi
	if [ -d "$HARVEST_OUT/lib/firmware" ]; then
		safe_exec sudo mkdir -p "$WORKDIR/mnt_rootfs/lib/firmware"
		safe_exec sudo cp -a "$HARVEST_OUT/lib/firmware/." "$WORKDIR/mnt_rootfs/lib/firmware/"
	fi
	if [ -d "$HARVEST_OUT/modprobe.d" ]; then
		safe_exec sudo mkdir -p "$WORKDIR/mnt_rootfs/lib/modprobe.d" "$WORKDIR/mnt_rootfs/etc/modprobe.d"
		safe_exec sudo cp -a "$HARVEST_OUT/modprobe.d/." "$WORKDIR/mnt_rootfs/lib/modprobe.d/" 2>/dev/null || true
		safe_exec sudo cp -a "$HARVEST_OUT/modprobe.d/." "$WORKDIR/mnt_rootfs/etc/modprobe.d/" 2>/dev/null || true
	fi
}

case "$DRIVERS_MODE" in
vendor)
	populate_vendor
	;;
both)
	populate_vendor
	inject_drivers
	;;
inject)
	if [ "$HAS_VENDOR_PARTITION" -eq 1 ]; then
		populate_vendor
	fi
	inject_drivers
	;;
none)
	log_info "DRIVERS_MODE=none; skipping driver placement"
	;;
esac

safe_exec sudo umount "$WORKDIR/mnt_rootfs"

# Unmount everything and detach
safe_exec sudo losetup -d "$LOOPDEV"
LOOPDEV=""

# === Step 12: Completion ===
log_step "Done" "Build complete"

log_info "Image:     $IMAGE"
log_info "Size:      $(du -sh "$IMAGE" 2>/dev/null | cut -f1 || echo "unknown")"
log_info "Board:     $BOARD"
log_info "Flavor:    $ROOTFS_FLAVOR"
log_info "Drivers:   $DRIVERS_MODE"
log_info "Elapsed:   $((SECONDS / 60))m $((SECONDS % 60))s"

# === Optional inspection ===
if [ "$INSPECT_AFTER" -eq 1 ]; then
	CURRENT_STEP="Inspect"
	log_step "$CURRENT_STEP" "Inspecting final image"
	safe_exec sudo partx -o NR,START,END,SIZE,TYPE,NAME,UUID -g --show "$IMAGE"

	LOOPDEV=$(sudo losetup --show -fP "$IMAGE")
	mkdir -p "$WORKDIR/inspect_rootfs"
	safe_exec sudo mount "${LOOPDEV}p${ROOTFS_PARTITION_INDEX}" "$WORKDIR/inspect_rootfs"
	sudo ls -la "$WORKDIR/inspect_rootfs"

	if [ -L "$WORKDIR/inspect_rootfs/var/guix/profiles/system" ]; then
		log_info "Guix system profile: $(readlink "$WORKDIR/inspect_rootfs/var/guix/profiles/system")"
	fi

	if [ -f "$WORKDIR/inspect_rootfs/var/guix/profiles/system/init" ]; then
		log_info "Init found: /var/guix/profiles/system/init"
	else
		log_warn "Init not found at /var/guix/profiles/system/init"
	fi

	safe_exec sudo umount "$WORKDIR/inspect_rootfs"
	safe_exec sudo losetup -d "$LOOPDEV"
	LOOPDEV=""
fi

# === Next steps ===
echo
	log_info "Next steps:"
	log_info "  Write to USB:  sudo dd if=$IMAGE of=/dev/sdX bs=4M conv=fsync"
	log_info "  Or use:         tools/write/write-guix-image.sh --board $BOARD --image $IMAGE"
	log_info "  Inspect:        ./assemble-guix-image.sh --board $BOARD --inspect"