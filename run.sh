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

# Main menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                    WordPress Master Installation Tool"
    echo "                   Comprehensive LAMP Stack Management"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# Main menu
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                            Website Master"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Main Menu:${NC}"
    echo "  1) Install LAMP Stack + WordPress - Complete LAMP installation with WordPress setup"
    echo "  2) Backup/Restore - Backup and restore WordPress sites and databases"
    echo "  3) MySQL Management - Database operations and remote access configuration"
    echo "  4) Check MySQL Remote Access - Verify if MySQL is accessible from remote locations"
    echo "  5) PHP Management - PHP configuration and information tools"
    echo "  6) Troubleshooting - Diagnose and fix common website issues"
    echo "  7) Rclone Management - Manage cloud storage backups with Google Drive"
    echo "  8) Configure Redis - Set up Redis caching for better performance"
        echo "  9) System Management - System monitoring, utilities, and SSH configuration"
        echo "  10) Website Management - Remove websites, databases, and cleanup operations"
        echo "  11) Apache Management - Apache configuration and SSL management"
        echo "  0) Exit - Close the Website Master tool"
    echo -e "${CYAN}=============================================================================${NC}"
}

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

# Submenu for MySQL Management
mysql_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            MySQL Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}MySQL Options:${NC}"
        echo "  1) Configure Remote Access - Set up MySQL for remote connections"
        echo "  2) Show Databases - Display all databases in MySQL server"
        echo "  3) List MySQL Users - Show all MySQL user accounts and hosts"
        echo "  4) Get Database Size - Check storage usage of specific database"
        echo "  5) Install phpMyAdmin - Set up web-based MySQL administration tool"
        echo "  6) Enable Automatic Log Purging - Configure MySQL to automatically purge old binary logs"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-6): " mysql_choice
        case $mysql_choice in
            1) execute_script "$SCRIPT_DIR/mysql/remote_access.sh" "MySQL Remote Access Configuration" ;;
            2) execute_script "$SCRIPT_DIR/mysql/show_databases.sh" "Show MySQL Databases" ;;
            3) execute_script "$SCRIPT_DIR/mysql/list_users.sh" "List MySQL Users" ;;
            4) execute_script "$SCRIPT_DIR/mysql/get_database_size.sh" "Get Database Size" ;;
            5) execute_script "$SCRIPT_DIR/mysql/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
            6) execute_script "$SCRIPT_DIR/mysql/enable_auto_log_purging.sh" "Enable Automatic Log Purging" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Submenu for PHP Management
php_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            PHP Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}PHP Options:${NC}"
        echo "  1) Adjust PHP Settings - Optimize PHP configuration for web applications"
        echo "  2) View PHP Info - Display PHP version and configuration details"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-2): " php_choice
        case $php_choice in
            1) execute_script "$SCRIPT_DIR/php/adjust_settings.sh" "Adjust PHP Settings" ;;
            2) execute_script "$SCRIPT_DIR/php/view_info.sh" "View PHP Information" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Submenu for System Management
system_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            System Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}System Options:${NC}"
        echo "  1) System Status Check - View system resources and service status"
        echo "  2) Disk Space Monitor - Monitor storage usage and clean system files"
        echo "  3) Toggle Root SSH - Enable or disable SSH root login access"
        echo "  4) Install System Utilities - Install common system tools and utilities"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-4): " system_choice
        case $system_choice in
            1) execute_script "$SCRIPT_DIR/system/status_check.sh" "System Status Check" ;;
            2) execute_script "$SCRIPT_DIR/system/disk_space_monitor.sh" "Disk Space Monitor" ;;
            3) execute_script "$SCRIPT_DIR/system/toggle_root_ssh.sh" "Toggle Root SSH" ;;
            4) execute_script "$SCRIPT_DIR/system/install_utilities.sh" "Install System Utilities" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Submenu for Website Management
website_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            Website Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}Website Options:${NC}"
        echo "  1) Remove Websites & Databases - Clean removal of websites and associated data"
        echo "  2) Remove Orphaned Databases - Clean up databases without corresponding websites"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-2): " website_choice
        case $website_choice in
            1) execute_script "$SCRIPT_DIR/wordpress/remove_websites_databases.sh" "Remove Websites & Databases" ;;
            2) execute_script "$SCRIPT_DIR/wordpress/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Submenu for Apache Management
apache_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================================================="
        echo "                            Apache Management"
        echo -e "=============================================================================${NC}"
        echo -e "${YELLOW}Apache Options:${NC}"
        echo "  1) Install Apache + SSL Only - Set up web server with SSL for existing domains"
        echo "  2) Fix Apache Configs - Repair broken Apache virtual host configurations"
        echo "  0) Back to Main Menu"
        echo -e "${CYAN}=============================================================================${NC}"
        
        read -p "Select option (0-2): " apache_choice
        case $apache_choice in
            1) execute_script "$SCRIPT_DIR/apache/install_ssl_only.sh" "Install Apache + SSL Only" ;;
            2) execute_script "$SCRIPT_DIR/apache/fix_configs.sh" "Fix Apache Configs" ;;
            0) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Main execution
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Select option (0-11): " choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/wordpress/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
            2) execute_script "$SCRIPT_DIR/backup_restore/backup_restore_menu.sh" "Backup/Restore Menu" ;;
            3) mysql_management_menu ;;
            4) execute_script "$SCRIPT_DIR/mysql/check_remote_access.sh" "Check MySQL Remote Access" ;;
            5) php_management_menu ;;
            6) execute_script "$SCRIPT_DIR/troubleshooting/troubleshooting_menu.sh" "Troubleshooting Tools" ;;
            7) execute_script "$SCRIPT_DIR/rclone/rclone_menu.sh" "Rclone Management" ;;
            8) execute_script "$SCRIPT_DIR/redis/configure.sh" "Redis Configuration" ;;
            9) system_management_menu ;;
            10) website_management_menu ;;
            11) apache_management_menu ;;
            0) 
                echo -e "${GREEN}Thank you for using WordPress Master!${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-11.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"