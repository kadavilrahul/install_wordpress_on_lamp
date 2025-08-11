#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Execute script with error handling
execute_script() {
    local script_path="$1"
    local script_name="$2"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: $script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    info "Launching $script_name..."
    bash "$script_path"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "$script_name completed successfully"
    else
        warn "$script_name exited with code $exit_code"
    fi
    
    read -p "Press Enter to continue..."
    return $exit_code
}

# Rclone Management Menu
rclone_menu() {
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            Rclone Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}Rclone Options:${NC}"
        echo "  1) Install Rclone Package - Install rclone for cloud storage management"
        echo "  2) Manage Remote Storage - Configure cloud storage connections"
        echo "  3) Show Remote Connections - Display configured remote storage services"
        echo "  4) Show Rclone Status - Check rclone service status and configuration"
        echo "  5) Uninstall Rclone Package - Remove rclone from the system"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-5): " rclone_choice
        case $rclone_choice in
            1) execute_script "$script_dir/install_package.sh" "Install Rclone Package" ;;
            2) execute_script "$script_dir/manage_remote.sh" "Manage Remote Storage" ;;
            3) execute_script "$script_dir/show_remotes.sh" "Show Remote Connections" ;;
            4) execute_script "$script_dir/show_status.sh" "Show Rclone Status" ;;
            5) execute_script "$script_dir/uninstall_package.sh" "Uninstall Rclone Package" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Main execution
main() {
    check_root
    echo -e "${YELLOW}Rclone Management Tool${NC}"
    echo "This tool manages cloud storage backups with Google Drive using Rclone."
    echo
    rclone_menu
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"