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

# Main execution
main() {
    check_root
    echo "Install phpMyAdmin"
    echo "=================="
    install_phpmyadmin
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"