#!/bin/bash

# Colors and globals
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
DB_NAME="your_db"
DB_USER="your_user"
DB_PASS="your_password"
BACKUP_RETENTION_DAYS=30

# SSH Configuration
SSH_TIMEOUT=30
SSH_CONNECT_TIMEOUT=10

# Utility functions
log() { echo "[$1] $2"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# Function to log messages with timestamp
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ${1}"
    echo "${message}"
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${message}" >> "${LOG_FILE}"
    fi
}

# Function to handle errors
error_exit() {
    log_message "ERROR: ${1}"
    exit 1
}

# PostgreSQL restore function
restore_postgresql() {
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="/var/log/postgres_restore_${TIMESTAMP}.log"
    
    log_message "Starting PostgreSQL restoration process"
    
    # List available dump files
    echo "Available PostgreSQL dump files:"
    echo "--------------------------------"
    
    readarray -t dump_files < <(find "${BACKUP_DIR}" -maxdepth 1 -name "*.dump" -type f | sort)
    
    if [ ${#dump_files[@]} -eq 0 ]; then
        error_exit "No PostgreSQL dump files found"
    fi
    
    for i in "${!dump_files[@]}"; do
        filename=$(basename "${dump_files[$i]}")
        echo "[$((i+1))] ${filename}"
    done
    
    echo
    read -p "Enter the number of the dump file to restore: " dump_number
    
    if ! [[ "$dump_number" =~ ^[0-9]+$ ]] || \
       [ "$dump_number" -lt 1 ] || \
       [ "$dump_number" -gt ${#dump_files[@]} ]; then
        error_exit "Invalid dump number selected"
    fi
    
    selected_dump="${dump_files[$((dump_number-1))]}"
    log_message "Selected dump: $(basename "${selected_dump}")"
    
    # Update system packages
    log_message "Updating system packages..."
    sudo apt update -y
    
    # Install PostgreSQL (if not installed)
    log_message "Installing PostgreSQL..."
    sudo apt install -y postgresql postgresql-contrib
    
    # Start and enable PostgreSQL service
    log_message "Starting PostgreSQL service..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Setup database and user
    log_message "Setting up database and user..."
    sudo -u postgres psql <<EOF
-- Drop database if it exists
DROP DATABASE IF EXISTS $DB_NAME;

-- Drop user if it exists and recreate
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    # Restore the dump file
    log_message "Restoring the database from dump..."
    sudo -u postgres pg_restore --clean --if-exists -d $DB_NAME "$selected_dump" || error_exit "Database restoration failed"
    
    # Verify database and table existence
    log_message "Verifying database..."
    sudo -u postgres psql -d $DB_NAME -c "\dt"
    
    success "PostgreSQL restoration completed successfully!"
}

# Execute the restore function
restore_postgresql