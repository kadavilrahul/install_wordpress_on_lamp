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

# WordPress menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                         WordPress Management Tools"
    echo "                      Installation and Maintenance"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# WordPress menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                         WordPress Management Tools"
    echo -e "=============================================================================${NC}"
    echo "1. Install LAMP Stack + WordPress    ./wordpress/run.sh install   # Complete LAMP installation with WordPress setup"
    echo "2. Install PostgreSQL + Extensions   ./wordpress/run.sh postgres  # Install PostgreSQL with extensions"
    echo "3. Remove Websites & Databases       ./wordpress/run.sh remove    # Clean removal of websites and data"
    echo "4. Remove Orphaned Databases         ./wordpress/run.sh cleanup   # Clean up databases without websites"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Show CLI help
show_cli_help() {
    echo -e "${CYAN}============================================================================="
    echo "                    WordPress Management CLI Commands"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Usage:${NC} ./wordpress/run.sh <command>"
    echo ""
    echo -e "${GREEN}Available Commands:${NC}"
    echo "  install   - Install LAMP Stack + WordPress"
    echo "  remove    - Remove websites & databases"
    echo "  cleanup   - Remove orphaned databases"
    echo "  postgres  - Install PostgreSQL with extensions"
    echo "  --help    - Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./wordpress/run.sh install"
    echo "  ./wordpress/run.sh remove"
    echo "  ./wordpress/run.sh cleanup"
    echo "  ./wordpress/run.sh postgres"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "install"|"lamp") execute_script "$SCRIPT_DIR/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
        "remove") execute_script "$SCRIPT_DIR/remove_websites_databases.sh" "Remove Websites & Databases" ;;
        "cleanup"|"orphan") execute_script "$SCRIPT_DIR/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
        "postgres"|"pg") execute_script "$SCRIPT_DIR/install_postgresql.sh" "PostgreSQL Installation" ;;
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
        echo -n "Enter option (0-4): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
            2) execute_script "$SCRIPT_DIR/install_postgresql.sh" "PostgreSQL Installation with Extensions" ;;
            3) execute_script "$SCRIPT_DIR/remove_websites_databases.sh" "Remove Websites & Databases" ;;
            4) execute_script "$SCRIPT_DIR/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
            0) 
                echo -e "${GREEN}Returning to main menu...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-4.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"