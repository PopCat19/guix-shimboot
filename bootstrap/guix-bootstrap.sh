# guix-bootstrap.sh
#
# Purpose: Guix-specific generation detection and boot functions
#
# This module:
# - Detects Guix system profiles
# - Lists Guix generations
# - Provides Guix init path
#
# Usage: source this file, then call functions
#   source guix-bootstrap.sh
#   is_guix_root "/newroot"

# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR/../shimboot-core/tools/lib

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
    # shellcheck disable=SC2012
    kernel_version="$(basename "$(ls -d "$gen_path/kernel" 2>/dev/null | head -1)" 2>/dev/null || echo "unknown")"

    echo "Guix System (gen $gen_num) [$kernel_version]"
}

# === Standalone test runner ===

test_guix_detection() {
	local test_root="${1:-/var/guix/profiles}"
	log_info "Testing Guix detection at: $test_root"

	if is_guix_root "$test_root"; then
		log_info "Guix system detected"
		log_info "Generations:"
		list_guix_generations "$test_root" | head -5
	else
		log_info "Not a Guix root: $test_root"
	fi
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
	# Source logging if available
	# shellcheck disable=SC1091
	if [[ -f "${BASH_SOURCE[0]%/*}/../shimboot-core/tools/lib/logging.sh" ]]; then
		# shellcheck disable=SC1091
		source "${BASH_SOURCE[0]%/*}/../shimboot-core/tools/lib/logging.sh"
	fi

	case "${1:-}" in
		test)
			test_guix_detection "${2:-/var/guix/profiles}"
			;;
		*)
			echo "Usage: $0 test [root-dir]"
			echo "Functions are meant to be sourced, not executed."
			echo "  source $0"
			;;
	esac
fi