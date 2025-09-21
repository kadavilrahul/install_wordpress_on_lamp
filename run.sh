#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source WSL functions
source "$SCRIPT_DIR/wsl/wsl_functions.sh"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Environment initialization
initialize_environment() {
    # Check for command line mode override
    local args=("$@")
    local i=0
    while [ $i -lt ${#args[@]} ]; do
        if [[ "${args[i]}" == "--mode" && $((i+1)) < ${#args[@]} ]]; then
            set_environment_mode "${args[i+1]}"
            # Remove both --mode and its value from args
            unset args[i] args[i+1]
            args=("${args[@]}")  # Re-index array
            break
        fi
        ((i++))
    done
    
    # Default to auto-detection if not set
    if [[ -z "$ENVIRONMENT_MODE" ]]; then
        set_environment_mode "auto"
    fi
    
    # Return remaining arguments
    echo "${args[@]}"
}

# Function to check service status
check_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}● Running${NC}"
    else
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo -e "${YELLOW}● Stopped${NC}"
        else
            echo -e "${RED}● Not Installed${NC}"
        fi
    fi
}

# Function to get service version
get_service_version() {
    local service="$1"
    case $service in
        "apache2")
            apache2 -v 2>/dev/null | head -1 | cut -d' ' -f3 | cut -d'/' -f2 || echo "N/A"
            ;;
        "mysql"|"mariadb")
            mysql --version 2>/dev/null | awk '{print $5}' | sed 's/,$//' || echo "N/A"
            ;;
        "php")
            php -v 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A"
            ;;
        "postgresql")
            sudo -u postgres psql --version 2>/dev/null | awk '{print $3}' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Comprehensive system status display
show_system_status() {
    clear
    echo -e "${CYAN}============================= System Status Overview ============================${NC}"
    
    # Core Services Status - One line
    echo -e "${YELLOW}Services:${NC} Apache2 $(check_service_status apache2) | MySQL $(check_service_status mysql) | PHP ${GREEN}●${NC} v$(get_service_version php) | PostgreSQL $(check_service_status postgresql) | Redis $(check_service_status redis-server)"
    
    # System Resources - One line
    local total_mem=$(free -h | awk '/^Mem:/{print $2}')
    local used_mem=$(free -h | awk '/^Mem:/{print $3}')
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local primary_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    echo -e "${YELLOW}System:${NC} Memory: $used_mem/$total_mem | Disk: $disk_usage used | IP: ${primary_ip:-N/A}"
    
    # Rclone status
    local rclone_status="Not installed"
    if command -v rclone >/dev/null 2>&1; then
        local rclone_version=$(rclone version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//')
        local rclone_remotes=$(rclone listremotes 2>/dev/null | wc -l)
        local remote_text="remote"
        [ "$rclone_remotes" -ne 1 ] && remote_text="remotes"
        rclone_status="v${rclone_version} (${rclone_remotes} ${remote_text})"
    fi
    echo -e "${YELLOW}Rclone:${NC} ${rclone_status}"
    
    # Database counts - One line (without requiring authentication)
    local mysql_status="Not running"
    local pg_status="Not running"
    local pg_db_names=""
    
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        # Just show MySQL is running, don't try to count databases which requires auth
        mysql_status="Running"
    fi
    
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        # PostgreSQL usually allows local sudo access without password
        local pg_db_count=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');" 2>/dev/null | tr -d ' ')
        if [ -n "$pg_db_count" ] && [ "$pg_db_count" -gt 0 ]; then
            pg_db_names=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');" 2>/dev/null | grep -v '^$' | sed 's/^[[:space:]]*//' | paste -sd ', ')
            pg_status="${pg_db_count} databases${pg_db_names:+ (}${pg_db_names}${pg_db_names:+)}"
        else
            pg_status="Running"
        fi
    fi
    
    echo -e "${YELLOW}Databases:${NC} MySQL: ${mysql_status} | PostgreSQL: ${pg_status}"
    
    # WordPress Websites
    echo -e "${YELLOW}WordPress Websites:${NC}"
    local site_count=0
    local wp_sites=()
    local site_statuses=()
    local site_types=()
    
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                local domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                
                # Check if it's a WordPress site
                if [ -f "$dir/wp-config.php" ]; then
                    wp_sites+=("$domain")
                    site_count=$((site_count + 1))
                    
                    # Check if site is accessible
                    if [ -f "/etc/apache2/sites-enabled/${domain}.conf" ] || [ -f "/etc/apache2/sites-enabled/${domain}-le-ssl.conf" ]; then
                        site_statuses+=("Active")
                    else
                        site_statuses+=("Disabled")
                    fi
                    
                    # Check database type
                    local db_type="MySQL"
                    if [ -f "$dir/generator/config.json" ] || [ -f "$dir/config.json" ]; then
                        local config_file=""
                        [ -f "$dir/generator/config.json" ] && config_file="$dir/generator/config.json"
                        [ -f "$dir/config.json" ] && config_file="$dir/config.json"
                        
                        if [ -n "$config_file" ]; then
                            local pg_port=$(jq -r '.port // ""' "$config_file" 2>/dev/null)
                            [[ "$pg_port" == "5432" ]] && db_type="PostgreSQL"
                        fi
                    fi
                    site_types+=("$db_type")
                else
                    # Check for subdirectory WordPress installations
                    for subdir in "$dir"*/; do
                        if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                            local subdir_name=$(basename "$subdir")
                            wp_sites+=("$domain/$subdir_name")
                            site_count=$((site_count + 1))
                            
                            if [ -f "/etc/apache2/sites-enabled/${domain}.conf" ] || [ -f "/etc/apache2/sites-enabled/${domain}-le-ssl.conf" ]; then
                                site_statuses+=("Active")
                            else
                                site_statuses+=("Disabled")
                            fi
                            site_types+=("MySQL")
                        fi
                    done
                fi
            fi
        done
    fi
    
    if [ $site_count -eq 0 ]; then
        echo -e "  No WordPress sites found"
    else
        for i in "${!wp_sites[@]}"; do
            local status_color="${GREEN}"
            [ "${site_statuses[i]}" = "Disabled" ] && status_color="${YELLOW}"
            echo -e "  $((i+1)). ${BLUE}${wp_sites[i]}${NC} - ${status_color}${site_statuses[i]}${NC} (${site_types[i]})"
        done
    fi
    
    # SSL Certificates
    echo -e "${YELLOW}SSL Certificates:${NC}"
    if command -v certbot >/dev/null 2>&1; then
        local cert_info=$(certbot certificates 2>/dev/null | grep -E "Certificate Name:|Expiry Date:")
        if [ -n "$cert_info" ]; then
            while IFS= read -r line; do
                if [[ "$line" == *"Certificate Name:"* ]]; then
                    local cert_name=$(echo "$line" | cut -d':' -f2 | xargs)
                    echo -n "  $cert_name"
                elif [[ "$line" == *"Expiry Date:"* ]]; then
                    local expiry=$(echo "$line" | cut -d':' -f2- | xargs | cut -d' ' -f1-3)
                    local days_left=$(echo "$line" | grep -oP '\d+(?= days\))')
                    [ -z "$days_left" ] && days_left="EXPIRED"
                    echo " - Expires: $expiry (${days_left} days)"
                fi
            done <<< "$cert_info"
        else
            echo -e "  No certificates found"
        fi
    else
        echo -e "  Certbot not installed"
    fi
    
    # PHP Extensions - Compact display
    echo -e "${YELLOW}PHP Extensions:${NC}"
    local php_modules=("mysqli" "curl" "gd" "mbstring" "xml" "zip" "imagick" "redis" "opcache" "pgsql")
    local installed_modules=""
    local missing_modules=""
    
    for module in "${php_modules[@]}"; do
        local is_installed=false
        case "$module" in
            "opcache")
                # OpCache shows as "Zend OPcache" in php -m
                php -m 2>/dev/null | grep -q "Zend OPcache" && is_installed=true
                ;;
            *)
                php -m 2>/dev/null | grep -q "^$module$" && is_installed=true
                ;;
        esac
        
        if [ "$is_installed" = true ]; then
            installed_modules="${installed_modules:+$installed_modules, }$module"
        else
            missing_modules="${missing_modules:+$missing_modules, }$module"
        fi
    done
    
    [ -n "$installed_modules" ] && echo -e "  ${GREEN}Installed:${NC} $installed_modules"
    [ -n "$missing_modules" ] && echo -e "  ${RED}Missing:${NC} $missing_modules"
    
    # System Updates - One line
    local last_update=$(stat -c %y /var/lib/apt/periodic/update-success-stamp 2>/dev/null | cut -d' ' -f1)
    local updates_available=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
    [ -z "$updates_available" ] && updates_available=0
    
    echo -e "${YELLOW}Updates:${NC} Last check: ${last_update:-Unknown} | Status: $([ "$updates_available" -gt 0 ] && echo -e "${YELLOW}$updates_available packages available${NC}" || echo -e "${GREEN}Up to date${NC}")"
    echo -e "${CYAN}=================================================================================${NC}"
}

# Execute folder run.sh script
execute_folder_script() {
    local folder="$1"
    local folder_name="$2"
    local script_path="$SCRIPT_DIR/$folder/run.sh"
    
    if [ ! -f "$script_path" ]; then
        error "Folder script not found: $script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    info "Launching $folder_name management..."
    
    # Execute the folder's run.sh
    bash "$script_path"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "$folder_name completed"
    else
        warn "$folder_name exited with code $exit_code"
    fi
    
    read -p "Press Enter to continue..."
    return $exit_code
}

# Execute script with error handling (for backward compatibility)
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

# Main menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    if is_wsl_mode; then
        echo "                 WordPress WSL Installation Tool"
        echo "            Comprehensive LAMP Stack for WSL Environment"
    else
        echo "                    WordPress Master Installation Tool"
        echo "                   Comprehensive LAMP Stack Management"
    fi
    echo "============================================================================="
    echo -e "${NC}"
    
    # Show environment status
    show_environment_status
    
    # Quick status line
    local apache_status=$(systemctl is-active apache2 2>/dev/null || echo "inactive")
    local mysql_status=$(systemctl is-active mysql 2>/dev/null || systemctl is-active mariadb 2>/dev/null || echo "inactive")
    local pg_status=$(systemctl is-active postgresql 2>/dev/null || echo "inactive")
    
    echo -e "${CYAN}Services: Apache:${NC}$([ "$apache_status" = "active" ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}") ${CYAN}MySQL:${NC}$([ "$mysql_status" = "active" ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}") ${CYAN}PostgreSQL:${NC}$([ "$pg_status" = "active" ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")"
    echo
}

# Category-based main menu
show_menu() {
    # Show system status by default
    show_system_status
    
    echo ""
    if is_wsl_mode; then
        echo -e "${CYAN}==================== WordPress WSL LAMP Stack Management =====================${NC}"
    else
        echo -e "${CYAN}==================== WordPress LAMP Stack Management System =====================${NC}"
    fi
    echo "1. WordPress Management         - Installation and maintenance tools"
    echo "2. New Website Setup            - Install blank website with Apache + SSL"
    echo "3. Backup & Restore             - Backup and restore operations"
    echo "4. MySQL Database               - Database administration and configuration"
    echo "5. PHP Configuration            - PHP settings and information"
    echo "6. System Management            - System utilities and monitoring"
    echo "7. Rclone (Cloud Storage)       - Cloud backup and storage management"
    echo "8. Redis Cache                  - Caching configuration"
    echo "9. Troubleshooting              - Diagnostic and repair tools"
    if is_wsl_mode; then
        echo "10. WSL Hosts File Helper       - Generate Windows hosts file entries"
    fi
    echo ""
    echo "0. Exit"
    echo -e "${CYAN}=================================================================================${NC}"
}

# Classic detailed menu (for backward compatibility)
show_classic_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                    WordPress LAMP Stack - Classic Menu"
    echo -e "=============================================================================${NC}"
    echo "1. Install LAMP Stack + WordPress   ./main.sh lamp"
    echo "2. Backup WordPress Sites           ./main.sh backup"
    echo "3. Restore WordPress Sites          ./main.sh restore"
    echo "4. Transfer Backups to Cloud        ./main.sh transfer"
    echo "5. Configure MySQL Remote Access    ./main.sh mysql"
    echo "6. Check MySQL Remote Access        ./main.sh checkdb"
    echo "7. Show MySQL Databases             ./main.sh showdb"
    echo "8. List MySQL Users                 ./main.sh users"
    echo "9. Get Database Size                ./main.sh dbsize"
    echo "10. Install phpMyAdmin              ./main.sh phpmyadmin"
    echo "11. Enable MySQL Log Purging        ./main.sh purge"
    echo "12. Adjust PHP Settings             ./main.sh php"
    echo "13. View PHP Information            ./main.sh phpinfo"
    echo "14. System Status Check             ./main.sh status"
    echo "15. Disk Space Monitor              ./main.sh disk"
    echo "16. Toggle Root SSH Access          ./main.sh ssh"
    echo "17. Install System Utilities        ./main.sh utils        # Install htop, curl, wget, unzip, git, nano, vim"
    echo "18. Install Rclone Package          ./main.sh rclone"
    echo "19. Configure Rclone Remote         ./main.sh config"
    echo "20. Show Rclone Remotes             ./main.sh remotes"
    echo "21. Check Rclone Status             ./main.sh rclonestatus"
    echo "22. Manage Cloud Remote             ./main.sh manage"
    echo "23. Setup Backup Automation         ./main.sh cron"
    echo "24. Uninstall Rclone                ./main.sh uninstall"
    echo "25. Configure Redis Cache           ./main.sh redis"
    echo "26. Install Apache + SSL Only       ./main.sh ssl"
    echo "27. Fix Apache Configurations       ./main.sh fixapache"
    echo "28. Remove Websites & Databases     ./main.sh remove"
    echo "29. Remove Orphaned Databases       ./main.sh cleanup"
    echo "30. Troubleshooting Tools           ./main.sh troubleshoot"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Handle backward compatibility CLI arguments
handle_legacy_cli() {
    local command="$1"
    
    case $command in
        # WordPress operations
        "lamp") execute_script "$SCRIPT_DIR/wordpress/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
        "remove") execute_script "$SCRIPT_DIR/wordpress/remove_websites_databases.sh" "Remove Websites & Databases" ;;
        "cleanup") execute_script "$SCRIPT_DIR/wordpress/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
        
        # Backup/Restore operations
        "backup") execute_script "$SCRIPT_DIR/backup_restore/backup_wordpress.sh" "WordPress Backup" ;;
        "restore") execute_script "$SCRIPT_DIR/backup_restore/restore_wordpress.sh" "WordPress Restore" ;;
        "transfer") execute_script "$SCRIPT_DIR/backup_restore/transfer_backups.sh" "Transfer Backups to Cloud" ;;
        
        # MySQL operations
        "mysql") execute_script "$SCRIPT_DIR/mysql/remote_access.sh" "MySQL Remote Access Configuration" ;;
        "checkdb") execute_script "$SCRIPT_DIR/mysql/check_remote_access.sh" "Check MySQL Remote Access" ;;
        "showdb") execute_script "$SCRIPT_DIR/mysql/show_databases.sh" "Show MySQL Databases" ;;
        "users") execute_script "$SCRIPT_DIR/mysql/list_users.sh" "List MySQL Users" ;;
        "dbsize") execute_script "$SCRIPT_DIR/mysql/get_database_size.sh" "Get Database Size" ;;
        "phpmyadmin") execute_script "$SCRIPT_DIR/mysql/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
        "purge") execute_script "$SCRIPT_DIR/mysql/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;
        
        # PHP operations
        "php") execute_script "$SCRIPT_DIR/php/adjust_settings.sh" "Adjust PHP Settings" ;;
        "phpinfo") execute_script "$SCRIPT_DIR/php/view_info.sh" "View PHP Information" ;;
        
        # System operations
        "status") 
            show_system_status
            read -p "Press Enter to continue..."
            ;;
        "disk") execute_script "$SCRIPT_DIR/system/disk_space_monitor.sh" "Disk Space Monitor" ;;
        "ssh") execute_script "$SCRIPT_DIR/system/toggle_root_ssh.sh" "Toggle Root SSH" ;;
        "utils") execute_script "$SCRIPT_DIR/system/install_utilities.sh" "Install System Utilities" ;;
        
        # Rclone operations
        "rclone") execute_script "$SCRIPT_DIR/rclone/install_package.sh" "Install Rclone Package" ;;
        "config") execute_script "$SCRIPT_DIR/rclone/manage_remote.sh" "Configure Rclone Remote" ;;
        "remotes") execute_script "$SCRIPT_DIR/rclone/show_remotes.sh" "Show Rclone Remotes" ;;
        "rclonestatus") execute_script "$SCRIPT_DIR/rclone/show_status.sh" "Check Rclone Status" ;;
        "manage") execute_script "$SCRIPT_DIR/rclone/manage_remote.sh" "Manage Cloud Remote" ;;
        "cron") execute_script "$SCRIPT_DIR/rclone/setup_backup_cron.sh" "Setup Backup Automation" ;;
        "uninstall") execute_script "$SCRIPT_DIR/rclone/uninstall_package.sh" "Uninstall Rclone" ;;
        
        # Redis operations
        "redis") execute_script "$SCRIPT_DIR/redis/configure.sh" "Configure Redis Cache" ;;
        
        # Apache operations
        "ssl") execute_script "$SCRIPT_DIR/apache/install_ssl_only.sh" "Install Apache + SSL Only" ;;
        "fixapache") execute_script "$SCRIPT_DIR/apache/fix_configs.sh" "Fix Apache Configurations" ;;
        
        # Troubleshooting
        "troubleshoot") execute_script "$SCRIPT_DIR/troubleshooting/troubleshooting_menu.sh" "Troubleshooting Tools" ;;
        
        # WSL-specific
        "hosts") 
            if is_wsl_mode; then
                execute_script "$SCRIPT_DIR/wsl/wsl_hosts_helper.sh" "WSL Hosts File Helper"
            else
                error "WSL Hosts Helper is only available in WSL mode. Use --mode wsl to force WSL mode."
            fi
            ;;
        
        *) return 1 ;;
    esac
    
    return 0
}

# Handle new category-based CLI arguments
handle_cli_command() {
    local category="$1"
    local command="$2"
    
    # First check for legacy commands (backward compatibility)
    if handle_legacy_cli "$category"; then
        return 0
    fi
    
    # Handle new category-based commands
    case $category in
        "wordpress")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/wordpress/run.sh" "$command"
            else
                execute_folder_script "wordpress" "WordPress Management"
            fi
            ;;
        "backup"|"backup-restore")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/backup_restore/run.sh" "$command"
            else
                execute_folder_script "backup_restore" "Backup & Restore"
            fi
            ;;
        "mysql"|"database")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/mysql/run.sh" "$command"
            else
                execute_folder_script "mysql" "MySQL Database"
            fi
            ;;
        "php")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/php/run.sh" "$command"
            else
                execute_folder_script "php" "PHP Configuration"
            fi
            ;;
        "apache"|"web"|"website")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/apache/run.sh" "$command"
            else
                execute_folder_script "apache" "New Website Setup"
            fi
            ;;
        "system")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/system/run.sh" "$command"
            else
                execute_folder_script "system" "System Management"
            fi
            ;;
        "rclone"|"cloud")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/rclone/run.sh" "$command"
            else
                execute_folder_script "rclone" "Cloud Storage"
            fi
            ;;
        "redis"|"cache")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/redis/run.sh" "$command"
            else
                execute_folder_script "redis" "Redis Cache"
            fi
            ;;
        "troubleshooting"|"trouble")
            if [ -n "$command" ]; then
                bash "$SCRIPT_DIR/troubleshooting/run.sh" "$command"
            else
                execute_folder_script "troubleshooting" "Troubleshooting"
            fi
            ;;
        "wsl"|"hosts")
            if is_wsl_mode; then
                if [ -n "$command" ]; then
                    bash "$SCRIPT_DIR/wsl/wsl_hosts_helper.sh" "$command"
                else
                    execute_script "$SCRIPT_DIR/wsl/wsl_hosts_helper.sh" "WSL Hosts File Helper"
                fi
            else
                error "WSL commands are only available in WSL mode. Use --mode wsl to force WSL mode."
            fi
            ;;
        *)
            echo -e "${RED}Invalid command: $category${NC}"
            echo -e "${YELLOW}Usage:${NC}"
            echo "  $0 [--mode server|wsl|auto]  - Interactive menu with environment mode"
            echo "  $0 <legacy-command>          - Legacy commands (lamp, backup, etc.)"
            echo "  $0 <category>                - Category menu (wordpress, mysql, etc.)"
            echo "  $0 <category> <command>      - Direct command execution"
            echo ""
            echo -e "${CYAN}Categories:${NC}"
            echo "  wordpress, backup, mysql, php, apache, system, rclone, redis, troubleshooting"
            if is_wsl_mode; then
                echo "  wsl, hosts (WSL mode only)"
            fi
            echo ""
            echo -e "${CYAN}Environment Modes:${NC}"
            echo "  --mode auto    - Auto-detect environment (default)"
            echo "  --mode server  - Force Linux server mode"
            echo "  --mode wsl     - Force WSL development mode"
            echo ""
            echo -e "${CYAN}Legacy commands still supported for backward compatibility${NC}"
            exit 1
            ;;
    esac
}

# Classic menu handler
handle_classic_menu() {
    while true; do
        show_classic_menu
        echo -n "Enter option (0-30): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/wordpress/install_lamp_stack.sh" "LAMP Stack + WordPress Installation" ;;
            2) execute_script "$SCRIPT_DIR/backup_restore/backup_wordpress.sh" "WordPress Backup" ;;
            3) execute_script "$SCRIPT_DIR/backup_restore/restore_wordpress.sh" "WordPress Restore" ;;
            4) execute_script "$SCRIPT_DIR/backup_restore/transfer_backups.sh" "Transfer Backups to Cloud" ;;
            5) execute_script "$SCRIPT_DIR/mysql/remote_access.sh" "MySQL Remote Access Configuration" ;;
            6) execute_script "$SCRIPT_DIR/mysql/check_remote_access.sh" "Check MySQL Remote Access" ;;
            7) execute_script "$SCRIPT_DIR/mysql/show_databases.sh" "Show MySQL Databases" ;;
            8) execute_script "$SCRIPT_DIR/mysql/list_users.sh" "List MySQL Users" ;;
            9) execute_script "$SCRIPT_DIR/mysql/get_database_size.sh" "Get Database Size" ;;
            10) execute_script "$SCRIPT_DIR/mysql/install_phpmyadmin.sh" "Install phpMyAdmin" ;;
            11) execute_script "$SCRIPT_DIR/mysql/enable_auto_log_purging.sh" "Enable MySQL Log Purging" ;;
            12) execute_script "$SCRIPT_DIR/php/adjust_settings.sh" "Adjust PHP Settings" ;;
            13) execute_script "$SCRIPT_DIR/php/view_info.sh" "View PHP Information" ;;
            14) execute_script "$SCRIPT_DIR/system/status_check.sh" "System Status Check" ;;
            15) execute_script "$SCRIPT_DIR/system/disk_space_monitor.sh" "Disk Space Monitor" ;;
            16) execute_script "$SCRIPT_DIR/system/toggle_root_ssh.sh" "Toggle Root SSH" ;;
            17) execute_script "$SCRIPT_DIR/system/install_utilities.sh" "Install System Utilities" ;;
            18) execute_script "$SCRIPT_DIR/rclone/install_package.sh" "Install Rclone Package" ;;
            19) execute_script "$SCRIPT_DIR/rclone/manage_remote.sh" "Configure Rclone Remote" ;;
            20) execute_script "$SCRIPT_DIR/rclone/show_remotes.sh" "Show Rclone Remotes" ;;
            21) execute_script "$SCRIPT_DIR/rclone/show_status.sh" "Check Rclone Status" ;;
            22) execute_script "$SCRIPT_DIR/rclone/manage_remote.sh" "Manage Cloud Remote" ;;
            23) execute_script "$SCRIPT_DIR/rclone/setup_backup_cron.sh" "Setup Backup Automation" ;;
            24) execute_script "$SCRIPT_DIR/rclone/uninstall_package.sh" "Uninstall Rclone" ;;
            25) execute_script "$SCRIPT_DIR/redis/configure.sh" "Configure Redis Cache" ;;
            26) execute_script "$SCRIPT_DIR/apache/install_ssl_only.sh" "Install Apache + SSL Only" ;;
            27) execute_script "$SCRIPT_DIR/apache/fix_configs.sh" "Fix Apache Configurations" ;;
            28) execute_script "$SCRIPT_DIR/wordpress/remove_websites_databases.sh" "Remove Websites & Databases" ;;
            29) execute_script "$SCRIPT_DIR/wordpress/remove_orphaned_databases.sh" "Remove Orphaned Databases" ;;
            30) execute_script "$SCRIPT_DIR/troubleshooting/troubleshooting_menu.sh" "Troubleshooting Tools" ;;
            0) return ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-30.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main execution
main() {
    check_root
    
    # Initialize environment and process arguments
    local remaining_args=($(initialize_environment "$@"))
    
    if [ ${#remaining_args[@]} -gt 0 ]; then
        handle_cli_command "${remaining_args[@]}"
        exit $?
    fi
    
    while true; do
        show_menu
        if is_wsl_mode; then
            echo -n "Enter option (0-10): "
        else
            echo -n "Enter option (0-9): "
        fi
        read choice
        
        case $choice in
            1) execute_folder_script "wordpress" "WordPress Management" ;;
            2) execute_folder_script "apache" "New Website Setup" ;;
            3) execute_folder_script "backup_restore" "Backup & Restore" ;;
            4) execute_folder_script "mysql" "MySQL Database" ;;
            5) execute_folder_script "php" "PHP Configuration" ;;
            6) execute_folder_script "system" "System Management" ;;
            7) execute_folder_script "rclone" "Cloud Storage" ;;
            8) execute_folder_script "redis" "Redis Cache" ;;
            9) execute_folder_script "troubleshooting" "Troubleshooting" ;;
            10) 
                if is_wsl_mode; then
                    execute_script "$SCRIPT_DIR/wsl/wsl_hosts_helper.sh" "WSL Hosts File Helper"
                else
                    echo -e "${RED}WSL Hosts Helper is only available in WSL mode.${NC}"
                    sleep 1
                fi
                ;;
            0) 
                echo -e "${GREEN}Thank you for using WordPress Master!${NC}"
                exit 0 
                ;;
            *) 
                if is_wsl_mode; then
                    echo -e "${RED}Invalid option. Please select 0-10.${NC}"
                else
                    echo -e "${RED}Invalid option. Please select 0-9.${NC}"
                fi
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"