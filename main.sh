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
    echo "                    WordPress LAMP Stack Management System"
    echo -e "=============================================================================${NC}"
    echo "1. Install LAMP Stack + WordPress   ./main.sh lamp         # Complete LAMP installation with WordPress setup"
    echo "2. Backup WordPress Sites           ./main.sh backup       # Create backups of WordPress sites and databases"
    echo "3. Restore WordPress Sites          ./main.sh restore      # Restore WordPress sites from backups"
    echo "4. Transfer Backups to Cloud        ./main.sh transfer     # Upload backups to cloud storage with rclone"
    echo "5. Configure MySQL Remote Access    ./main.sh mysql        # Set up MySQL for remote connections"
    echo "6. Check MySQL Remote Access        ./main.sh checkdb      # Verify MySQL remote accessibility status"
    echo "7. Cloud Storage (Rclone)           ./main.sh cloud        # Complete cloud storage management suite"
    echo "8. Show MySQL Databases             ./main.sh showdb       # Display all databases in MySQL server"
    echo "9. List MySQL Users                 ./main.sh users        # Show all MySQL user accounts and permissions"
    echo "10. Get Database Size               ./main.sh dbsize       # Check storage usage of databases"
    echo "11. Install phpMyAdmin              ./main.sh phpmyadmin   # Set up web-based MySQL administration"
    echo "12. Enable MySQL Log Purging        ./main.sh purge        # Configure automatic binary log cleanup"
    echo "13. Adjust PHP Settings             ./main.sh php          # Optimize PHP configuration for web apps"
    echo "14. View PHP Information            ./main.sh phpinfo      # Display PHP version and configuration"
    echo "15. System Status Check             ./main.sh status       # View system resources and service status"
    echo "16. Disk Space Monitor              ./main.sh disk         # Monitor storage usage and cleanup"
    echo "17. Toggle Root SSH Access          ./main.sh ssh          # Enable or disable SSH root login"
    echo "18. Install System Utilities        ./main.sh utils        # Install common system tools"
    echo "19. Configure Redis Cache           ./main.sh redis        # Set up Redis caching for performance"
    echo "20. Install Apache + SSL Only       ./main.sh ssl          # Set up web server with SSL certificates"
    echo "21. Fix Apache Configurations       ./main.sh fixapache    # Repair broken Apache virtual host configs"
    echo "22. Remove Websites & Databases     ./main.sh remove       # Clean removal of websites and data"
    echo "23. Remove Orphaned Databases       ./main.sh cleanup      # Clean up databases without websites"
    echo "24. Troubleshooting Tools           ./main.sh troubleshoot # Diagnose and fix common issues"
    echo "0. Exit"
    echo -e "${CYAN}=============================================================================${NC}"
}

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

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "lamp") execute_script "$SCRIPT_DIR/wordpress/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
        "backup") execute_script "$SCRIPT_DIR/backup_restore/backup_wordpress.sh" "WordPress Backup" ;;
        "restore") execute_script "$SCRIPT_DIR/backup_restore/restore_wordpress.sh" "WordPress Restore" ;;
        "transfer") execute_script "$SCRIPT_DIR/backup_restore/transfer_backups.sh" "Transfer Backups to Cloud" ;;
        "mysql") execute_script "$SCRIPT_DIR/mysql/remote_access.sh" "MySQL Remote Access Configuration" ;;
        "checkdb") execute_script "$SCRIPT_DIR/mysql/check_remote_access.sh" "Check MySQL Remote Access" ;;
        "cloud") execute_script "$SCRIPT_DIR/rclone/run.sh" "Cloud Storage (Rclone)" ;;
        "showdb") execute_script "$SCRIPT_DIR/mysql/show_databases.sh" "Show MySQL Databases" ;;
        "users") execute_script "$SCRIPT_DIR/mysql/list_users.sh" "List MySQL Users" ;;
        "dbsize") execute_script "$SCRIPT_DIR/mysql/get_database_size.sh" "Get Database Size" ;;
        "phpmyadmin") execute_script "$SCRIPT_DIR/mysql/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
        "purge") execute_script "$SCRIPT_DIR/mysql/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;
        "php") execute_script "$SCRIPT_DIR/php/adjust_settings.sh" "Adjust PHP Settings" ;;
        "phpinfo") execute_script "$SCRIPT_DIR/php/view_info.sh" "View PHP Information" ;;
        "status") execute_script "$SCRIPT_DIR/system/status_check.sh" "System Status Check" ;;
        "disk") execute_script "$SCRIPT_DIR/system/disk_space_monitor.sh" "Disk Space Monitor" ;;
        "ssh") execute_script "$SCRIPT_DIR/system/toggle_root_ssh.sh" "Toggle Root SSH" ;;
        "utils") execute_script "$SCRIPT_DIR/system/install_utilities.sh" "Install System Utilities" ;;
        "redis") execute_script "$SCRIPT_DIR/redis/configure.sh" "Configure Redis Cache" ;;
        "ssl") execute_script "$SCRIPT_DIR/apache/install_ssl_only.sh" "Install Apache + SSL Only" ;;
        "fixapache") execute_script "$SCRIPT_DIR/apache/fix_configs.sh" "Fix Apache Configurations" ;;
        "remove") execute_script "$SCRIPT_DIR/wordpress/remove_websites_databases.sh" "Remove Websites & Databases" ;;
        "cleanup") execute_script "$SCRIPT_DIR/wordpress/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
        "troubleshoot") execute_script "$SCRIPT_DIR/troubleshooting/troubleshooting_menu.sh" "Troubleshooting Tools" ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            echo -e "${YELLOW}Usage: $0 <command>${NC}"
            echo -e "${CYAN}Run without arguments to see the interactive menu${NC}"
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
        echo -n "Enter option (0-24): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/wordpress/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
            2) execute_script "$SCRIPT_DIR/backup_restore/backup_wordpress.sh" "WordPress Backup" ;;
            3) execute_script "$SCRIPT_DIR/backup_restore/restore_wordpress.sh" "WordPress Restore" ;;
            4) execute_script "$SCRIPT_DIR/backup_restore/transfer_backups.sh" "Transfer Backups to Cloud" ;;
            5) execute_script "$SCRIPT_DIR/mysql/remote_access.sh" "MySQL Remote Access Configuration" ;;
            6) execute_script "$SCRIPT_DIR/mysql/check_remote_access.sh" "Check MySQL Remote Access" ;;
            7) execute_script "$SCRIPT_DIR/rclone/run.sh" "Cloud Storage (Rclone)" ;;
            8) execute_script "$SCRIPT_DIR/mysql/show_databases.sh" "Show MySQL Databases" ;;
            9) execute_script "$SCRIPT_DIR/mysql/list_users.sh" "List MySQL Users" ;;
            10) execute_script "$SCRIPT_DIR/mysql/get_database_size.sh" "Get Database Size" ;;
            11) execute_script "$SCRIPT_DIR/mysql/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
            12) execute_script "$SCRIPT_DIR/mysql/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;
            13) execute_script "$SCRIPT_DIR/php/adjust_settings.sh" "Adjust PHP Settings" ;;
            14) execute_script "$SCRIPT_DIR/php/view_info.sh" "View PHP Information" ;;
            15) execute_script "$SCRIPT_DIR/system/status_check.sh" "System Status Check" ;;
            16) execute_script "$SCRIPT_DIR/system/disk_space_monitor.sh" "Disk Space Monitor" ;;
            17) execute_script "$SCRIPT_DIR/system/toggle_root_ssh.sh" "Toggle Root SSH" ;;
            18) execute_script "$SCRIPT_DIR/system/install_utilities.sh" "Install System Utilities" ;;
            19) execute_script "$SCRIPT_DIR/redis/configure.sh" "Configure Redis Cache" ;;
            20) execute_script "$SCRIPT_DIR/apache/install_ssl_only.sh" "Install Apache + SSL Only" ;;
            21) execute_script "$SCRIPT_DIR/apache/fix_configs.sh" "Fix Apache Configurations" ;;
            22) execute_script "$SCRIPT_DIR/wordpress/remove_websites_databases.sh" "Remove Websites & Databases" ;;
            23) execute_script "$SCRIPT_DIR/wordpress/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
            24) execute_script "$SCRIPT_DIR/troubleshooting/troubleshooting_menu.sh" "Troubleshooting Tools" ;;
            0) 
                echo -e "${GREEN}Thank you for using WordPress Master!${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-24.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"