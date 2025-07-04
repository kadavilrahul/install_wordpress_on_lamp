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

# Utility functions
log() { echo "[$1] $2"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# Menu system
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                            Backup and Restore Menu"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Main Menu:${NC}"
    echo "  1) Backup WordPress Sites"
    echo "  2) Restore WordPress Sites"
    echo "  3) Backup PostgreSQL"
    echo "  4) Restore PostgreSQL"
    echo "  5) Transfer Backups"
    echo "  6) Exit"
    echo -e "${CYAN}=============================================================================${NC}"
}

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

# Function to check if a directory is a WordPress installation
is_wordpress() {
    if [ -f "${1}/wp-config.php" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check WP-CLI installation
check_wpcli() {
    if ! command -v wp &> /dev/null; then
        log_message "WP-CLI not found. Installing..."
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
        if ! command -v wp &> /dev/null; then
            error_exit "Failed to install WP-CLI"
        fi
    fi
    log_message "WP-CLI is available"
}

# Function to backup WordPress site
backup_wordpress_site() {
    local site_path="${1}"
    local site_name="${2}"
    
    log_message "Starting WordPress backup for: ${site_name}"
    
    # Create database dump
    local db_dump_name="${site_name}_db.sql"
    
    if wp core is-installed --path="${site_path}" --allow-root; then
        log_message "Exporting database for ${site_name}"
        wp db export "${site_path}/${db_dump_name}" --path="${site_path}" --allow-root || \
            error_exit "Database export failed for ${site_name}"
    else
        log_message "Warning: WordPress not properly installed in ${site_name}"
    fi
    
    # Create backup
    local backup_name="${site_name}_backup_${TIMESTAMP}.tar.gz"
    log_message "Creating tar archive for ${site_name}"
    
    pushd "${WWW_PATH}" > /dev/null || error_exit "Cannot change to www directory"
    
    # Exclude cache directories and handle file changes during backup
    tar --warning=no-file-changed -czf "${BACKUP_DIR}/${backup_name}" \
        --exclude="${site_name}/wp-content/cache" \
        --exclude="${site_name}/wp-content/wpo-cache" \
        --exclude="${site_name}/wp-content/uploads/cache" \
        --exclude="${site_name}/wp-content/plugins/*/cache" \
        "${site_name}" || {
        local tar_exit=$?
        if [ $tar_exit -ne 0 ] && [ $tar_exit -ne 1 ]; then
            popd > /dev/null
            error_exit "Tar backup failed for ${site_name}"
        fi
    }
    popd > /dev/null
    
    # Cleanup database dump
    if [ -f "${site_path}/${db_dump_name}" ]; then
        rm -f "${site_path}/${db_dump_name}"
    fi
    
    success "Backup completed for ${site_name}"
}

# Main WordPress backup function
backup_wordpress() {
    local TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    local LOG_FILE="/var/log/website_backup_${TIMESTAMP}.log"
    
    log_message "Starting WordPress backup process"
    log_message "Log file: ${LOG_FILE}"
    
    # Check if WWW_PATH exists
    if [ ! -d "${WWW_PATH}" ]; then
        error_exit "WWW_PATH (${WWW_PATH}) does not exist!"
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}" || error_exit "Failed to create backup directory"
    
    # Check WP-CLI
    check_wpcli
    
    # Iterate through all directories in www path
    for site_dir in "${WWW_PATH}"/*; do
        if [ -d "${site_dir}" ]; then
            site_name=$(basename "${site_dir}")
            
            # Skip the html directory
            if [ "${site_name}" = "html" ]; then
                log_message "Skipping html directory"
                continue
            fi
            
            log_message "Processing site: ${site_name}"
            
            if is_wordpress "${site_dir}"; then
                backup_wordpress_site "${site_dir}" "${site_name}"
            fi
        fi
    done
    
    # Cleanup old backups
    log_message "Cleaning up old backups"
    find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +7 -delete
    find "${BACKUP_DIR}" -type f -name "backup_inventory_*.txt" -mtime +7 -delete
    
    success "WordPress backup process completed"
}

# Function to check if a backup is WordPress
is_wordpress_backup() {
    local backup_file="${1}"
    tar -tzf "${backup_file}" 2>/dev/null | grep -q "wp-config.php"
    return $?
}

# Function to list backups with serial numbers
list_and_store_backups() {
    echo "Available backups:"
    echo "----------------"
    
    readarray -t backup_files < <(find "${BACKUP_DIR}" -maxdepth 1 -name "*.tar.gz" -type f | sort)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo "No backups found"
        return 1
    fi
    
    for i in "${!backup_files[@]}"; do
        filename=$(basename "${backup_files[$i]}")
        echo "[$((i+1))] ${filename}"
    done
    
    return 0
}

# Function to restore WordPress site
restore_wordpress_site() {
    local backup_file="${1}"
    local site_name="${2}"
    local target_dir="${WWW_PATH}/${site_name}"
    
    log_message "Starting WordPress restoration for: ${site_name}"
    
    # Create target directory if it doesn't exist
    mkdir -p "${target_dir}" || error_exit "Failed to create target directory"
    
    # Extract backup
    log_message "Extracting backup archive"
    tar -xzf "${backup_file}" -C "${WWW_PATH}" || error_exit "Failed to extract backup"
    
    # Remove problematic files immediately after extraction
    log_message "Removing problematic files..."
    rm -f "${target_dir}/wp-content/object-cache.php"
    rm -f "${target_dir}/wp-content/advanced-cache.php"
    
    # Find database dump in the extracted files
    local db_dump=""
    for possible_dump in "${target_dir}"/*_db.sql "${target_dir}"/wordpress_db.sql "${target_dir}"/*.sql; do
        if [ -f "${possible_dump}" ]; then
            db_dump="${possible_dump}"
            break
        fi
    done
    
    if [ -n "${db_dump}" ]; then
        log_message "Found database dump: ${db_dump}"
        
        if [ -f "${target_dir}/wp-config.php" ]; then
            # Add direct filesystem access
            log_message "Configuring filesystem access..."
            sed -i "/^require_once/i define('FS_METHOD', 'direct');" "${target_dir}/wp-config.php"
            
            # Enable debug mode
            log_message "Enabling debug mode..."
            sed -i "/'WP_DEBUG'/d" "${target_dir}/wp-config.php"
            sed -i "/^define('FS_METHOD'/a define('WP_DEBUG', true);\ndefine('WP_DEBUG_LOG', true);\ndefine('WP_DEBUG_DISPLAY', false);" "${target_dir}/wp-config.php"
            
            log_message "Importing database..."
            wp db import "${db_dump}" --path="${target_dir}" --allow-root
            if [ $? -eq 0 ]; then
                log_message "Database import successful"
                rm -f "${db_dump}"
                
                # Deactivate problematic plugins
                log_message "Deactivating problematic plugins..."
                wp plugin deactivate redis-cache wp-optimize w3-total-cache wp-super-cache --path="${target_dir}" --allow-root 2>/dev/null || log_message "Note: Some plugins were already inactive"
                
                # Update WordPress core
                log_message "Updating WordPress core..."
                wp core update --path="${target_dir}" --allow-root || log_message "Warning: Core update failed"
                
                # Update only active theme
                log_message "Checking active theme..."
                active_theme=$(wp theme list --status=active --field=name --path="${target_dir}" --allow-root 2>/dev/null)
                if [ -n "${active_theme}" ]; then
                    log_message "Updating active theme: ${active_theme}"
                    wp theme update "${active_theme}" --path="${target_dir}" --allow-root || log_message "Warning: Failed to update theme"
                else
                    log_message "Warning: Could not determine active theme"
                fi
                
                # Clear caches without using plugins
                log_message "Clearing caches..."
                wp rewrite flush --path="${target_dir}" --allow-root || log_message "Warning: Rewrite flush failed"
            else
                log_message "Warning: Database import failed, but continuing with restoration"
            fi
        else
            log_message "Warning: wp-config.php not found, skipping database import"
        fi
    else
        log_message "Warning: No database dump found in backup"
    fi
    
    # Fix permissions
    log_message "Setting correct permissions"
    chown -R www-data:www-data "${target_dir}"
    chmod 755 "${target_dir}"
    
    success "Restoration completed for ${site_name}"
}

# Main WordPress restore function
restore_wordpress() {
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="/var/log/website_restore_${TIMESTAMP}.log"
    
    log_message "Starting WordPress restoration process"
    log_message "Log file: ${LOG_FILE}"
    
    check_wpcli
    
    if ! list_and_store_backups; then
        error_exit "No backups available for restoration"
    fi
    
    echo
    read -p "Enter the number of the backup you want to restore: " backup_number
    
    if ! [[ "$backup_number" =~ ^[0-9]+$ ]] || \
       [ "$backup_number" -lt 1 ] || \
       [ "$backup_number" -gt ${#backup_files[@]} ]; then
        error_exit "Invalid backup number selected"
    fi
    
    selected_backup="${backup_files[$((backup_number-1))]}"
    log_message "Selected backup: $(basename "${selected_backup}")"
    
    read -p "Enter the target site name for restoration: " TARGET_SITE
    
    if [ -d "${WWW_PATH}/${TARGET_SITE}" ]; then
        read -p "Target directory already exists. Do you want to overwrite? (y/n): " confirm
        if [ "${confirm}" != "y" ]; then
            error_exit "Restoration cancelled by user"
        fi
        log_message "Removing existing directory"
        rm -rf "${WWW_PATH}/${TARGET_SITE}"
    fi
    
    if is_wordpress_backup "${selected_backup}"; then
        restore_wordpress_site "${selected_backup}" "${TARGET_SITE}"
    else
        error_exit "Selected backup is not a WordPress backup"
    fi
    
    success "WordPress restoration process completed successfully"
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

# Transfer backups function
transfer_backups() {
    info "Starting backup transfer process..."
    
    # Ask if the user is on the source/old server
    read -p "Are you on the source/old server? (yes/no): " ON_SOURCE_SERVER
    if [[ "$ON_SOURCE_SERVER" != "yes" ]]; then
        error_exit "Please run this script on the source/old server."
    fi
    
    # Prompt for the destination IP address
    read -p "Enter the destination IP address: " DEST_IP
    
    if [[ -z "$DEST_IP" ]]; then
        error_exit "Destination IP address cannot be empty"
    fi
    
    # Set the destination backup directory
    DEST_BACKUP_DIR="/website_backups"
    
    # Test SSH connection
    info "Testing SSH connection to ${DEST_IP}..."
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes root@${DEST_IP} exit 2>/dev/null; then
        error_exit "Cannot establish SSH connection to ${DEST_IP}. Please check connectivity and SSH keys."
    fi
    
    # Create the backup directory on the destination server if it doesn't exist
    info "Creating backup directory on destination server..."
    ssh root@${DEST_IP} "mkdir -p ${DEST_BACKUP_DIR}" || error_exit "Failed to create backup directory on destination"
    
    # Transfer the backup files
    info "Transferring backup files..."
    rsync -avz --progress /website_backups/ root@${DEST_IP}:${DEST_BACKUP_DIR} || error_exit "Failed to transfer backup files"
    
    success "Backup transfer completed successfully!"
}

# Main function
main() {
    while true; do
        show_menu
        read -p "Select option: " choice

        case $choice in
            1) backup_wordpress ;;
            2) restore_wordpress ;;
            3) backup_postgres ;;
            4) restore_postgresql ;;
            5) transfer_backups ;;
            6) echo -e "${GREEN}Thank you for using Backup and Restore!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 2 ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Start script
main