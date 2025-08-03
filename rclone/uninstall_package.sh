#!/bin/bash

#================================================================================
# rclone Package Uninstallation Script
#================================================================================

# --- Globals & Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config.json"
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

uninstall_rclone_package() {
    warn "This will UNINSTALL the rclone package and DELETE ALL remotes and cron jobs."
    read -p "Are you sure you want to completely uninstall rclone? (y/n) " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Uninstallation cancelled."
        return
    fi

    info "Removing all rclone-related cron jobs..."
    crontab -l 2>/dev/null | grep -v "/usr/bin/rclone" | crontab - || warn "Failed to remove cron jobs."

    info "Deleting all rclone configurations..."
    rm -rf "$HOME/.config/rclone" || warn "Failed to delete rclone configurations."

    info "Purging rclone package..."
    apt-get remove --purge -y rclone || error "Failed to uninstall rclone."

    success "rclone has been completely uninstalled from the system."
}

# Main execution
main() {
    check_root
    echo -e "${CYAN}======================================================================${NC}"
    echo "                         rclone Package Uninstallation"
    echo -e "${CYAN}======================================================================${NC}"
    uninstall_rclone_package
    press_enter
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"