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

# Rclone menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                        Cloud Storage Management"
    echo "                          Rclone Configuration"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# Rclone menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                        Cloud Storage Management"
    echo -e "=============================================================================${NC}"
    echo "1. Install Rclone Package        - Download and install rclone with dependencies"
    echo "2. Manage Remote Storage         - Configure cloud storage authentication"
    echo "3. Show Configured Remotes       - Display remotes and accessibility"
    echo "4. Check Rclone Status           - View rclone setup and configuration"
    echo "5. Setup Backup Automation       - Configure automatic backup scheduling"
    echo "6. Uninstall Rclone              - Remove rclone and all configurations"
    echo "7. Advanced Rclone Menu          - Access advanced rclone options"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "install") execute_script "$SCRIPT_DIR/install_package.sh" "Install Rclone Package" ;;
        "manage"|"config") execute_script "$SCRIPT_DIR/manage_remote.sh" "Manage Remote Storage" ;;
        "remotes"|"show") execute_script "$SCRIPT_DIR/show_remotes.sh" "Show Configured Remotes" ;;
        "status") execute_script "$SCRIPT_DIR/show_status.sh" "Check Rclone Status" ;;
        "cron"|"automation") execute_script "$SCRIPT_DIR/setup_backup_cron.sh" "Setup Backup Automation" ;;
        "uninstall") execute_script "$SCRIPT_DIR/uninstall_package.sh" "Uninstall Rclone" ;;
        "menu") execute_script "$SCRIPT_DIR/rclone_menu.sh" "Advanced Rclone Menu" ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            echo -e "${YELLOW}Available commands:${NC}"
            echo "  install    - Install rclone package"
            echo "  manage     - Manage remote storage"
            echo "  remotes    - Show configured remotes"
            echo "  status     - Check rclone status"
            echo "  cron       - Setup backup automation"
            echo "  uninstall  - Uninstall rclone"
            echo "  menu       - Advanced rclone menu"
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
            1) execute_script "$SCRIPT_DIR/install_package.sh" "Install Rclone Package" ;;
            2) execute_script "$SCRIPT_DIR/manage_remote.sh" "Manage Remote Storage" ;;
            3) execute_script "$SCRIPT_DIR/show_remotes.sh" "Show Configured Remotes" ;;
            4) execute_script "$SCRIPT_DIR/show_status.sh" "Check Rclone Status" ;;
            5) execute_script "$SCRIPT_DIR/setup_backup_cron.sh" "Setup Backup Automation" ;;
            6) execute_script "$SCRIPT_DIR/uninstall_package.sh" "Uninstall Rclone" ;;
            7) execute_script "$SCRIPT_DIR/rclone_menu.sh" "Advanced Rclone Menu" ;;
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