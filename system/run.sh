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

# System menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                          System Management Tools"
    echo "                      Monitoring and Administration"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# System menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                          System Management Tools"
    echo -e "=============================================================================${NC}"
    echo "1. System Status Check        - View system resources and service status"
    echo "2. Disk Space Monitor         - Monitor storage usage and cleanup"
    echo "3. Toggle Root SSH Access     - Enable or disable SSH root login"
    echo "4. Install System Utilities   - Install common system tools"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "status") execute_script "$SCRIPT_DIR/status_check.sh" "System Status Check" ;;
        "disk") execute_script "$SCRIPT_DIR/disk_space_monitor.sh" "Disk Space Monitor" ;;
        "ssh") execute_script "$SCRIPT_DIR/toggle_root_ssh.sh" "Toggle Root SSH Access" ;;
        "utils"|"utilities") execute_script "$SCRIPT_DIR/install_utilities.sh" "Install System Utilities" ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            echo -e "${YELLOW}Available commands:${NC}"
            echo "  status    - System status check"
            echo "  disk      - Disk space monitor"
            echo "  ssh       - Toggle root SSH access"
            echo "  utils     - Install system utilities"
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
            1) execute_script "$SCRIPT_DIR/status_check.sh" "System Status Check" ;;
            2) execute_script "$SCRIPT_DIR/disk_space_monitor.sh" "Disk Space Monitor" ;;
            3) execute_script "$SCRIPT_DIR/toggle_root_ssh.sh" "Toggle Root SSH Access" ;;
            4) execute_script "$SCRIPT_DIR/install_utilities.sh" "Install System Utilities" ;;
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