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

function list_mysql_users() {
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null; then
        success "Successfully listed MySQL users."
    else
        error "Failed to list MySQL users. Check your password."
    fi
}

# Main execution
main() {
    check_root
    echo "List MySQL Users"
    echo "================"
    list_mysql_users
    read -p "Press Enter to continue..."
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"