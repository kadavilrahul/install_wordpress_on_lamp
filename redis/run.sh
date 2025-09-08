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

# Redis menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                          Redis Cache Management"
    echo "                        Performance Optimization Tool"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# Redis menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                          Redis Cache Management"
    echo -e "=============================================================================${NC}"
    echo "1. Configure Redis Cache    - Set up Redis caching for performance"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "configure"|"config") execute_script "$SCRIPT_DIR/configure.sh" "Configure Redis Cache" ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            echo -e "${YELLOW}Available commands:${NC}"
            echo "  configure - Configure Redis cache"
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
        echo -n "Enter option (0-1): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/configure.sh" "Configure Redis Cache" ;;
            0) 
                echo -e "${GREEN}Returning to main menu...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-1.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"