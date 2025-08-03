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

# Function to check if a directory is a WordPress installation
is_wordpress() {
    local dir="${1}"
    
    # Check for wp-config.php (primary indicator)
    if [ -f "${dir}/wp-config.php" ]; then
        return 0
    fi
    
    # Check for wp-config-sample.php and wp-includes (WordPress core files)
    if [ -f "${dir}/wp-config-sample.php" ] && [ -d "${dir}/wp-includes" ] && [ -d "${dir}/wp-content" ]; then
        log_message "Found WordPress installation without wp-config.php at: ${dir}"
        return 0
    fi
    
    # Check for WordPress core files as additional verification
    if [ -f "${dir}/wp-load.php" ] && [ -f "${dir}/wp-blog-header.php" ] && [ -d "${dir}/wp-includes" ]; then
        log_message "Found WordPress core files at: ${dir}"
        return 0
    fi
    
    return 1
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
    
    log_message "Starting WordPress site discovery in ${WWW_PATH}"
    
    if [ -d "${WWW_PATH}" ]; then
        for site_dir in "${WWW_PATH}"/*; do
            if [ -d "${site_dir}" ]; then
                site_name=$(basename "${site_dir}")
                
                # Skip the html directory
                if [ "${site_name}" = "html" ]; then
                    log_message "Skipping html directory"
                    continue
                fi
                
                log_message "Checking directory: ${site_name}"
                
                if is_wordpress "${site_dir}"; then
                    log_message "Found WordPress installation: ${site_name}"
                    sites+=("${site_name}")
                    site_types+=("Main Domain")
                else
                    log_message "Not a WordPress installation, checking subdirectories in: ${site_name}"
                    # Check for subdirectory WordPress installations
                    local found_subdir=false
                    for subdir in "${site_dir}"/*; do
                        if [ -d "${subdir}" ] && is_wordpress "${subdir}"; then
                            subdir_name=$(basename "${subdir}")
                            log_message "Found WordPress in subdirectory: ${site_name}/${subdir_name}"
                            sites+=("${site_name}/${subdir_name}")
                            site_types+=("Subdirectory")
                            found_subdir=true
                        fi
                    done
                    
                    if [ "$found_subdir" = false ]; then
                        log_message "No WordPress installations found in subdirectories of: ${site_name}"
                    fi
                fi
            fi
        done
    else
        log_message "WWW_PATH directory does not exist: ${WWW_PATH}"
    fi
    
    # Also check for WordPress installations that might be in Apache virtual hosts but not detected
    log_message "Cross-referencing with Apache virtual host configurations..."
    if [ -d "/etc/apache2/sites-available" ]; then
        for vhost_file in /etc/apache2/sites-available/*.conf; do
            if [ -f "$vhost_file" ] && [[ "$(basename "$vhost_file")" != "000-default.conf" ]] && [[ "$(basename "$vhost_file")" != "default-ssl.conf" ]]; then
                local domain_name=$(basename "$vhost_file" .conf | sed 's/-le-ssl$//')
                local doc_root=$(grep -i "DocumentRoot" "$vhost_file" | head -1 | awk '{print $2}' 2>/dev/null)
                
                if [ -n "$doc_root" ] && [ -d "$doc_root" ] && is_wordpress "$doc_root"; then
                    # Check if this WordPress site is already in our list
                    local already_found=false
                    for existing_site in "${sites[@]}"; do
                        if [[ "$existing_site" == "$domain_name" ]] || [[ "$doc_root" == "${WWW_PATH}/${existing_site}" ]] || [[ "$doc_root" == "${WWW_PATH}/${existing_site%/*}" ]]; then
                            already_found=true
                            break
                        fi
                    done
                    
                    if [ "$already_found" = false ]; then
                        log_message "Found additional WordPress site from Apache config: ${domain_name} -> ${doc_root}"
                        # Determine the site name based on document root
                        if [[ "$doc_root" == "${WWW_PATH}/"* ]]; then
                            local relative_path="${doc_root#${WWW_PATH}/}"
                            sites+=("${relative_path}")
                            if [[ "$relative_path" == *"/"* ]]; then
                                site_types+=("Subdirectory")
                            else
                                site_types+=("Main Domain")
                            fi
                        fi
                    fi
                fi
            fi
        done
    fi
    
    log_message "WordPress site discovery completed. Found ${#sites[@]} sites."
    
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
    
    # Show additional info about configured domains
    echo -e "${BLUE}ℹ Additional Information:${NC}"
    local all_domains=()
    if [ -d "/etc/apache2/sites-available" ]; then
        for vhost_file in /etc/apache2/sites-available/*.conf; do
            if [ -f "$vhost_file" ] && [[ "$(basename "$vhost_file")" != "000-default.conf" ]] && [[ "$(basename "$vhost_file")" != "default-ssl.conf" ]]; then
                local domain_name=$(basename "$vhost_file" .conf | sed 's/-le-ssl$//')
                if [[ ! " ${all_domains[@]} " =~ " ${domain_name} " ]]; then
                    all_domains+=("$domain_name")
                fi
            fi
        done
        
        if [ ${#all_domains[@]} -gt 0 ]; then
            echo -e "  ${BLUE}Configured domains in Apache:${NC}"
            for domain in "${all_domains[@]}"; do
                local has_wp=false
                for wp_site in "${DISCOVERED_SITES[@]}"; do
                    if [[ "$wp_site" == "$domain" ]] || [[ "$wp_site" == *"$domain"* ]]; then
                        has_wp=true
                        break
                    fi
                done
                if [ "$has_wp" = true ]; then
                    echo -e "    - ${GREEN}$domain${NC} (WordPress installed)"
                else
                    echo -e "    - ${YELLOW}$domain${NC} (No WordPress detected)"
                fi
            done
        fi
    fi
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

# Execute the backup function
backup_wordpress