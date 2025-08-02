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

# Main execution
main() {
    check_root
    echo "Get Database Size"
    echo "================="
    get_database_size
    read -p "Press Enter to continue..."
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"