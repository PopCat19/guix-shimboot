#!/usr/bin/env bash
#
# bulk-conventions.sh
#
# Purpose: Execute dev-conventions commands across multiple repositories
#
# This script:
# - Finds all instances of dev-conventions.sh under a root directory
# - Filters targets by inclusion/exclusion patterns
# - Displays affected repositories and waits for a 10s countdown
# - Executes the specified command in each target directory
#
# Usage:
#   ./bulk-conventions.sh [options] <command> [command-args]
#
# Options:
#   --root DIR       Root directory to search (default: .)
#   --include PAT    Regex pattern for directories to include
#   --exclude PAT    Regex pattern for directories to exclude
#   --yes, -y        Skip countdown
#
# Examples:
#   ./bulk-conventions.sh sync --push
#   ./bulk-conventions.sh --include "popcat" sync
#   ./bulk-conventions.sh --exclude "legacy" lint --format

set -Eeuo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SH="${SCRIPT_DIR}/conventions/src/lib.sh"

# Source library for logging and colors if available
# shellcheck source=conventions/src/lib.sh
if [[ -f "$LIB_SH" ]]; then
	# shellcheck disable=SC1091
	source "$LIB_SH"
else
	# Fallback colors and logging
	ANSI_CLEAR='\033[0m'
	ANSI_GREEN='\033[1;32m'
	ANSI_YELLOW='\033[1;33m'
	ANSI_RED='\033[1;31'
	ANSI_CYAN='\033[1;36m'
	log_info() { printf "${ANSI_GREEN}  → %s${ANSI_CLEAR}\n" "$1"; }
	log_warn() { printf "${ANSI_YELLOW}  ⚠ %s${ANSI_CLEAR}\n" "$1"; }
	log_error() { printf "${ANSI_RED}  ✗ %s${ANSI_CLEAR}\n" "$1"; }
	log_success() { printf "${ANSI_GREEN}  ✓ %s${ANSI_CLEAR}\n" "$1"; }
fi

# Defaults
ROOT_DIR=""
INCLUDE_PAT=""
EXCLUDE_PAT=""
SKIP_COUNTDOWN=false
HARD_OVERWRITE=false
COMMAND_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	--root)
		ROOT_DIR="$2"
		shift 2
		;;
	--include)
		INCLUDE_PAT="$2"
		shift 2
		;;
	--exclude)
		EXCLUDE_PAT="$2"
		shift 2
		;;
	--hard)
		HARD_OVERWRITE=true
		shift
		;;
	--yes | -y)
		SKIP_COUNTDOWN=true
		COMMAND_ARGS+=("$1")
		shift
		;;
	--help | -h)
		echo "Usage: $0 --root <DIR> [options] <command> [command-args]"
		echo ""
		echo "Options:"
		echo "  --root DIR       Root directory to search (required)"
		echo "  --include PAT    Regex pattern for directories to include"
		echo "  --exclude PAT    Regex pattern for directories to exclude"
		echo "  --hard           Force overwrite conventions/ from this repo before running command"
		echo "  --yes, -y        Skip countdown"
		exit 0
		;;
	*)
		COMMAND_ARGS+=("$1")
		shift
		;;
	esac
done

if [[ -z "$ROOT_DIR" ]]; then
	log_error "Root directory (--root) must be explicitly specified."
	echo "Usage: $0 --root <DIR> [options] <command> [command-args]"
	exit 1
fi

# Expand literal ~/ if present (if not already expanded by shell)
if [[ "$ROOT_DIR" == "~/"* ]]; then
	ROOT_DIR="${HOME}/${ROOT_DIR#\~/}"
elif [[ "$ROOT_DIR" == "~" ]]; then
	ROOT_DIR="${HOME}"
fi

# Warn about the root directory
log_warn "Target root directory set to: $ROOT_DIR"
if [[ "$ROOT_DIR" == "$HOME" || "$ROOT_DIR" == "/" ]]; then
	log_warn "Caution: Operating on a very broad scope ($ROOT_DIR)"
fi

if [[ ${#COMMAND_ARGS[@]} -eq 0 ]]; then
	log_error "No command provided."
	echo "Usage: $0 --root <DIR> [options] <command> [command-args]"
	exit 1
fi

log_info "Searching for dev-conventions.sh in $ROOT_DIR..."
# Find all dev-conventions.sh files, suppressing permission denied errors
if command -v rg &>/dev/null; then
	# Use ripgrep if available for speed and automatic noise filtering
	mapfile -t FOUND_SCRIPTS < <(rg --files --glob "dev-conventions.sh" "$ROOT_DIR" 2>/dev/null)
else
	# Fallback to find, suppressing stderr
	mapfile -t FOUND_SCRIPTS < <(find "$ROOT_DIR" -name "dev-conventions.sh" -not -path "*/.git/*" -type f 2>/dev/null)
fi

# Determine this script's project root to avoid self-processing
# shellcheck disable=SC2015
SELF_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

TARGETS=()
for script_path in "${FOUND_SCRIPTS[@]}"; do
	# Get directory containing the script
	script_dir="$(dirname "$script_path")"
	script_name="$(basename "$script_path")"

	# Determine the best directory to run from
	# If script is in a 'conventions' folder, run from the parent (project root)
	run_dir="$script_dir"
	exec_path="./$script_name"
	if [[ "$(basename "$script_dir")" == "conventions" ]]; then
		run_dir="$(dirname "$script_dir")"
		exec_path="./conventions/$script_name"
	fi

	# Get absolute path for execution
	abs_run_dir="$(cd "$run_dir" && pwd)"

	# Skip self
	if [[ "$abs_run_dir" == "$SELF_ROOT" ]]; then
		continue
	fi

	# Get relative path from root for filtering
	rel_path="${run_dir#"$ROOT_DIR"/}"
	[[ "$rel_path" == "$run_dir" ]] && rel_path="."

	# Filter by include
	if [[ -n "$INCLUDE_PAT" ]] && [[ ! "$rel_path" =~ $INCLUDE_PAT ]]; then
		continue
	fi

	# Filter by exclude
	if [[ -n "$EXCLUDE_PAT" ]] && [[ "$rel_path" =~ $EXCLUDE_PAT ]]; then
		continue
	fi

	# Get absolute path for execution
	abs_run_dir="$(cd "$run_dir" && pwd)"
	abs_exec_path="$exec_path"
	TARGETS+=("$abs_run_dir:$abs_exec_path")
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
	log_warn "No targets found matching criteria."
	exit 0
fi

echo ""
log_info "The following repositories/directories will be affected:"
for entry in "${TARGETS[@]}"; do
	target_dir="${entry%%:*}"
	printf "  ${ANSI_CYAN}- %s${ANSI_CLEAR}\n" "$target_dir"
done
echo ""
log_info "Command to run: dev-conventions.sh ${COMMAND_ARGS[*]}"
echo ""

	if [[ "$SKIP_COUNTDOWN" == "false" ]]; then
		printf "Starting bulk operation in: "
		for i in {10..1}; do
			printf "%s... " "$i"
			sleep 1
		done
		echo "0!"
	fi

SUCCESS_COUNT=0
FAILURE_COUNT=0

for entry in "${TARGETS[@]}"; do
	target_dir="${entry%%:*}"
	exec_path="${entry#*:}"

	echo ""
	log_info ">>> Processing: $target_dir"

	if [[ "$HARD_OVERWRITE" == "true" ]]; then
		log_info "Hard overwriting conventions in $target_dir..."
		# Copy conventions directory from this repo to target
		# Using a subshell to avoid affecting current environment and handle potential errors gracefully
		if cp -rf "${SCRIPT_DIR}/conventions" "$target_dir/"; then
			log_success "Conventions overwritten"
		else
			# If they are the same file, cp might fail; we check if it's actually an error
			if [[ "$(cd "${SCRIPT_DIR}/conventions" && pwd)" == "$(cd "$target_dir/conventions" 2>/dev/null && pwd)" ]]; then
				log_detail "Target is the same as source, skipping copy"
			else
				log_error "Failed to overwrite conventions"
				FAILURE_COUNT=$((FAILURE_COUNT + 1))
				continue
			fi
		fi
	fi

	log_info "Executing command in $target_dir: $exec_path ${COMMAND_ARGS[*]}"
	if (cd "$target_dir" && "$exec_path" "${COMMAND_ARGS[@]}"); then
		log_success "Completed: $target_dir"
		SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
	else
		log_error "Failed: $target_dir"
		FAILURE_COUNT=$((FAILURE_COUNT + 1))
	fi
done

echo ""
if [[ $FAILURE_COUNT -eq 0 ]]; then
	log_success "Bulk operation complete. Successfully processed $SUCCESS_COUNT targets."
else
	log_warn "Bulk operation finished with errors."
	log_detail "Success: $SUCCESS_COUNT"
	log_error "Failures: $FAILURE_COUNT"
	exit 1
fi
