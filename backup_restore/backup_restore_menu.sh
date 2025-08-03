#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

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

# Backup/Restore menu
show_backup_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            Backup/Restore Menu"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}Backup/Restore Options:${NC}"
        echo "  1) Backup WordPress - Create backup of WordPress site and database"
        echo "  2) Restore WordPress - Restore WordPress site from backup"
        echo "  3) Backup PostgreSQL - Create backup of PostgreSQL database"
        echo "  4) Restore PostgreSQL - Restore PostgreSQL database from backup"
        echo "  5) Transfer Backups - Transfer backups to remote storage"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-5): " backup_choice
        case $backup_choice in
            1) execute_script "$SCRIPT_DIR/backup_wordpress.sh" "WordPress Backup" ;;
            2) execute_script "$SCRIPT_DIR/restore_wordpress.sh" "WordPress Restore" ;;
            3) execute_script "$SCRIPT_DIR/backup_postgresql.sh" "PostgreSQL Backup" ;;
            4) execute_script "$SCRIPT_DIR/restore_postgresql.sh" "PostgreSQL Restore" ;;
            5) execute_script "$SCRIPT_DIR/transfer_backups.sh" "Transfer Backups" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Main execution
main() {
    check_root
    show_backup_menu
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"