#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    
    # Make script_path absolute
    script_path="$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: $script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    info "Launching $script_name..."
    
    # Change to script directory and run, then return to original directory
    local original_dir="$(pwd)"
    cd "$SCRIPT_DIR"
    bash "$script_path"
    local exit_code=$?
    cd "$original_dir"
    
    if [ $exit_code -eq 0 ]; then
        success "$script_name completed successfully"
    else
        warn "$script_name exited with code $exit_code"
    fi
    
    read -p "Press Enter to continue..."
    return $exit_code
}

# Backup/Restore menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                      Backup & Restore Management"
    echo "                    WordPress and Database Operations"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# Backup/Restore menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                      Backup & Restore Management"
    echo -e "=============================================================================${NC}"
    echo "1. Backup WordPress Sites       ./backup_restore/run.sh backup     # Create backups of WordPress sites and databases"
    echo "2. Restore WordPress Sites      ./backup_restore/run.sh restore    # Restore WordPress sites from backups"
    echo "3. Backup Static/HTML Sites     ./backup_restore/run.sh static     # Create backups of non-WordPress websites"
    echo "4. Restore Static/HTML Sites    ./backup_restore/run.sh staticrestore # Restore non-WordPress websites from backups"
    echo "5. Backup WordPress + PostgreSQL ./backup_restore/run.sh wppg       # Combined WordPress and PostgreSQL backup"
    echo "6. Restore WordPress + PostgreSQL ./backup_restore/run.sh wppgrestore # Combined WordPress and PostgreSQL restore"
    echo "7. Transfer Backups to Server   ./backup_restore/run.sh transfer   # Transfer backups to another server via SSH/SCP"
    echo "8. Backup PostgreSQL            ./backup_restore/run.sh pgbackup   # Create PostgreSQL database backups"
    echo "9. Restore PostgreSQL           ./backup_restore/run.sh pgrestore  # Restore PostgreSQL database from backup"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Show CLI help
show_cli_help() {
    echo -e "${CYAN}============================================================================="
    echo "                    Backup & Restore CLI Commands"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Usage:${NC} ./backup_restore/run.sh <command>"
    echo ""
    echo -e "${GREEN}Available Commands:${NC}"
    echo "  backup        - Backup WordPress sites"
    echo "  restore       - Restore WordPress sites"
    echo "  static        - Backup static/HTML sites"
    echo "  staticrestore - Restore static/HTML sites"
    echo "  wppg          - Backup WordPress + PostgreSQL"
    echo "  wppgrestore   - Restore WordPress + PostgreSQL"
    echo "  transfer      - Transfer backups to server"
    echo "  pgbackup      - Backup PostgreSQL"
    echo "  pgrestore     - Restore PostgreSQL"
    echo "  --help        - Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./backup_restore/run.sh backup"
    echo "  ./backup_restore/run.sh restore"
    echo "  ./backup_restore/run.sh static"
    echo "  ./backup_restore/run.sh wppg"
    echo "  ./backup_restore/run.sh transfer"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "backup") execute_script "$SCRIPT_DIR/backup_wordpress.sh" "WordPress Backup" ;;
        "restore") execute_script "$SCRIPT_DIR/restore_wordpress.sh" "WordPress Restore" ;;
        "static") execute_script "$SCRIPT_DIR/backup_static_sites.sh" "Static Sites Backup" ;;
        "staticrestore") execute_script "$SCRIPT_DIR/restore_static_sites.sh" "Static Sites Restore" ;;
        "wppg") execute_script "$SCRIPT_DIR/backup_wordpress_postgresql.sh" "WordPress + PostgreSQL Backup" ;;
        "wppgrestore") execute_script "$SCRIPT_DIR/restore_wordpress_postgresql.sh" "WordPress + PostgreSQL Restore" ;;
        "transfer") execute_script "$SCRIPT_DIR/transfer_backups.sh" "Transfer Backups to Server" ;;
        "pgbackup") execute_script "$SCRIPT_DIR/backup_postgresql.sh" "PostgreSQL Backup" ;;
        "pgrestore") execute_script "$SCRIPT_DIR/restore_postgresql.sh" "PostgreSQL Restore" ;;
        "--help"|"-h"|"help") 
            show_cli_help
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            show_cli_help
            exit 1
            ;;
    esac
}

# Main execution
main() {
    check_root
    
    if [ $# -gt 0 ]; then
        handle_cli_command "$1"
        exit $?
    fi
    
    while true; do
        show_menu
        echo -n "Enter option (0-9): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/backup_wordpress.sh" "WordPress Backup" ;;
            2) execute_script "$SCRIPT_DIR/restore_wordpress.sh" "WordPress Restore" ;;
            3) execute_script "$SCRIPT_DIR/backup_static_sites.sh" "Static Sites Backup" ;;
            4) execute_script "$SCRIPT_DIR/restore_static_sites.sh" "Static Sites Restore" ;;
            5) execute_script "$SCRIPT_DIR/backup_wordpress_postgresql.sh" "WordPress + PostgreSQL Backup" ;;
            6) execute_script "$SCRIPT_DIR/restore_wordpress_postgresql.sh" "WordPress + PostgreSQL Restore" ;;
            7) execute_script "$SCRIPT_DIR/transfer_backups.sh" "Transfer Backups to Server" ;;
            8) execute_script "$SCRIPT_DIR/backup_postgresql.sh" "PostgreSQL Backup" ;;
            9) execute_script "$SCRIPT_DIR/restore_postgresql.sh" "PostgreSQL Restore" ;;
            0) 
                echo -e "${GREEN}Returning to main menu...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-9.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"