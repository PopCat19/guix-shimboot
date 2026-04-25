#!/usr/bin/env bash

# logging.sh
#
# Purpose: Provide unified logging functions with ANSI colors
#
# This module:
# - Defines ANSI color codes (auto-detects terminal support)
# - Provides log_step, log_info, log_warn, log_error, log_success
# - Delegates to shimboot-core logging if available

# shellcheck shell=bash

# Prefer shared logging from shimboot-core submodule
SHIMBOOT_CORE_LIB="${BASH_SOURCE[0]%/*}/../../../shimboot-core/tools/lib/logging.sh"
if [[ -f "$SHIMBOOT_CORE_LIB" ]]; then
	# shellcheck source=/dev/null
	source "$SHIMBOOT_CORE_LIB"
	return 0 2>/dev/null
fi

# Fallback implementation
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	ANSI_CLEAR='\033[0m'
	ANSI_BOLD='\033[1m'
	ANSI_GREEN='\033[1;32m'
	ANSI_BLUE='\033[1;34m'
	ANSI_YELLOW='\033[1;33m'
	ANSI_RED='\033[1;31m'
else
	ANSI_CLEAR=''
	ANSI_BOLD=''
	ANSI_GREEN=''
	ANSI_BLUE=''
	ANSI_YELLOW=''
	ANSI_RED=''
fi

log_step() {
	printf "${ANSI_BOLD}${ANSI_BLUE}[%s] %s${ANSI_CLEAR}\n" "$1" "$2"
}

log_info() {
	printf "${ANSI_GREEN}  > %s${ANSI_CLEAR}\n" "$1"
}

log_warn() {
	printf "${ANSI_YELLOW}  ! %s${ANSI_CLEAR}\n" "$1"
}

log_error() {
	printf "${ANSI_RED}  X %s${ANSI_CLEAR}\n" "$1"
}

log_success() {
	printf "${ANSI_GREEN}  OK %s${ANSI_CLEAR}\n" "$1"
}