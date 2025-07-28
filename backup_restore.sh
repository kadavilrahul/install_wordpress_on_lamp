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

# Menu system
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                            Backup and Restore Menu"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Main Menu:${NC}"
    echo "  1) Backup WordPress Sites - Create backups of WordPress websites and databases"
    echo "  2) Restore WordPress Sites - Restore WordPress sites from backup archives"
    echo "  3) Backup PostgreSQL - Create PostgreSQL database backups"
    echo "  4) Restore PostgreSQL - Restore PostgreSQL databases from backup files"
    echo "  5) Transfer Backups - Copy backups to another server via SSH"
    echo "  0) Exit - Return to main menu"
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

# Function to setup SSH keys for passwordless authentication
setup_ssh_keys() {
    local dest_ip="$1"
    local dest_user="$2"
    local ssh_port="$3"
    
    info "Setting up SSH keys for passwordless authentication..."
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "backup-transfer-$(hostname)"
    fi
    
    # Copy public key to destination
    info "Copying public key to destination server..."
    if ssh-copy-id -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -p ${ssh_port} ${dest_user}@${dest_ip}; then
        success "SSH key setup completed successfully!"
        return 0
    else
        warn "SSH key setup failed. You'll need to use password authentication."
        return 1
    fi
}

# Function to test network connectivity
test_connectivity() {
    local dest_ip="$1"
    local ssh_port="$2"
    
    info "Testing network connectivity to ${dest_ip}:${ssh_port}..."
    
    # Test basic TCP connectivity
    if timeout 10 bash -c "</dev/tcp/${dest_ip}/${ssh_port}" 2>/dev/null; then
        success "Network connectivity test passed"
        return 0
    else
        error_exit "Cannot connect to ${dest_ip}:${ssh_port}. Please check IP address, port, and firewall settings."
    fi
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

# Function to discover and list WordPress sites
discover_wordpress_sites() {
    local sites=()
    local site_types=()
    
    if [ -d "${WWW_PATH}" ]; then
        for site_dir in "${WWW_PATH}"/*; do
            if [ -d "${site_dir}" ]; then
                site_name=$(basename "${site_dir}")
                
                # Skip the html directory
                if [ "${site_name}" = "html" ]; then
                    continue
                fi
                
                if is_wordpress "${site_dir}"; then
                    sites+=("${site_name}")
                    site_types+=("Main Domain")
                else
                    # Check for subdirectory WordPress installations
                    for subdir in "${site_dir}"/*; do
                        if [ -d "${subdir}" ] && is_wordpress "${subdir}"; then
                            subdir_name=$(basename "${subdir}")
                            sites+=("${site_name}/${subdir_name}")
                            site_types+=("Subdirectory")
                        fi
                    done
                fi
            fi
        done
    fi
    
    # Return the arrays (using global variables for simplicity)
    DISCOVERED_SITES=("${sites[@]}")
    DISCOVERED_TYPES=("${site_types[@]}")
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
    
    # Discover WordPress sites
    discover_wordpress_sites
    
    if [ ${#DISCOVERED_SITES[@]} -eq 0 ]; then
        error_exit "No WordPress sites found in ${WWW_PATH}"
    fi
    
    # Show site selection menu
    echo
    echo -e "${CYAN}Available WordPress Sites:${NC}"
    echo "----------------------------------------"
    for i in "${!DISCOVERED_SITES[@]}"; do
        echo -e "  $((i+1))) ${GREEN}${DISCOVERED_SITES[i]}${NC} (${DISCOVERED_TYPES[i]})"
    done
    echo -e "  $((${#DISCOVERED_SITES[@]}+1))) ${YELLOW}Backup ALL websites${NC}"
    echo -e "  $((${#DISCOVERED_SITES[@]}+2))) ${RED}Cancel${NC}"
    echo "----------------------------------------"
    echo
    
    read -p "Select option (1-$((${#DISCOVERED_SITES[@]}+2))): " choice
    
    # Handle user choice
    if [ "$choice" = "$((${#DISCOVERED_SITES[@]}+2))" ]; then
        log_message "Backup cancelled by user"
        echo "Backup cancelled."
        return
    elif [ "$choice" = "$((${#DISCOVERED_SITES[@]}+1))" ]; then
        # Backup all sites
        log_message "User selected to backup all WordPress sites"
        echo "Backing up all WordPress sites..."
        
        for i in "${!DISCOVERED_SITES[@]}"; do
            local site_name="${DISCOVERED_SITES[i]}"
            local site_type="${DISCOVERED_TYPES[i]}"
            
            if [ "$site_type" = "Subdirectory" ]; then
                local main_domain=$(echo "$site_name" | cut -d'/' -f1)
                local subdir=$(echo "$site_name" | cut -d'/' -f2)
                local site_dir="${WWW_PATH}/${main_domain}/${subdir}"
            else
                local site_dir="${WWW_PATH}/${site_name}"
            fi
            
            log_message "Processing site: ${site_name} (${site_type})"
            backup_wordpress_site "${site_dir}" "${site_name}"
        done
    else
        # Backup selected site
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#DISCOVERED_SITES[@]} ]; then
            error_exit "Invalid selection"
        fi
        
        local selected_site="${DISCOVERED_SITES[$((choice-1))]}"
        local selected_type="${DISCOVERED_TYPES[$((choice-1))]}"
        
        log_message "User selected to backup: ${selected_site} (${selected_type})"
        echo "Backing up: ${selected_site}..."
        
        if [ "$selected_type" = "Subdirectory" ]; then
            local main_domain=$(echo "$selected_site" | cut -d'/' -f1)
            local subdir=$(echo "$selected_site" | cut -d'/' -f2)
            local site_dir="${WWW_PATH}/${main_domain}/${subdir}"
        else
            local site_dir="${WWW_PATH}/${selected_site}"
        fi
        
        backup_wordpress_site "${site_dir}" "${selected_site}"
    fi
    
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
    
    # Install required packages
    info "Checking required packages..."
    if ! command -v rsync &> /dev/null; then
        info "Installing rsync..."
        apt update -qq && apt install -y rsync || error_exit "Failed to install rsync"
    fi
    
    if ! command -v ssh &> /dev/null; then
        info "Installing openssh-client..."
        apt update -qq && apt install -y openssh-client || error_exit "Failed to install openssh-client"
    fi
    
    # Check if backup directory exists and has files
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        error_exit "No backups found in $BACKUP_DIR. Please create backups first."
    fi
    
    # Show available backups
    echo -e "${CYAN}Available backup files:${NC}"
    ls -lah "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No .tar.gz backup files found"
    ls -lah "$BACKUP_DIR"/*.dump 2>/dev/null || echo "No .dump backup files found"
    echo
    
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
    
    # Prompt for destination username (default: root)
    read -p "Enter destination username (default: root): " DEST_USER
    DEST_USER=${DEST_USER:-root}
    
    # Prompt for destination port (default: 22)
    read -p "Enter SSH port (default: 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    
    # Set the destination backup directory
    read -p "Enter destination backup directory (default: /website_backups): " DEST_BACKUP_DIR
    DEST_BACKUP_DIR=${DEST_BACKUP_DIR:-/website_backups}
    
    # Test basic connectivity first
    test_connectivity "$DEST_IP" "$SSH_PORT"
    
    # Test SSH connection with different methods
    info "Testing SSH connection to ${DEST_USER}@${DEST_IP}:${SSH_PORT}..."
    
    # First try with key-based authentication
    if ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o BatchMode=yes -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} exit 2>/dev/null; then
        info "SSH key authentication successful"
        SSH_AUTH_METHOD="key"
    else
        warn "SSH key authentication failed."
        
        # Ask if user wants to setup SSH keys
        read -p "Would you like to setup SSH keys for passwordless authentication? (y/n): " SETUP_KEYS
        if [[ "$SETUP_KEYS" =~ ^[Yy]$ ]]; then
            if setup_ssh_keys "$DEST_IP" "$DEST_USER" "$SSH_PORT"; then
                SSH_AUTH_METHOD="key"
            else
                SSH_AUTH_METHOD="password"
            fi
        else
            SSH_AUTH_METHOD="password"
        fi
        
        # If still using password, test the connection
        if [ "$SSH_AUTH_METHOD" = "password" ]; then
            info "Testing password authentication..."
            if ! ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} exit; then
                error_exit "SSH connection failed. Please check credentials and connectivity."
            fi
        fi
    fi
    
    # Create the backup directory on the destination server if it doesn't exist
    info "Creating backup directory on destination server..."
    ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "mkdir -p ${DEST_BACKUP_DIR}" || error_exit "Failed to create backup directory on destination"
    
    # Ask which files to transfer
    echo -e "${CYAN}Transfer options:${NC}"
    echo "1) Transfer all backup files"
    echo "2) Transfer only WordPress backups (.tar.gz)"
    echo "3) Transfer only database backups (.dump)"
    echo "4) Select specific files"
    read -p "Select option (1-4): " TRANSFER_OPTION
    
    case $TRANSFER_OPTION in
        1)
            TRANSFER_PATTERN="*"
            # Verify files exist
            if [ -z "$(ls -A ${BACKUP_DIR}/ 2>/dev/null)" ]; then
                warn "No files found in backup directory"
                return
            fi
            ;;
        2)
            TRANSFER_PATTERN="*.tar.gz"
            # Verify .tar.gz files exist
            if [ -z "$(ls ${BACKUP_DIR}/*.tar.gz 2>/dev/null)" ]; then
                warn "No .tar.gz files found in backup directory"
                return
            fi
            ;;
        3)
            TRANSFER_PATTERN="*.dump"
            # Verify .dump files exist
            if [ -z "$(ls ${BACKUP_DIR}/*.dump 2>/dev/null)" ]; then
                warn "No .dump files found in backup directory"
                return
            fi
            ;;
        4)
            echo "Available files:"
            readarray -t available_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" -o -name "*.zip" \) 2>/dev/null | sort)
            
            if [ ${#available_files[@]} -eq 0 ]; then
                warn "No backup files found in $BACKUP_DIR"
                TRANSFER_PATTERN=""
            else
                for i in "${!available_files[@]}"; do
                    filename=$(basename "${available_files[$i]}")
                    filesize=$(du -sh "${available_files[$i]}" 2>/dev/null | cut -f1 || echo "unknown")
                    echo "  $((i+1))) $filename ($filesize)"
                done
                
                read -p "Enter file numbers to transfer (space-separated, e.g., '1 3 5' or '1-3'): " FILE_NUMBERS
                
                if [[ -z "$FILE_NUMBERS" ]]; then
                    warn "No files selected."
                    TRANSFER_PATTERN=""
                else
                    # Parse file numbers and build list of selected files
                    selected_files=()
                    
                    # Clean up input and handle ranges
                    FILE_NUMBERS=$(echo "$FILE_NUMBERS" | sed -e 's/,/ /g' -e 's/  */ /g')
                    
                    for num_part in $FILE_NUMBERS; do
                        if [[ "$num_part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                            # Handle range like "1-3"
                            start=${BASH_REMATCH[1]}
                            end=${BASH_REMATCH[2]}
                            for j in $(seq "$start" "$end"); do
                                if [ "$j" -ge 1 ] && [ "$j" -le "${#available_files[@]}" ]; then
                                    selected_files+=("${available_files[$((j-1))]}")
                                fi
                            done
                        elif [[ "$num_part" =~ ^[0-9]+$ ]]; then
                            # Handle single number
                            if [ "$num_part" -ge 1 ] && [ "$num_part" -le "${#available_files[@]}" ]; then
                                selected_files+=("${available_files[$((num_part-1))]}")
                            fi
                        fi
                    done
                    
                    if [ ${#selected_files[@]} -eq 0 ]; then
                        warn "No valid file numbers selected."
                        TRANSFER_PATTERN=""
                    else
                        info "Selected files for transfer:"
                        for file in "${selected_files[@]}"; do
                            echo "  - $(basename "$file")"
                        done
                        
                        # Set TRANSFER_PATTERN to empty to use selected_files array instead
                        TRANSFER_PATTERN="SELECTIVE"
                    fi
                fi
            fi
            ;;
        *)
            TRANSFER_PATTERN="*"
            warn "Invalid option. Transferring all files."
            ;;
    esac
    
    # Transfer the backup files
    if [ "$TRANSFER_PATTERN" = "SELECTIVE" ]; then
        info "Transferring selected backup files..."
        
        # Transfer each selected file individually
        transfer_failed=false
        for file in "${selected_files[@]}"; do
            filename=$(basename "$file")
            info "Transferring: $filename"
            
            if [ "$SSH_AUTH_METHOD" = "key" ]; then
                if ! rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no -p ${SSH_PORT}" \
                    "$file" ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/; then
                    warn "Failed to transfer: $filename"
                    transfer_failed=true
                fi
            else
                if ! rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no -p ${SSH_PORT}" \
                    "$file" ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/; then
                    warn "Failed to transfer: $filename"
                    transfer_failed=true
                fi
            fi
        done
        
        if [ "$transfer_failed" = true ]; then
            error_exit "Some files failed to transfer"
        fi
    elif [ -n "$TRANSFER_PATTERN" ]; then
        info "Transferring backup files (pattern: $TRANSFER_PATTERN)..."
        
        if [ "$SSH_AUTH_METHOD" = "key" ]; then
            rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no -p ${SSH_PORT}" \
                ${BACKUP_DIR}/${TRANSFER_PATTERN} ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/ || error_exit "Failed to transfer backup files"
        else
            rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no -p ${SSH_PORT}" \
                ${BACKUP_DIR}/${TRANSFER_PATTERN} ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/ || error_exit "Failed to transfer backup files"
        fi
    else
        warn "No files selected for transfer."
        return
    fi
    
    # Verify transfer
    info "Verifying transfer..."
    
    if [ "$TRANSFER_PATTERN" = "SELECTIVE" ]; then
        # For selective transfers, verify each transferred file exists on remote
        info "Verifying selective file transfer..."
        verification_failed=false
        
        for file in "${selected_files[@]}"; do
            filename=$(basename "$file")
            if [ "$SSH_AUTH_METHOD" = "key" ]; then
                if ! ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "test -f ${DEST_BACKUP_DIR}/$filename" 2>/dev/null; then
                    warn "Verification failed for: $filename"
                    verification_failed=true
                fi
            else
                if ! ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "test -f ${DEST_BACKUP_DIR}/$filename" 2>/dev/null; then
                    warn "Verification failed for: $filename"
                    verification_failed=true
                fi
            fi
        done
        
        if [ "$verification_failed" = true ]; then
            warn "Some files failed verification on remote server"
        else
            success "All selected files verified successfully on remote server"
        fi
    else
        # For pattern-based transfers, use the original logic
        if [ "$SSH_AUTH_METHOD" = "key" ]; then
            REMOTE_FILES=$(ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "ls -1 ${DEST_BACKUP_DIR}/ 2>/dev/null | wc -l")
        else
            REMOTE_FILES=$(ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "ls -1 ${DEST_BACKUP_DIR}/ 2>/dev/null | wc -l")
        fi
        
        case $TRANSFER_OPTION in
            1) # All files
                LOCAL_FILES=$(ls -1 ${BACKUP_DIR}/ 2>/dev/null | wc -l)
                info "Local files: $LOCAL_FILES, Remote files: $REMOTE_FILES"
                ;;
            2) # WordPress backups only
                LOCAL_FILES=$(find ${BACKUP_DIR} -maxdepth 1 -name "*.tar.gz" 2>/dev/null | wc -l)
                info "Local .tar.gz files: $LOCAL_FILES, Total remote files: $REMOTE_FILES"
                ;;
            3) # Database backups only
                LOCAL_FILES=$(find ${BACKUP_DIR} -maxdepth 1 -name "*.dump" 2>/dev/null | wc -l)
                info "Local .dump files: $LOCAL_FILES, Total remote files: $REMOTE_FILES"
                ;;
        esac
    fi
    
    success "Backup transfer completed successfully!"
    info "Files transferred to: ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/"
}

# Main function
main() {
    while true; do
        show_menu
        read -p "Select option: " choice

        case $choice in
            1) 
                backup_wordpress
                echo
                read -p "Press Enter to continue..."
                ;;
            2) 
                restore_wordpress
                echo
                read -p "Press Enter to continue..."
                ;;
            3) 
                backup_postgres
                echo
                read -p "Press Enter to continue..."
                ;;
            4) 
                restore_postgresql
                echo
                read -p "Press Enter to continue..."
                ;;
            5) 
                transfer_backups
                echo
                read -p "Press Enter to continue..."
                ;;
            0) 
                echo -e "${GREEN}Thank you for using Backup and Restore!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Invalid option${NC}"
                sleep 2
                ;;
        esac
    done
}

# Start script
main