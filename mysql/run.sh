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

# MySQL menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                         MySQL Database Management"
    echo "                      Configuration and Administration"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# MySQL menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                         MySQL Database Management"
    echo -e "=============================================================================${NC}"
    echo "1. Configure Remote Access       ./mysql/run.sh remote      # Set up MySQL for remote connections"
    echo "2. Check Remote Access Status    ./mysql/run.sh check       # Verify MySQL remote accessibility"
    echo "3. Show Databases                ./mysql/run.sh show        # Display all databases in MySQL server"
    echo "4. List Users                    ./mysql/run.sh users       # Show all MySQL user accounts and permissions"
    echo "5. Get Database Size             ./mysql/run.sh size        # Check storage usage of databases"
    echo "6. Install phpMyAdmin            ./mysql/run.sh phpmyadmin  # Set up web-based MySQL administration"
    echo "7. Enable Auto Log Purging       ./mysql/run.sh purge       # Configure automatic binary log cleanup"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Show CLI help
show_cli_help() {
    echo -e "${CYAN}============================================================================="
    echo "                    MySQL CLI Commands"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Usage:${NC} ./mysql/run.sh <command>"
    echo ""
    echo -e "${GREEN}Available Commands:${NC}"
    echo "  remote      - Configure MySQL remote access"
    echo "  check       - Check remote access status"  
    echo "  show        - Show databases"
    echo "  users       - List MySQL users"
    echo "  size        - Get database size"
    echo "  phpmyadmin  - Install phpMyAdmin"
  echo "  purge       - Enable auto log purging"
  echo "  --help      - Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./mysql/run.sh remote"
    echo "  ./mysql/run.sh show"
    echo "  ./mysql/run.sh users"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "remote") execute_script "$SCRIPT_DIR/remote_access.sh" "MySQL Remote Access Configuration" ;;
        "checkdb"|"check") execute_script "$SCRIPT_DIR/check_remote_access.sh" "Check MySQL Remote Access" ;;
        "showdb"|"show") execute_script "$SCRIPT_DIR/show_databases.sh" "Show MySQL Databases" ;;
        "users"|"list") execute_script "$SCRIPT_DIR/list_users.sh" "List MySQL Users" ;;
        "dbsize"|"size") execute_script "$SCRIPT_DIR/get_database_size.sh" "Get Database Size" ;;
        "phpmyadmin") execute_script "$SCRIPT_DIR/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
        "purge") execute_script "$SCRIPT_DIR/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;

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
        echo -n "Enter option (0-7): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/remote_access.sh" "MySQL Remote Access Configuration" ;;
            2) execute_script "$SCRIPT_DIR/check_remote_access.sh" "Check MySQL Remote Access" ;;
            3) execute_script "$SCRIPT_DIR/show_databases.sh" "Show MySQL Databases" ;;
            4) execute_script "$SCRIPT_DIR/list_users.sh" "List MySQL Users" ;;
            5) execute_script "$SCRIPT_DIR/get_database_size.sh" "Get Database Size" ;;
            6) execute_script "$SCRIPT_DIR/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
            7) execute_script "$SCRIPT_DIR/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;
            0) 
                echo -e "${GREEN}Returning to main menu...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-7.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"