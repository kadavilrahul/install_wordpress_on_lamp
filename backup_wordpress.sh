# sudo nano backup.sh
# bash backup.sh
# rm -r /root/backup.sh
# backs up all wordpress websites on a server in location /var/www/ 

#!/bin/bash

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${1}"
}

# Function to handle errors
error_exit() {
    log_message "ERROR: ${1}"
    exit 1
}

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}" || error_exit "Failed to create backup directory"

# Function to check if a directory is a WordPress installation
is_wordpress() {
    if [ -f "${1}/wp-config.php" ]; then
        return 0
    else
        return 1
    fi
}

# Function to backup WordPress site
backup_wordpress() {
    local site_path="${1}"
    local site_name="${2}"
    
    log_message "Starting WordPress backup for: ${site_name}"
    
    # Create database dump without timestamp
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
    
    log_message "Backup completed for ${site_name}"
}

# Function to backup HTML site
backup_html() {
    local site_path="${1}"
    local site_name="${2}"
    
    log_message "Starting HTML backup for: ${site_name}"
    
    # Create backup
    local backup_name="${site_name}_html_backup_${TIMESTAMP}.tar.gz"
    
    pushd "${WWW_PATH}" > /dev/null || error_exit "Cannot change to www directory"
    
    # Handle file changes during backup
    tar --warning=no-file-changed -czf "${BACKUP_DIR}/${backup_name}" \
        --exclude="${site_name}/cache" \
        "${site_name}" || {
        local tar_exit=$?
        if [ $tar_exit -ne 0 ] && [ $tar_exit -ne 1 ]; then
            popd > /dev/null
            error_exit "Tar backup failed for ${site_name}"
        fi
    }
    popd > /dev/null
    
    log_message "Backup completed for ${site_name}"
}

# Main backup process
log_message "Starting backup process"

# Check if WWW_PATH exists
if [ ! -d "${WWW_PATH}" ]; then
    error_exit "WWW_PATH (${WWW_PATH}) does not exist!"
fi

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
            backup_wordpress "${site_dir}" "${site_name}"
        else
            backup_html "${site_dir}" "${site_name}"
        fi
    fi
done

# Cleanup old backups
log_message "Cleaning up old backups"
find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +7 -delete
find "${BACKUP_DIR}" -type f -name "backup_inventory_*.txt" -mtime +7 -delete

log_message "Backup process completed"
