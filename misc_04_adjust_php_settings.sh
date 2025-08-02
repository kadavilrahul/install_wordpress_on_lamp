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

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root (use sudo)"
        exit 1
    fi
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

# Main execution
main() {
    check_root
    echo "Adjust PHP Settings"
    echo "=================="
    adjust_php_settings
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"