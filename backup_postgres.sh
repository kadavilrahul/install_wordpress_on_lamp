#!/bin/bash

# Configuration
DB_NAME="your_db"
DB_USER="your_user"
DB_PASS="your_password"  # Change this to a secure password
BACKUP_DIR="/website_backups/postgres"
BACKUP_RETENTION_DAYS=30

# Logging functions
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error_exit() { echo -e "[ERROR] $1" >&2; exit 1; }

# Install PostgreSQL if not installed
if ! command -v psql &>/dev/null; then
    log "Installing PostgreSQL..."
    sudo apt update -y && sudo apt install -y postgresql postgresql-contrib || error_exit "Failed to install PostgreSQL"
fi

# Start PostgreSQL if not running
log "Checking PostgreSQL status..."
systemctl is-active --quiet postgresql || sudo systemctl start postgresql || error_exit "Failed to start PostgreSQL"

# Ensure backup directory exists and set permissions
log "Setting up backup directory..."
sudo mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
sudo chown postgres:postgres "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"

# Create database and user if they don't exist
log "Ensuring database and user exist..."
sudo -u postgres psql <<EOF
DO \$\$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
        CREATE DATABASE $DB_NAME OWNER $DB_USER;
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';
    END IF;
END
\$\$;
EOF

# Perform backup
timestamp=$(date '+%Y%m%d_%H%M%S')
dump_backup="${BACKUP_DIR}/${DB_NAME}_${timestamp}.dump"

log "Creating PostgreSQL backup..."
sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$dump_backup" || error_exit "Backup failed"

# Clean old backups
log "Cleaning old backups..."
find "$BACKUP_DIR" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete

# Summary
log "Backup completed successfully!"
ls -lh "$dump_backup"
