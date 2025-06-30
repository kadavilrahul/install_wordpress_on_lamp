#!/bin/bash

#=============================================================================
# WordPress Master - Minimalistic Installation Script
#=============================================================================

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 (y/n): ${NC}")" -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }
check_system() {
    info "Checking system requirements..."
    ! grep -q "Ubuntu" /etc/os-release && warn "This script is designed for Ubuntu"
    [ "$(df / | awk 'NR==2 {print $4}')" -lt 5242880 ] && error "Insufficient disk space. At least 5GB required"
    ! ping -c 1 google.com &>/dev/null && error "No internet connection detected"
    success "System requirements check passed"
}

# Configuration management
load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" && info "Configuration loaded"; }
save_config() {
    cat > "$CONFIG_FILE" << EOF
ADMIN_EMAIL="$ADMIN_EMAIL"
REDIS_MAX_MEMORY="$REDIS_MAX_MEMORY"
LAST_DOMAIN="$DOMAIN"
LAST_INSTALL_DATE="$(date)"
EOF
    success "Configuration saved"
}

# Menu system
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                    WordPress Master - Minimalistic Tool"
    echo "=============================================================================${NC}"
    echo -e "${YELLOW}Main Menu:${NC}"
    echo "  1) Install LAMP Stack + WordPress    2) Install Apache + SSL Only"
    echo "  3) Install phpMyAdmin               4) Backup WordPress Sites"
    echo "  5) Restore WordPress Sites          6) Backup PostgreSQL"
    echo "  7) Restore PostgreSQL               8) Transfer Backups"
    echo "  9) Adjust PHP Configuration         10) Configure Redis"
    echo "  11) SSH Security Management         12) System Utilities"
    echo "  13) Remove Websites & Databases     14) Remove Orphaned Databases"
    echo "  15) Fix Apache Configs              16) Troubleshooting Guide"
    echo "  17) MySQL Commands Guide            18) System Status Check"
    echo "  19) Exit"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Get installation inputs
get_inputs() {
    local type="$1"
    echo -e "${YELLOW}Installation Configuration:${NC}"
    case $type in
        "main") read -p "Enter domain (e.g., example.com): " DOMAIN; INSTALL_TYPE="main_domain" ;;
        "subdomain") 
            read -p "Enter main domain: " MAIN_DOMAIN
            read -p "Enter subdomain: " SUBDOMAIN
            DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"; INSTALL_TYPE="subdomain" ;;
        "subdirectory")
            read -p "Enter main domain: " MAIN_DOMAIN
            read -p "Enter subdirectory: " WP_SUBDIR
            DOMAIN="$MAIN_DOMAIN"; INSTALL_TYPE="subdirectory" ;;
    esac
    read -p "Enter admin email: " ADMIN_EMAIL
    echo -e "${CYAN}MySQL Password Setup:${NC}"
    echo "Enter a password for MySQL root user (new installations) or your existing MySQL root password"
    while true; do
        read -sp "MySQL root password: " DB_ROOT_PASSWORD; echo
        read -sp "Confirm password: " DB_ROOT_PASSWORD_CONFIRM; echo
        [ "$DB_ROOT_PASSWORD" = "$DB_ROOT_PASSWORD_CONFIRM" ] && break
        echo -e "${RED}Passwords do not match${NC}"
    done
    read -p "Enter Redis memory in GB (default: 1): " REDIS_MAX_MEMORY
    [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    confirm "Proceed with installation?" || return 1
}

# LAMP stack installation
install_lamp() {
    info "Installing LAMP stack..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt upgrade -y || warn "Failed to update system"
    apt install -y apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl php-soap php-bcmath php-xmlrpc php-imagick php-opcache curl wget unzip certbot python3-certbot-apache redis-server || warn "Failed to install LAMP stack"
    
    systemctl enable apache2 mysql redis-server
    systemctl start apache2 mysql redis-server
    a2enmod rewrite ssl headers || warn "Failed to enable Apache modules"
    
    # Secure MySQL - check if password already exists
    if mysql -e "SELECT 1;" 2>/dev/null; then
        # MySQL has no password - set the new one
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD';" || error "Failed to set MySQL password"
        MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
        info "MySQL root password set successfully"
    else
        # MySQL already has a password - test if user provided the correct existing one
        if mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
            info "Using provided MySQL root password"
        else
            warn "MySQL already has a different root password"
            read -sp "Enter existing MySQL root password: " EXISTING_PASSWORD; echo
            mysql -u root -p"$EXISTING_PASSWORD" -e "SELECT 1;" 2>/dev/null && DB_ROOT_PASSWORD="$EXISTING_PASSWORD" && MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD" || error "Invalid MySQL password"
        fi
    fi
    
    mysql $MYSQL_AUTH -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; FLUSH PRIVILEGES;" || warn "MySQL security setup had warnings"
    
    if verify_apache_installed && verify_mysql_installed && verify_php_installed; then
        success "LAMP stack installed successfully"
    else
        warn "Failed to install LAMP stack completely"
    fi
}

# WordPress installation
install_wordpress() {
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && site_dir="/var/www/$MAIN_DOMAIN/$WP_SUBDIR"
    
    mkdir -p "$site_dir" || error "Failed to create site directory"
    cd /tmp && wget https://wordpress.org/latest.tar.gz && tar xzf latest.tar.gz && cp -R wordpress/* "$site_dir/" && rm -rf wordpress latest.tar.gz || error "Failed to download WordPress"
    chown -R www-data:www-data "$site_dir" && chmod -R 755 "$site_dir"
    
    # Database setup
    DB_NAME=$(echo "$DOMAIN" | sed 's/\./_/g' | sed 's/-/_/g')
    [ "$INSTALL_TYPE" = "subdirectory" ] && DB_NAME=$(echo "${MAIN_DOMAIN}_${WP_SUBDIR}" | sed 's/\./_/g' | sed 's/-/_/g')
    DB_USER="${DB_NAME}_user"
    DB_PASSWORD=$(openssl rand -base64 12)
    
    mysql $MYSQL_AUTH -e "CREATE DATABASE $DB_NAME; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" || error "Database creation failed"
    
    # Configure WordPress
    cp "$site_dir/wp-config-sample.php" "$site_dir/wp-config.php"
    sed -i "s#database_name_here#$DB_NAME#g; s#username_here#$DB_USER#g; s#password_here#$DB_PASSWORD#g" "$site_dir/wp-config.php"
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$site_dir/wp-config.php"
    sed -i "/define('DB_COLLATE', '');/a\\$SALTS" "$site_dir/wp-config.php"
    
    cat >> "$site_dir/wp-config.php" << EOF

define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
EOF
    
    if [ "$INSTALL_TYPE" = "subdirectory" ]; then
        cat >> "$site_dir/wp-config.php" << EOF
define('WP_SITEURL', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
define('WP_HOME', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
EOF
    fi
    # After WordPress is configured, set secure permissions
    set_wordpress_permissions "$site_dir"
}

# Apache virtual host and SSL with conflict detection
create_vhost_ssl() {
    local domain="$1"
    local site_dir="$2"
    
    cat > "/etc/apache2/sites-available/$domain.conf" << EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $site_dir
    <Directory $site_dir>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$domain.log
    CustomLog \${APACHE_LOG_DIR}/access_$domain.log combined
</VirtualHost>
EOF
    
    a2ensite "$domain.conf" && systemctl reload apache2 || error "Failed to enable site"
    
    # SSL installation with conflict detection
    if host "$domain" >/dev/null 2>&1; then
        install_ssl_with_conflict_detection "$domain"
    else
        warn "Domain $domain does not resolve, skipping SSL"
    fi
}

# SSL installation with conflict detection
install_ssl_with_conflict_detection() {
    local domain="$1"
    local conflicting_sites=()
    local disabled_sites=()
    
    info "Checking for SSL conflicts..."
    
    # Find potentially conflicting sites
    for site in /etc/apache2/sites-enabled/*.conf; do
        [ -f "$site" ] || continue
        site_name=$(basename "$site")
        site_domain=$(echo "$site_name" | sed 's/-le-ssl\.conf$//' | sed 's/\.conf$//')
        
        # Skip current domain
        [ "$site_domain" = "$domain" ] && continue
        
        # Check if site might conflict
        if [[ "$site_name" == *"-le-ssl.conf" ]] || grep -q "ServerName.*\." "$site" 2>/dev/null; then
            conflicting_sites+=("$site_name")
        fi
    done
    
    # Handle conflicts if found
    if [ ${#conflicting_sites[@]} -gt 0 ]; then
        warn "Found ${#conflicting_sites[@]} potentially conflicting sites"
        
        if confirm "Temporarily disable conflicting sites for SSL installation?"; then
            info "Temporarily disabling conflicting sites..."
            for site in "${conflicting_sites[@]}"; do
                if a2dissite "$site" 2>/dev/null; then
                    disabled_sites+=("$site")
                    info "Disabled: $site"
                fi
            done
            systemctl reload apache2 2>/dev/null
            sleep 2
        fi
    fi
    
    # Install SSL certificate with fallback
    info "Installing SSL certificate for $domain..."
    if certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null; then
        success "SSL certificate installed for $domain"
    elif certbot --apache -d "$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null; then
        success "SSL certificate installed for $domain (main domain only)"
    else
        warn "SSL installation failed - you may need to install manually"
    fi

    if verify_ssl_installed "$domain"; then
        success "SSL certificate installed for $domain"
    else
        warn "Failed to install SSL certificate for $domain"
    fi
    
    # Re-enable disabled sites
    if [ ${#disabled_sites[@]} -gt 0 ]; then
        info "Re-enabling previously disabled sites..."
        for site in "${disabled_sites[@]}"; do
            a2ensite "$site" 2>/dev/null && info "Re-enabled: $site"
        done
        systemctl reload apache2 2>/dev/null
    fi
}

# Redis and WP-CLI setup
setup_tools() {
    # Install WP-CLI
    if ! command -v wp &>/dev/null; then
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp || error "WP-CLI installation failed"
    fi
    
    # Configure Redis
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server
    
    cat >> "$1/wp-config.php" << EOF

// Redis Configuration
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
EOF
}

# Complete WordPress installation
install_lamp_wordpress() {
    echo -e "${YELLOW}WordPress Installation Types:${NC}"
    echo "1) Main Domain  2) Subdomain  3) Subdirectory  4) Back"
    read -p "Select type (1-4): " choice
    
    case $choice in
        1) get_inputs "main" || return ;;
        2) get_inputs "subdomain" || return ;;
        3) get_inputs "subdirectory" || return ;;
        4) return ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 2; install_lamp_wordpress; return ;;
    esac
    
    install_lamp
    install_wordpress
    
    local target_domain="$DOMAIN"
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && target_domain="$MAIN_DOMAIN" && site_dir="/var/www/$MAIN_DOMAIN"
    
    create_vhost_ssl "$target_domain" "$site_dir"
    setup_tools "$site_dir"
    save_config
    
    success "WordPress installation completed!"
    echo -e "${GREEN}Domain: $DOMAIN${NC}"
    echo -e "${GREEN}Database: $DB_NAME / $DB_USER / $DB_PASSWORD${NC}"
    echo -e "${GREEN}Visit: https://$DOMAIN${NC}"
    read -p "Press Enter to continue..."
}

# Apache + SSL only installation
install_apache_ssl_only() {
    read -p "Enter domain name: " DOMAIN
    [ -z "$DOMAIN" ] && error "Domain name required"
    
    apt update -qq && apt install -y apache2 certbot python3-certbot-apache || error "Installation failed"
    a2enmod rewrite ssl
    
    WEB_ROOT="/var/www/$DOMAIN"
    mkdir -p "$WEB_ROOT" && chown -R www-data:www-data "$WEB_ROOT" && chmod -R 755 "$WEB_ROOT"
    
    cat > "$WEB_ROOT/index.html" << EOF
<!DOCTYPE html>
<html><head><title>Welcome to $DOMAIN</title>
<style>body{font-family:Arial;margin:40px;background:#f4f4f4}.container{background:white;padding:40px;border-radius:10px;max-width:600px;margin:0 auto}</style>
</head><body><div class="container"><h1>🎉 Welcome to $DOMAIN</h1><p>Your website is live and ready!</p></div></body></html>
EOF
    
    create_vhost_ssl "$DOMAIN" "$WEB_ROOT"
    success "Apache + SSL setup completed for $DOMAIN"
    read -p "Press Enter to continue..."
}

# phpMyAdmin installation
install_phpmyadmin() {
    read -p "Enter web directory (default: /var/www): " WP_DIR
    [[ -z "$WP_DIR" ]] && WP_DIR="/var/www"
    [ ! -d "$WP_DIR" ] && error "Directory $WP_DIR does not exist"
    
    export DEBIAN_FRONTEND=noninteractive
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    
    apt update -y && apt install -y phpmyadmin || error "phpMyAdmin installation failed"
    ln -sf /usr/share/phpmyadmin "$WP_DIR/phpmyadmin"
    a2enconf phpmyadmin && systemctl restart apache2
    
    success "phpMyAdmin installed! Access at: http://your-domain/phpmyadmin"
    read -p "Press Enter to continue..."
}

# WordPress backup
backup_wordpress() {
    local WWW_PATH="/var/www"
    local BACKUP_DIR="/website_backups"
    local TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    
    mkdir -p "$BACKUP_DIR" || error "Failed to create backup directory"
    ! command -v wp &>/dev/null && setup_tools ""
    
    info "Starting WordPress backup process..."
    local backup_count=0
    
    for site_dir in "$WWW_PATH"/*; do
        [ ! -d "$site_dir" ] && continue
        site_name=$(basename "$site_dir")
        [ "$site_name" = "html" ] && continue
        
        if [ -f "$site_dir/wp-config.php" ]; then
            info "Backing up $site_name..."
            
            # Database export
            wp db export "$site_dir/${site_name}_db.sql" --path="$site_dir" --allow-root 2>/dev/null || warn "DB export failed for $site_name"
            
            # Create archive
            pushd "$WWW_PATH" >/dev/null
            tar --warning=no-file-changed -czf "$BACKUP_DIR/${site_name}_backup_${TIMESTAMP}.tar.gz" \
                --exclude="$site_name/wp-content/cache" \
                --exclude="$site_name/wp-content/wpo-cache" \
                "$site_name" 2>/dev/null || warn "Backup failed for $site_name"
            popd >/dev/null
            
            rm -f "$site_dir/${site_name}_db.sql"
            ((backup_count++))
            success "Backup completed for $site_name"
        fi
    done
    
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
    [ $backup_count -eq 0 ] && warn "No WordPress sites found" || success "$backup_count sites backed up to $BACKUP_DIR"
    read -p "Press Enter to continue..."
}

# WordPress restore
restore_wordpress() {
    local BACKUP_DIR="/website_backups"
    local WWW_PATH="/var/www"

    # Step 1: Get MySQL credentials first
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL server not accessible."
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"

    # Step 2: Select the backup file
    ! command -v wp &>/dev/null && setup_tools ""
    echo -e "${YELLOW}Available backups:${NC}"
    readarray -t backup_files < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r)
    [ ${#backup_files[@]} -eq 0 ] && { warn "No backups found in $BACKUP_DIR"; read -p "Press Enter..."; return; }

    for i in "${!backup_files[@]}"; do
        echo "[$((i+1))] $(basename "${backup_files[$i]}")"
    done
    read -p "Enter backup number: " backup_number
    [[ ! "$backup_number" =~ ^[0-9]+$ ]] || [ "$backup_number" -lt 1 ] || [ "$backup_number" -gt ${#backup_files[@]} ] && error "Invalid backup number"
    
    local selected_backup="${backup_files[$((backup_number-1))]}"
    
    # Step 3: Get the target site name and original site name from archive
    read -p "Enter the new domain/site name for the restored site: " TARGET_SITE
    [ -z "$TARGET_SITE" ] && error "Target site name cannot be empty."

    local original_site_name=$(tar -tf "$selected_backup" 2>/dev/null | head -n 1 | cut -f1 -d"/")
    if [ -z "$original_site_name" ]; then
        error "Could not determine root directory name from backup archive."
    fi
    info "Original site name in backup is '$original_site_name'."

    # Step 4: Extract backup and rename directory
    if [ -d "$WWW_PATH/$TARGET_SITE" ]; then
        confirm "Site '$TARGET_SITE' already exists. Overwrite?" || { info "Cancelled."; return; }
        rm -rf "$WWW_PATH/$TARGET_SITE"
    fi
    
    # Remove old directory if it exists from a previous failed attempt
    [ -d "$WWW_PATH/$original_site_name" ] && rm -rf "$WWW_PATH/$original_site_name"
    
    info "Restoring files from $(basename "$selected_backup")..."
    if ! tar -xzf "$selected_backup" -C "$WWW_PATH"; then
        error "Failed to extract backup archive."
    fi
    
    # Rename the extracted folder to the target site name
    if [ "$original_site_name" != "$TARGET_SITE" ]; then
        info "Renaming '$WWW_PATH/$original_site_name' to '$WWW_PATH/$TARGET_SITE'..."
        mv "$WWW_PATH/$original_site_name" "$WWW_PATH/$TARGET_SITE" || error "Failed to rename site directory."
    fi
    
    local target_dir="$WWW_PATH/$TARGET_SITE"
    if [ ! -d "$target_dir" ] || [ ! -f "$target_dir/wp-config.php" ]; then
        error "Restored files are incomplete or wp-config.php is missing."
    fi
    
    # Step 5: Read DB credentials from restored wp-config.php
    info "Reading database credentials from restored wp-config.php..."
    DB_NAME=$(grep "DB_NAME" "$target_dir/wp-config.php" | cut -d"'" -f4)
    DB_USER=$(grep "DB_USER" "$target_dir/wp-config.php" | cut -d"'" -f4)
    DB_PASSWORD=$(grep "DB_PASSWORD" "$target_dir/wp-config.php" | cut -d"'" -f4)
    
    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        error "Could not read database credentials from wp-config.php. Cannot proceed."
    fi
    success "Credentials found: DB: $DB_NAME, User: $DB_USER"

    # Step 6: Create database and user
    info "Re-creating database and user..."
    mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
    mysql $MYSQL_AUTH -e "CREATE DATABASE \`$DB_NAME\`;" || error "Failed to create new database."
    mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
    mysql $MYSQL_AUTH -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" || error "Failed to create new user."
    mysql $MYSQL_AUTH -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;"
    success "Database and user created successfully."

    # Step 7: Import the database content
    local db_dump_file=$(find "$target_dir" -maxdepth 1 -name "*_db.sql" -o -name "*.sql" | head -n 1)

    if [ -z "$db_dump_file" ]; then
        warn "No .sql file found in backup. Skipping database import."
    else
        info "Importing database from $(basename "$db_dump_file")..."
        # Use wp-cli to import the database
        wp db import "$db_dump_file" --path="$target_dir" --allow-root || error "Database import failed."
        rm -f "$db_dump_file" # Clean up the sql file
        success "Database imported successfully."
    fi

    # Step 8: Update domain in database if it changed
    if [ "$original_site_name" != "$TARGET_SITE" ]; then
        info "Updating domain in database from '$original_site_name' to '$TARGET_SITE'..."
        wp search-replace "$original_site_name" "$TARGET_SITE" --all-tables --skip-columns=guid --path="$target_dir" --allow-root
        success "Domain updated in database."
    fi

    # Step 9: Fix file permissions and clean up
    rm -f "$target_dir/wp-content/object-cache.php" "$target_dir/wp-content/advanced-cache.php"
    check_maintenance_file "$target_dir"
    
    rm -f "$target_dir/.maintenance" # Remove maintenance file
    
    info "Setting secure file and directory permissions..."
    set_wordpress_permissions "$target_dir"
    
    if [ -f "$target_dir/.maintenance" ]; then
        warn "Failed to remove maintenance file. Your site might be stuck in maintenance mode."
    else
        success "Maintenance file removed."
    fi
    # Step 10: Set up Apache and SSL
    info "Setting up Apache virtual host and SSL for $TARGET_SITE..."
    read -p "Enter admin email for SSL certificate: " ADMIN_EMAIL
    create_vhost_ssl "$TARGET_SITE" "$target_dir"

    success "Restoration completed for $TARGET_SITE"
    read -p "Press Enter to continue..."
}

# PostgreSQL backup
backup_postgresql() {
    read -p "Database name (default: your_db): " DB_NAME; [[ -z "$DB_NAME" ]] && DB_NAME="your_db"
    read -p "Database user (default: your_user): " DB_USER; [[ -z "$DB_USER" ]] && DB_USER="your_user"
    
    local BACKUP_DIR="/website_backups/postgres"
    mkdir -p "$BACKUP_DIR" && chown postgres:postgres "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
    
    ! command -v psql &>/dev/null && { apt update -y && apt install -y postgresql postgresql-contrib || error "PostgreSQL installation failed"; }
    systemctl start postgresql && systemctl enable postgresql
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$BACKUP_DIR/${DB_NAME}_${timestamp}.dump" || error "Backup failed"
    find "$BACKUP_DIR" -name "*.dump" -mtime +30 -delete
    
    success "PostgreSQL backup completed: $BACKUP_DIR/${DB_NAME}_${timestamp}.dump"
    read -p "Press Enter to continue..."
}

# PostgreSQL restore
restore_postgresql() {
    read -p "Database name (default: your_db): " DB_NAME; [[ -z "$DB_NAME" ]] && DB_NAME="your_db"
    read -p "Database user (default: your_user): " DB_USER; [[ -z "$DB_USER" ]] && DB_USER="your_user"
    read -sp "Database password: " DB_PASS; echo
    
    local BACKUP_DIR="/website_backups/postgres"
    local DUMP_FILE=$(find "$BACKUP_DIR" -name "*.dump" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -n 1 | awk '{print $2}')
    
    [ -z "$DUMP_FILE" ] && { warn "No dump file found in $BACKUP_DIR"; read -p "Press Enter..."; return; }
    info "Using backup: $DUMP_FILE"
    
    ! command -v psql &>/dev/null && { apt update -y && apt install -y postgresql postgresql-contrib || error "PostgreSQL installation failed"; }
    systemctl start postgresql && systemctl enable postgresql
    
    sudo -u postgres psql << EOF
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME;
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    sudo -u postgres pg_restore --clean --if-exists -d "$DB_NAME" "$DUMP_FILE" || warn "Some restore warnings occurred"
    success "PostgreSQL restoration completed"
    read -p "Press Enter to continue..."
}

# Transfer backups
transfer_backups() {
    read -p "Are you on the source server? (yes/no): " ON_SOURCE
    [[ "$ON_SOURCE" != "yes" ]] && { warn "Run this on the source server"; read -p "Press Enter..."; return; }
    
    read -p "Enter destination IP: " DEST_IP
    [ -z "$DEST_IP" ] && error "Destination IP required"
    
    local SOURCE_DIR="/website_backups"
    [ ! -d "$SOURCE_DIR" ] && error "Source backup directory does not exist"
    
    ssh root@"$DEST_IP" "mkdir -p /website_backups" || error "Failed to create destination directory"
    rsync -avz --progress "$SOURCE_DIR/" root@"$DEST_IP":"/website_backups" || error "Transfer failed"
    
    success "Backup transfer completed to $DEST_IP"
    read -p "Press Enter to continue..."
}

# PHP configuration
adjust_php_config() {
    local PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    [ -z "$PHP_VERSION" ] && error "PHP not installed"
    
    info "Adjusting PHP $PHP_VERSION configuration..."
    for ini in "/etc/php/$PHP_VERSION/cli/php.ini" "/etc/php/$PHP_VERSION/apache2/php.ini" "/etc/php/$PHP_VERSION/fpm/php.ini"; do
        [ -f "$ini" ] && sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/; s/^post_max_size = .*/post_max_size = 64M/; s/^memory_limit = .*/memory_limit = 512M/; s/^max_execution_time = .*/max_execution_time = 300/' "$ini"
    done
    
    systemctl restart apache2 php"$PHP_VERSION"-fpm 2>/dev/null || true
    success "PHP configuration updated"
    read -p "Press Enter to continue..."
}

# Redis configuration
configure_redis() {
    read -p "Redis memory in GB (default: 1): " REDIS_MAX_MEMORY; [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    
    ! command -v redis-server &>/dev/null && { apt update -y && apt install -y redis-server || error "Redis installation failed"; }
    
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server && systemctl enable redis-server
    
    success "Redis configured with ${REDIS_MAX_MEMORY}GB memory"
    read -p "Press Enter to continue..."
}

# SSH security management
ssh_security_management() {
    echo "1) Disable root SSH  2) Enable root SSH  3) Back"
    read -p "Choose (1-3): " choice
    
    case $choice in
        1) sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config* 2>/dev/null; systemctl restart ssh; success "Root SSH disabled" ;;
        2) sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config* 2>/dev/null; systemctl restart ssh; success "Root SSH enabled" ;;
        3) return ;;
        *) warn "Invalid option"; sleep 1; ssh_security_management; return ;;
    esac
    read -p "Press Enter to continue..."
}

# System utilities
system_utilities() {
    read -p "Swap size in GB (default: 2): " SWAP_SIZE; [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="2"
    
    confirm "Update system?" && { apt update && apt upgrade -y || warn "Update failed"; }
    
    if confirm "Install UFW firewall?"; then
        apt install -y ufw && ufw --force enable && ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 3306 && success "UFW configured"
    fi
    
    confirm "Install Fail2ban?" && { apt install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban && success "Fail2ban installed"; }
    
    if confirm "Setup ${SWAP_SIZE}GB swap?"; then
        fallocate -l "${SWAP_SIZE}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab && success "Swap created"
    fi
    
    confirm "Install utilities (plocate, rclone, pv, rsync)?" && { apt install -y plocate rclone pv rsync && success "Utilities installed"; }
    
    success "System utilities configuration completed"
    read -p "Press Enter to continue..."
}

# Website removal
# Website removal with proper MySQL authentication and testing
remove_websites_and_databases() {
    # Get MySQL credentials first
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    
    # Test MySQL connection
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL not accessible"
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
    
    # Discover websites with better detection
    local sites=()
    local site_types=()
    
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                
                if [ -f "$dir/wp-config.php" ]; then
                    sites+=("$domain")
                    site_types+=("WordPress")
                else
                    # Check for subdirectory WordPress installations
                    has_wp_subdir=false
                    for subdir in "$dir"*/; do
                        if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                            subdir_name=$(basename "$subdir")
                            sites+=("$domain/$subdir_name")
                            site_types+=("WordPress-SubDir")
                            has_wp_subdir=true
                        fi
                    done
                    
                    # If no WordPress subdirs, it's a regular site
                    if [ "$has_wp_subdir" = false ]; then
                        sites+=("$domain")
                        site_types+=("Static")
                    fi
                fi
            fi
        done
    fi
    
    [ ${#sites[@]} -eq 0 ] && { warn "No websites found in /var/www"; read -p "Press Enter..."; return; }
    
    echo -e "${RED}Website Removal Tool${NC}"
    echo -e "${YELLOW}Available websites:${NC}"
    echo
    for i in "${!sites[@]}"; do
        echo -e "  $((i+1))) ${GREEN}${sites[i]}${NC} (${site_types[i]})"
    done
    echo
    echo -e "  $((${#sites[@]}+1))) ${RED}Remove ALL websites${NC}"
    echo -e "  $((${#sites[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#sites[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#sites[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL websites and databases!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; read -p "Press Enter..."; return; }
        
        for i in "${!sites[@]}"; do
            remove_single_site "${sites[i]}" "${site_types[i]}"
        done
        success "All websites removed"
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sites[@]} ]; then
            warn "Invalid selection"
            read -p "Press Enter..."
            return
        fi
        
        local selected_site="${sites[$((choice-1))]}"
        local selected_type="${site_types[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Website: ${GREEN}$selected_site${NC}"
        echo -e "  Type: $selected_type"
        if [[ "$selected_type" == *"WordPress"* ]]; then
            echo -e "  Database and user will be removed"
        fi
        echo -e "  Apache configuration will be removed"
        echo -e "  SSL certificates will be removed"
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; read -p "Press Enter..."; return; }
        
        remove_single_site "$selected_site" "$selected_type"
    fi
    
    # Reload Apache configuration
    info "Reloading Apache configuration..."
    if apache2ctl configtest 2>/dev/null; then
        systemctl reload apache2 && success "Apache reloaded successfully"
    else
        warn "Apache configuration has issues, attempting restart..."
        systemctl restart apache2 && success "Apache restarted successfully"
    fi
    
    read -p "Press Enter to continue..."
}

# Remove single website function
remove_single_site() {
    local site="$1"
    local site_type="$2"
    
    info "Removing $site..."
    
    # Handle subdirectory installations
    if [[ "$site" == *"/"* ]]; then
        local main_domain=$(echo "$site" | cut -d'/' -f1)
        local subdir=$(echo "$site" | cut -d'/' -f2)
        local site_path="/var/www/$main_domain/$subdir"
        local domain_for_apache="$main_domain"
    else
        local site_path="/var/www/$site"
        local domain_for_apache="$site"
    fi
    
    # Remove Apache configurations
    info "Removing Apache configurations for $domain_for_apache..."
    a2dissite "$domain_for_apache.conf" 2>/dev/null || true
    a2dissite "$domain_for_apache-le-ssl.conf" 2>/dev/null || true
    a2dissite "$domain_for_apache-ssl.conf" 2>/dev/null || true
    rm -f "/etc/apache2/sites-available/$domain_for_apache.conf"
    rm -f "/etc/apache2/sites-available/$domain_for_apache-le-ssl.conf"
    rm -f "/etc/apache2/sites-available/$domain_for_apache-ssl.conf"
    
    # Remove SSL certificates
    info "Removing SSL certificates for $domain_for_apache..."
    certbot delete --cert-name "$domain_for_apache" --non-interactive 2>/dev/null || true
    
    # Remove database if WordPress
    if [[ "$site_type" == *"WordPress"* ]] && [ -f "$site_path/wp-config.php" ]; then
        info "Removing WordPress database..."
        local db_name=$(grep "DB_NAME" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        local db_user=$(grep "DB_USER" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        
        if [ -n "$db_name" ]; then
            info "Dropping database: $db_name"
            if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
                success "Database $db_name dropped"
            else
                warn "Failed to drop database $db_name"
            fi
        fi
        
        if [ -n "$db_user" ]; then
            info "Dropping user: $db_user"
            if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
                success "User $db_user dropped"
            else
                warn "Failed to drop user $db_user"
            fi
        fi
        
        mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi
    
    # Remove website files
    info "Removing website files from $site_path..."
    if rm -rf "$site_path"; then
        success "Website files removed"
    else
        warn "Failed to remove some website files"
    fi
    
    if verify_website_removed "$domain_for_apache"; then
        success "$site removed successfully"
    else
        warn "Failed to remove $site completely"
    fi
}

# Remove orphaned/redundant databases
remove_orphaned_databases() {
    echo -e "${YELLOW}Scanning for orphaned databases...${NC}"
    
    # Get MySQL credentials
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    
    # Test MySQL connection
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL not accessible"
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
    
    # Get all databases (excluding system databases)
    local all_dbs=($(mysql $MYSQL_AUTH -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys|phpmyadmin)$"))
    
    # Get all existing websites
    local existing_sites=()
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                existing_sites+=("$domain")
                
                # Check for subdirectory WordPress installations
                for subdir in "$dir"*/; do
                    if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                        subdir_name=$(basename "$subdir")
                        existing_sites+=("$domain/$subdir_name")
                    fi
                done
            fi
        done
    fi
    
    # Find orphaned databases
    local orphaned_dbs=()
    local orphaned_users=()
    
    for db in "${all_dbs[@]}"; do
        local is_orphaned=true
        
        # Check if database belongs to any existing website
        for site in "${existing_sites[@]}"; do
            # Convert site name to expected database name format
            local expected_db=$(echo "$site" | sed 's/\./_/g' | sed 's/-/_/g' | sed 's/\//_/g')
            
            if [[ "$db" == "$expected_db" ]]; then
                is_orphaned=false
                break
            fi
        done
        
        # Also check if database is referenced in any wp-config.php"
        if [ "$is_orphaned" = true ]; then
            for dir in /var/www/*/; do
                if [ -f "$dir/wp-config.php" ]; then
                    local config_db=$(grep "DB_NAME" "$dir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                    if [[ "$db" == "$config_db" ]]; then
                        is_orphaned=false
                        break
                    fi
                fi
                
                # Check subdirectories
                for subdir in "$dir"*/; do
                    if [ -f "$subdir/wp-config.php" ]; then
                        local config_db=$(grep "DB_NAME" "$subdir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                        if [[ "$db" == "$config_db" ]]; then
                            is_orphaned=false
                            break 2
                        fi
                    fi
                done
            done
        fi
        
        if [ "$is_orphaned" = true ]; then
            orphaned_dbs+=("$db")
            # Find associated user (common pattern: dbname_user)
            # Find associated user by checking common naming patterns
            local user_found=""
            local potential_user1="${db}_user"
            local base_name=$(echo "$db" | sed 's/_db$//')
            local potential_user2="${base_name}_user"

            if mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user1';" 2>/dev/null | grep -q "^${potential_user1}$"; then
                user_found="$potential_user1"
            elif [ "$base_name" != "$db" ] && mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user2';" 2>/dev/null | grep -q "^${potential_user2}$"; then
                user_found="$potential_user2"
            fi
            orphaned_users+=("$user_found")
        fi
    done
    
    if [ ${#orphaned_dbs[@]} -eq 0 ]; then
        success "No orphaned databases found"
        return
    fi
    
    echo -e "${RED}Found ${#orphaned_dbs[@]} orphaned database(s):${NC}"
    echo
    for i in "${!orphaned_dbs[@]}"; do
        echo -e "  $((i+1))) ${YELLOW}${orphaned_dbs[i]}${NC}"
        if [ -n "${orphaned_users[i]}" ]; then
            echo -e "      User: ${orphaned_users[i]}"
        fi
        
        # Show database size
        local db_size=$(mysql $MYSQL_AUTH -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.tables WHERE table_schema = '${orphaned_dbs[i]}';" 2>/dev/null | tail -n 1)
        if [ -n "$db_size" ] && [ "$db_size" != "NULL" ]; then
            echo -e "      Size: ${db_size} MB"
        fi
    done
    
    echo
    echo -e "  $((${#orphaned_dbs[@]}+1))) ${RED}Remove ALL orphaned databases${NC}"
    echo -e "  $((${#orphaned_dbs[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#orphaned_dbs[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#orphaned_dbs[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL orphaned databases and users!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; return; }
        
        for i in "${!orphaned_dbs[@]}"; do
            remove_single_database "${orphaned_dbs[i]}" "${orphaned_users[i]}"
        done
        success "All orphaned databases removed"
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#orphaned_dbs[@]} ]; then
            warn "Invalid selection"
            return
        fi
        
        local selected_db="${orphaned_dbs[$((choice-1))]}"
        local selected_user="${orphaned_users[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Database: ${YELLOW}$selected_db${NC}"
        if [ -n "$selected_user" ]; then
            echo -e "  User: ${YELLOW}$selected_user${NC}"
        fi
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; return; }
        
        remove_single_database "$selected_db" "$selected_user"
    fi
}

# Remove single database and user
remove_single_database() {
    local db_name="$1"
    local db_user="$2"
    
    info "Removing database: $db_name"
    
    if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
        success "Database $db_name dropped"
    else
        warn "Failed to drop database $db_name"
    fi

    if [ -n "$db_user" ]; then
        info "Removing user: $db_user"
        if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
            success "User $db_user dropped"
        else
            warn "Failed to drop user $db_user"
        fi
    fi
    
    mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    success "Database cleanup completed"
}

# Set secure WordPress file and directory permissions
set_wordpress_permissions() {
    local wp_path="$1"
    if [ -z "$wp_path" ] || [ ! -d "$wp_path" ]; then
        warn "Cannot set permissions: WordPress path '$wp_path' is invalid."
        return 1
    fi

    info "Setting ownership to www-data:www-data..."
    chown -R www-data:www-data "$wp_path"

    info "Setting directory permissions to 755..."
    find "$wp_path" -type d -print0 | xargs -0 chmod 755
    
    success "Directory permissions have been set. For comprehensive and secure file permissions, please use fast_permissions.sh."
}

# Verify Apache installation
verify_apache_installed() {
    if systemctl is-active --quiet apache2; then
        return 0 # Apache is installed and running
    else
        return 1 # Apache is not installed or not running
    fi
}

# Verify MySQL installation
verify_mysql_installed() {
    if systemctl is-active --quiet mysql; then
        return 0 # MySQL is installed and running
    else
        return 1 # MySQL is not installed or not running
    fi
}

# Verify PHP installation
verify_php_installed() {
    if command -v php &>/dev/null; then
        return 0 # PHP is installed
    else
        return 1 # PHP is not installed
    fi
}

# Verify WordPress installation
verify_wordpress_installed() {
    local site_dir="$1"
    if [ -d "$site_dir" ] && [ -f "$site_dir/wp-config.php" ]; then
        return 0 # WordPress is installed
    else
        return 1 # WordPress is not installed
    fi
}

# Verify SSL installation
verify_ssl_installed() {
    local domain="$1"
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        return 0 # SSL is installed
    else
        return 1 # SSL is not installed
    fi
}

# Verify website removal
verify_website_removed() {
    local domain="$1"
    local site_path="/var/www/$domain"
    local apache_config="/etc/apache2/sites-available/$domain.conf"
    local apache_ssl_config="/etc/apache2/sites-available/$domain-le-ssl.conf"

    if [ -d "$site_path" ] || [ -f "$apache_config" ] || [ -f "$apache_ssl_config" ]; then
        return 1 # Website not removed
    else
        return 0 # Website removed
    fi
}

# Check for maintenance file
check_maintenance_file() {
    local site_path="$1"
    if [ -f "$site_path/.maintenance" ]; then
        warn "Maintenance file detected at '$site_path/.maintenance'. This could be the reason for the maintenance page."
    else
        info "No .maintenance file found at '$site_path/.maintenance'."
    fi
}

# Fix Apache configurations
fix_all_apache_configs() {
    info "Scanning Apache configurations..."
    local fixed=0
    
    for config in /etc/apache2/sites-available/*.conf; do
        [ -f "$config" ] || continue
        domain=$(basename "$config" .conf)
        
        if grep -q "ServerAdmin.*Error:" "$config" || grep -q "ServerAdmin.*root@.*#" "$config"; then
            warn "Fixing broken config: $domain"
            cp "$config" "${config}.broken.$(date +%Y%m%d_%H%M%S)"
            
            cat > "$config" << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/$domain
    <Directory /var/www/$domain>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$domain.log
    CustomLog \${APACHE_LOG_DIR}/access_$domain.log combined
</VirtualHost>
EOF
            ((fixed++))
        fi
    done
    
    [ $fixed -gt 0 ] && { success "Fixed $fixed configurations"; systemctl reload apache2; } || info "No broken configurations found"
    apache2ctl configtest && success "Apache configuration is valid" || warn "Apache configuration has issues"
    read -p "Press Enter to continue..."
}

# Troubleshooting guide
show_troubleshooting_guide() {
    clear
    echo -e "${YELLOW}Troubleshooting Guide${NC}"
    cat << 'EOF'

1. WordPress admin fails to load:
   wp plugin deactivate --all --allow-root --path=/var/www/your_site
   rm -rf /var/www/your_site/wp-content/plugins/broken_plugin

2. Check service status:
   systemctl status apache2 mysql redis-server

3. Check system resources:
   free -h && df -h

4. Check logs:
   tail -n 20 /var/log/apache2/error.log
   tail -n 20 /var/www/your_site/wp-content/debug.log

5. Enable WordPress debug (add to wp-config.php):
   define('WP_DEBUG', true);
   define('WP_DEBUG_LOG', true);

6. MySQL binary logs cleanup:
   mysql -u root -p -e "RESET MASTER;"

7. Redis connection errors:
   rm /var/www/your_site/wp-content/object-cache.php
EOF
    read -p "Press Enter to continue..."
}

# MySQL commands guide
mysql_commands_guide() {
    clear
    echo -e "${YELLOW}MySQL Commands Guide${NC}"
    cat << 'EOF'

Access MySQL: sudo mysql -u root -p
Check databases: SHOW DATABASES;
Check users: SELECT User FROM mysql.user;
Login to database: mysql -u username -p database_name

Check WordPress URLs:
SELECT option_name, option_value FROM wp_options 
WHERE option_name IN ('siteurl', 'home');

Check database size:
SELECT table_schema AS "Database",
ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size (MB)"
FROM information_schema.tables
WHERE table_schema = "database_name";

Exit MySQL: EXIT;
EOF
    read -p "Press Enter to continue..."
}

# System status check
system_status_check() {
    clear
    echo -e "${YELLOW}System Status Check${NC}"
    echo
    echo -e "${CYAN}=== System Information ===${NC}"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo "Uptime: $(uptime -p 2>/dev/null || echo "Unknown")"
    echo
    echo -e "${CYAN}=== Resource Usage ===${NC}"
    echo "Memory:"; free -h
    echo "Disk:"; df -h | grep -E '^/dev/'
    echo
    echo -e "${CYAN}=== Service Status ===${NC}"
    for service in apache2 mysql redis-server; do
        systemctl is-active --quiet "$service" && echo -e "$service: ${GREEN}Running${NC}" || echo -e "$service: ${RED}Stopped${NC}"
    done
    echo
    echo -e "${CYAN}=== WordPress Sites ===${NC}"
    [ -d "/var/www" ] && for site in /var/www/*; do
        [ -d "$site" ] && [ -f "$site/wp-config.php" ] && echo -e "WordPress: ${GREEN}$(basename "$site")${NC}"
    done
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    check_system
    load_config

    if [ -n "$1" ]; then
        case "$1" in
            install_apache_ssl_only) install_apache_ssl_only ;;
            remove_websites_and_databases) remove_websites_and_databases ;;
            remove_orphaned_databases) remove_orphaned_databases ;;
            *) echo "Invalid function: $1" ;;
        esac
        exit 0
    fi
    
    while true; do
        show_menu
        read -p "Select option (1-19): " choice
        
        case $choice in
            1) install_lamp_wordpress ;;
            2) install_apache_ssl_only ;;
            3) install_phpmyadmin ;;
            4) backup_wordpress ;;
            5) restore_wordpress ;;
            6) backup_postgresql ;;
            7) restore_postgresql ;;
            8) transfer_backups ;;
            9) adjust_php_config ;;
            10) configure_redis ;;
            11) ssh_security_management ;;
            12) system_utilities ;;
            13) remove_websites_and_databases ;;
            14) remove_orphaned_databases ;;
            15) fix_all_apache_configs ;;
            16) show_troubleshooting_guide ;;
            17) mysql_commands_guide ;;
            18) system_status_check ;;
            19) echo -e "${GREEN}Thank you for using WordPress Master!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"