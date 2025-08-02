#!/bin/bash

#================================================================================
# rclone Package Installation Script
#================================================================================

# --- Globals & Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/config.json"
BACKUP_SOURCE="/website_backups"
LOG_DIR="/var/log"

# --- Utility Functions ---
info() { echo -e "${BLUE}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }

press_enter() { read -p $'\nPress [Enter] to continue...' "$@"; }

check_root() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root (e.g., 'sudo ./rclone.sh')"
}

install_rclone_package() {
    info "Installing rclone package..."
    if command -v rclone &>/dev/null; then
        warn "rclone is already installed."
    else
        apt-get update && apt-get install -y rclone || error "Failed to install rclone."
        success "rclone package installed successfully."
    fi

    if ! command -v jq &>/dev/null; then
        info "Installing jq..."
        apt-get install -y jq || error "Failed to install jq."
    fi
}

# Main execution
main() {
    check_root
    echo -e "${CYAN}======================================================================${NC}"
    echo "                         rclone Package Installation"
    echo -e "${CYAN}======================================================================${NC}"
    install_rclone_package
    press_enter
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"