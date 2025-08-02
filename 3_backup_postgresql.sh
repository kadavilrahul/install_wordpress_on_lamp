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

# PostgreSQL backup function
backup_postgres() {
    local TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    local LOG_FILE="/var/log/postgres_backup_${TIMESTAMP}.log"
    
    log_message "Starting PostgreSQL backup process"
    
    # Start PostgreSQL if not running
    log_message "Checking PostgreSQL status..."
    systemctl is-active --quiet postgresql || sudo systemctl start postgresql || error_exit "Failed to start PostgreSQL"
    
    # Ensure backup directory exists and set permissions
    log_message "Setting up backup directory..."
    sudo mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    sudo chown postgres:postgres "$BACKUP_DIR"
    sudo chmod 700 "$BACKUP_DIR"
    
    # Create database and user if they don't exist
    log_message "Ensuring database and user exist..."
    sudo -u postgres psql <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
        CREATE DATABASE $DB_NAME;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';
    END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    # Perform backup
    local dump_backup="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"
    log_message "Creating PostgreSQL backup..."
    sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$dump_backup" || error_exit "PostgreSQL backup failed"
    
    # Clean old backups
    log_message "Cleaning old backups..."
    find "$BACKUP_DIR" -type f -name "*.dump" -mtime +"$BACKUP_RETENTION_DAYS" -delete
    
    success "PostgreSQL backup completed successfully!"
    info "Backup location: $dump_backup"
}

# Execute the backup function
backup_postgres