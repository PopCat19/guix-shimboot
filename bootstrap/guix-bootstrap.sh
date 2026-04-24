#!/usr/bin/env bash
# Guix Bootstrap Functions
#
# Purpose: Guix-specific generation detection and boot functions
#
# This module:
# - Detects Guix system profiles
# - Lists Guix generations
# - Provides Guix init path

set -Eeuo pipefail

# === Guix Detection ===

is_guix_root() {
    local root_dir="$1"
    [ -d "$root_dir/var/guix/profiles/system" ]
}

guix_system_link() {
    local root_dir="${1:-/newroot}"
    echo "$root_dir/var/guix/profiles/system"
}

guix_init_path() {
    local root_dir="${1:-/newroot}"
    echo "$root_dir/var/guix/profiles/system/init"
}

# === Generation Listing ===

list_guix_generations() {
    local root_dir="${1:-/newroot}"
    local system_link
    system_link="$(guix_system_link "$root_dir")"

    if [ ! -L "$system_link" ]; then
        return 1
    fi

    local generations_dir
    generations_dir="$(dirname "$system_link")/links"

    if [ ! -d "$generations_dir" ]; then
        return 1
    fi

    # List generations sorted by number (newest first)
    find "$generations_dir" -maxdepth 1 -type l -name "system-*" 2>/dev/null \
        | sed 's/.*system-//' \
        | sort -t- -k1 -rn \
        | head -20
}

guix_generation_path() {
    local root_dir="$1"
    local gen_num="$2"
    local system_link
    system_link="$(guix_system_link "$root_dir")"

    if [ "$gen_num" = "current" ]; then
        readlink -f "$system_link"
    else
        readlink -f "$(dirname "$system_link")/links/system-$gen_num-link"
    fi
}

# === Guix Menu Entry ===

guix_menu_entry() {
    local gen_num="$1"
    local gen_path="$2"
    local kernel_version

    # Try to extract kernel version from generation
    kernel_version="$(basename "$(ls -d "$gen_path/kernel" 2>/dev/null | head -1)" 2>/dev/null || echo "unknown")"

    echo "Guix System (gen $gen_num) [$kernel_version]"
}

# === Integration with bootstrap.sh ===
# Add to is_rootfs_guix() in modified bootstrap.sh:

# is_rootfs_guix() {
#     local root_dir="$1"
#     is_guix_root "$root_dir"
# }
#
# get_guix_init() {
#     local root_dir="$1"
#     guix_init_path "$root_dir"
# }