# Important: Point the DNS correctly both main domain and www and subdomains
# Use nano command to copy code from windows to Linux else there will be error due to Windows-style line endings
# sudo nano restore.sh
# bash restore.sh
# rm -r /root/restore.sh

#!/bin/bash

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"


TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/website_restore_${TIMESTAMP}.log"

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ${1}"
    echo "${message}"
    echo "${message}" >> "${LOG_FILE}"
}

# Function to handle errors
error_exit() {
    log_message "ERROR: ${1}"
    exit 1
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

# Function to check if a backup is WordPress
is_wordpress_backup() {
    local backup_file="${1}"
    tar -tzf "${backup_file}" | grep -q "wp-config.php"
    return $?
}

# Function to restore WordPress site
restore_wordpress() {
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
    
    # Fix permissions (optimized)
    log_message "Setting correct permissions"
    chown -R www-data:www-data "${target_dir}"
    chmod 755 "${target_dir}"
    
    log_message "Restoration completed for ${site_name}"
}

# Function to restore HTML site
restore_html() {
    local backup_file="${1}"
    local site_name="${2}"
    local target_dir="${WWW_PATH}/${site_name}"
    
    log_message "Starting HTML site restoration for: ${site_name}"
    
    mkdir -p "${target_dir}" || error_exit "Failed to create target directory"
    tar -xzf "${backup_file}" -C "${WWW_PATH}" || error_exit "Failed to extract backup"
    
    chown -R www-data:www-data "${target_dir}"
    chmod 755 "${target_dir}"
    
    log_message "Restoration completed for ${site_name}"
}

# Function to list backups with serial numbers
list_and_store_backups() {
    echo "Available backups:"
    echo "----------------"
    
    readarray -t backup_files < <(find "${BACKUP_DIR}" -maxdepth 1 -name "*.tar.gz" -type f | sort)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo "No backups found"
        exit 1
    fi
    
    for i in "${!backup_files[@]}"; do
        filename=$(basename "${backup_files[$i]}")
        echo "[$((i+1))] ${filename}"
    done
    
    return 0
}

# Main script execution
echo "Website Backup Restoration Tool"
echo "=============================="

check_wpcli

log_message "Starting restoration process"
log_message "Log file: ${LOG_FILE}"

list_and_store_backups

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
    restore_wordpress "${selected_backup}" "${TARGET_SITE}"
else
    restore_html "${selected_backup}" "${TARGET_SITE}"
fi

log_message "Restoration process completed successfully"
