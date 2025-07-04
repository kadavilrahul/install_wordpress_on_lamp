#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# phpMyAdmin installation
install_phpmyadmin() {
    read -p "Enter web directory (default: /var/www): " WP_DIR
    [[ -z "$WP_DIR" ]] && WP_DIR="/var/www"
    [ ! -d "$WP_DIR" ] && error "Directory $WP_DIR does not exist"
    
    export DEBIAN_FRONTEND=noninteractive
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    
    apt update -y && apt install -y phpmyadmin || error "phpMyAdmin installation failed"
    ln -sf /usr/share/phpmyadmin "$WP_DIR/phpmyadmin"
    a2enconf phpmyadmin && systemctl restart apache2
    
    success "phpMyAdmin installed! Access at: http://your-domain/phpmyadmin"
    read -p "Press Enter to continue..."
}

# System utilities configuration
system_utilities() {
    echo "Configuring system utilities..."
    
    # Update package lists
    apt update -y
    
    # Install common utilities
    apt install -y htop curl wget unzip git nano vim
    
    success "System utilities configuration completed"
    read -p "Press Enter to continue..."
}

# MySQL Utilities
function show_databases() {
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SHOW DATABASES;" 2>/dev/null; then
        success "Successfully showed databases."
    else
        error "Failed to show databases. Check your password."
    fi
}

function list_mysql_users() {
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null; then
        success "Successfully listed MySQL users."
    else
        error "Failed to list MySQL users. Check your password."
    fi
}


function get_database_size() {
    if [ -z "$1" ]; then
        read -p "Enter database name: " DB_NAME
        if [ -z "$DB_NAME" ]; then
            error "Database name is required."
            return 1
        fi
        DATABASE_NAME="$DB_NAME"
    else
        DATABASE_NAME="$1"
    fi
    
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    
    if mysql -u root -p"$MYSQL_PWD" -e "SELECT table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    WHERE table_schema = '$DATABASE_NAME'
    GROUP BY table_schema;" 2>/dev/null; then
        success "Successfully got database size."
    else
        error "Failed to get database size. Check database name and password."
    fi
}

function verify_mysql_root() {
    local MYSQL_PWD="$1"
    if ! mysql -u root -p"$MYSQL_PWD" -e "SELECT 1" 2>/dev/null; then
        error "Invalid MySQL root password"
        return 1
    fi
    return 0
}


# PHP Configuration
function adjust_php_settings() {
    # Function to modify php.ini
    modify_php_ini() {
        local ini_file="$1"
        echo "Modifying PHP INI file: $ini_file"

        if [ -f "$ini_file" ]; then
            # Backup original file
            cp "$ini_file" "${ini_file}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Update settings
            sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$ini_file"
            sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$ini_file"
            sed -i "s/^memory_limit = .*/memory_limit = 512M/" "$ini_file"
            sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$ini_file"
            sed -i "s/^max_input_time = .*/max_input_time = 300/" "$ini_file"
            sed -i "s/^max_input_vars = .*/max_input_vars = 5000/" "$ini_file"
        else
            warning "PHP INI file not found: $ini_file"
        fi
    }

    # Get PHP version
    PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    
    if [ -z "$PHP_VERSION" ]; then
        error "PHP is not installed or not in PATH"
        return 1
    fi
    
    echo "Detected PHP version: ${PHP_VERSION}"

    # Define possible php.ini paths
    CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
    APACHE_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
    FPM_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

    # Modify php.ini files
    modify_php_ini "$CLI_INI"
    modify_php_ini "$APACHE_INI"
    modify_php_ini "$FPM_INI"

    # Restart PHP-FPM if it's running
    if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
        echo "Restarting PHP-FPM..."
        systemctl restart php${PHP_VERSION}-fpm
    fi

    # Restart Apache if it's running
    if systemctl is-active --quiet apache2; then
        echo "Restarting Apache..."
        systemctl restart apache2
    fi

    success "PHP configuration completed!"
    read -p "Press Enter to continue..."
}

# View PHP Information
function view_php_info() {
    clear
    echo "PHP Information"
    echo "==============="
    echo "1) Create phpinfo.php and show URL"
    echo "2) Show PHP version and modules"
    echo "3) Back to menu"
    echo
    read -p "Select option: " choice
    
    case $choice in
        1)
            if [ ! -f "/var/www/html/phpinfo.php" ]; then
                echo "Creating phpinfo.php in /var/www/html..."
                echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
                chown www-data:www-data /var/www/html/phpinfo.php
                chmod 644 /var/www/html/phpinfo.php
            fi
            SERVER_IP=$(hostname -I | awk '{print $1}')
            echo "PHP Info available at: http://${SERVER_IP}/phpinfo.php"
            warning "Remember to delete phpinfo.php after viewing for security!"
            ;;
        2)
            php -v
            echo
            echo "Installed PHP modules:"
            php -m
            ;;
        3) 
            return 
            ;;
        *) 
            echo "Invalid option" 
            sleep 1
            view_php_info
            return
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Disk Space Monitoring and Cleanup
function disk_space_monitor() {
    clear
    echo "Disk Space Monitoring"
    echo "===================="
    echo "1) Show disk usage summary"
    echo "2) Show largest directories"
    echo "3) Show largest files"
    echo "4) Clean system logs"
    echo "5) Clean package cache"
    echo "6) Clean temporary files"
    echo "7) Full system cleanup"
    echo "8) Back to menu"
    echo
    read -p "Select option: " choice
    
    case $choice in
        1) show_disk_usage ;;
        2) show_largest_directories ;;
        3) show_largest_files ;;
        4) clean_system_logs ;;
        5) clean_package_cache ;;
        6) clean_temp_files ;;
        7) full_system_cleanup ;;
        8) return ;;
        *)
            echo "Invalid option"
            sleep 1
            disk_space_monitor
            return
            ;;
    esac
    
    read -p "Press Enter to continue..."
    disk_space_monitor
}

function show_disk_usage() {
    echo "=== Disk Usage Summary ==="
    df -h
    echo
    echo "=== Memory Usage ==="
    free -h
    echo
    echo "=== Inode Usage ==="
    df -i
}

function show_largest_directories() {
    echo "=== Top 10 Largest Directories ==="
    read -p "Enter path to scan (default: /): " scan_path
    scan_path=${scan_path:-/}
    
    if [ ! -d "$scan_path" ]; then
        error "Directory $scan_path does not exist"
        return 1
    fi
    
    echo "Scanning $scan_path (this may take a while)..."
    du -h "$scan_path" 2>/dev/null | sort -hr | head -10
}

function show_largest_files() {
    echo "=== Top 10 Largest Files ==="
    read -p "Enter path to scan (default: /): " scan_path
    scan_path=${scan_path:-/}
    
    if [ ! -d "$scan_path" ]; then
        error "Directory $scan_path does not exist"
        return 1
    fi
    
    echo "Scanning $scan_path (this may take a while)..."
    find "$scan_path" -type f -exec du -h {} + 2>/dev/null | sort -hr | head -10
}

function clean_system_logs() {
    echo "=== Cleaning System Logs ==="
    
    # Show current log sizes
    echo "Current log directory sizes:"
    du -sh /var/log/* 2>/dev/null | sort -hr | head -10
    echo
    
    read -p "Proceed with log cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean journal logs older than 7 days
        journalctl --vacuum-time=7d
        
        # Clean old log files
        find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        
        # Truncate large log files
        for log in /var/log/syslog /var/log/auth.log /var/log/kern.log; do
            if [ -f "$log" ] && [ $(stat -c%s "$log") -gt 104857600 ]; then  # 100MB
                echo "Truncating large log file: $log"
                tail -n 1000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
            fi
        done
        
        success "System logs cleaned"
    else
        echo "Log cleanup cancelled"
    fi
}

function clean_package_cache() {
    echo "=== Cleaning Package Cache ==="
    
    # Show current cache sizes
    echo "Current package cache sizes:"
    if [ -d "/var/cache/apt" ]; then
        du -sh /var/cache/apt 2>/dev/null
    fi
    if [ -d "/var/lib/apt/lists" ]; then
        du -sh /var/lib/apt/lists 2>/dev/null
    fi
    echo
    
    read -p "Proceed with package cache cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean apt cache
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y
        
        success "Package cache cleaned"
    else
        echo "Package cache cleanup cancelled"
    fi
}

function clean_temp_files() {
    echo "=== Cleaning Temporary Files ==="
    
    # Show current temp sizes
    echo "Current temporary directory sizes:"
    du -sh /tmp /var/tmp 2>/dev/null
    echo
    
    read -p "Proceed with temporary files cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean /tmp (files older than 7 days)
        find /tmp -type f -mtime +7 -delete 2>/dev/null
        find /tmp -type d -empty -delete 2>/dev/null
        
        # Clean /var/tmp (files older than 30 days)
        find /var/tmp -type f -mtime +30 -delete 2>/dev/null
        find /var/tmp -type d -empty -delete 2>/dev/null
        
        # Clean user cache directories
        find /home -name ".cache" -type d -exec du -sh {} \; 2>/dev/null | head -5
        
        success "Temporary files cleaned"
    else
        echo "Temporary files cleanup cancelled"
    fi
}

function full_system_cleanup() {
    echo "=== Full System Cleanup ==="
    echo "This will perform all cleanup operations:"
    echo "- Clean system logs"
    echo "- Clean package cache"
    echo "- Clean temporary files"
    echo
    
    read -p "Proceed with full cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "Starting full system cleanup..."
        
        # Show initial disk usage
        echo "=== Initial Disk Usage ==="
        df -h /
        echo
        
        # Perform all cleanup operations
        echo "Cleaning system logs..."
        journalctl --vacuum-time=7d >/dev/null 2>&1
        find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        
        echo "Cleaning package cache..."
        apt-get clean >/dev/null 2>&1
        apt-get autoclean >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        
        echo "Cleaning temporary files..."
        find /tmp -type f -mtime +7 -delete 2>/dev/null
        find /var/tmp -type f -mtime +30 -delete 2>/dev/null
        
        # Show final disk usage
        echo "=== Final Disk Usage ==="
        df -h /
        
        success "Full system cleanup completed"
    else
        echo "Full cleanup cancelled"
    fi
}

# SSH Security Management
function toggle_root_ssh() {
    echo "SSH Root Access Management"
    echo "=========================="
    echo "1) Disable root SSH login"
    echo "2) Enable root SSH login"
    echo "3) Show current status"
    echo "4) Back to menu"
    echo
    read -p "Choose (1-4): " choice
    
    case $choice in
        1)
            # Disable root SSH
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            systemctl restart sshd
            success "Root SSH login disabled"
            ;;
        2)
            # Enable root SSH
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
            systemctl restart sshd
            warning "Root SSH login enabled - this is less secure!"
            ;;
        3)
            # Show current status
            echo "Current SSH configuration:"
            grep -E "^#*PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin not explicitly set (default: prohibit-password)"
            ;;
        4)
            return
            ;;
        *)
            echo "Invalid option"
            sleep 1
            toggle_root_ssh
            return
            ;;
    esac
    read -p "Press Enter to continue..."
}


# Main Menu
function main_menu() {
    while true; do
        clear
        echo "=================================="
        echo "    Server Management Script"
        echo "=================================="
        echo "MySQL Utilities:"
        echo "1) Show MySQL databases"
        echo "2) List MySQL users"
        echo "3) Get database size"
        echo
        echo "PHP Management:"
        echo "4) Adjust PHP settings"
        echo "5) View PHP Info"
        echo
        echo "System Management:"
        echo "6) Disk space monitoring & cleanup"
        echo "7) Toggle root SSH access"
        echo "8) Install phpMyAdmin"
        echo "9) System Utilities"
        echo
        echo "q) Quit"
        echo "=================================="
        read -p "Enter your choice: " choice

        case "$choice" in
            1) show_databases ;;
            2) list_mysql_users ;;
            3) get_database_size ;;
            4) adjust_php_settings ;;
            5) view_php_info ;;
            6) disk_space_monitor ;;
            7) toggle_root_ssh ;;
            8) install_phpmyadmin ;;
            9) system_utilities ;;
            q|Q) 
                echo "Goodbye!"
                exit 0 
                ;;
            *) 
                echo "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    main_menu
fi