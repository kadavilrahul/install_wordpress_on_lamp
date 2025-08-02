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

# View PHP Information
function view_php_info() {
    clear
    echo "PHP Information"
    echo "==============="
    echo "  1) Create phpinfo.php and show URL - Generate phpinfo() page accessible via web browser"
    echo "  2) Show PHP version and modules - Display PHP version and installed extensions"
    echo "  0) Back to menu - Return to main miscellaneous menu"
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
        0) 
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

# Main execution
main() {
    check_root
    view_php_info
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"