#!/bin/bash

#=============================================================================
# Professional WordPress Installation & Management Script
#=============================================================================

#--- CONFIGURATION ---
LOG_FILE="/var/log/wordpress_pro_$(date +%Y%m%d_%H%M%S).log"

#--- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#--- UTILITY FUNCTIONS ---
log() { echo -e "$1" | tee -a "$LOG_FILE"; }
info() { log "${BLUE}INFO:${NC} $1"; }
error() { log "${RED}ERROR:${NC} $1"; exit 1; }
confirm() { read -p "${YELLOW}CONFIRM:${NC} $1 (y/n): " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]]; }

#--- CORE INSTALLATION ---
run_installation() {
    info "Starting WordPress installation..."
    read -p "Enter domain name: " DOMAIN
    read -p "Enter admin email: " ADMIN_EMAIL
    read -sp "Enter new MySQL root password: " DB_ROOT_PASSWORD; echo

    [[ -z "$DOMAIN" || -z "$ADMIN_EMAIL" || -z "$DB_ROOT_PASSWORD" ]] && error "Domain, email, and password are required."

    info "Installing packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql php-redis redis-server certbot python3-certbot-apache curl wget unzip >> "$LOG_FILE" 2>&1 || error "Package installation failed."
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

    info "Securing MySQL..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD'; FLUSH PRIVILEGES;" || error "MySQL password setup failed."

    info "Setting up WordPress..."
    SITE_DIR="/var/www/$DOMAIN"
    DB_NAME=$(echo "$DOMAIN" | sed 's/\./_/g')
    DB_USER="${DB_NAME}_user"
    DB_PASSWORD=$(openssl rand -base64 12)
    mkdir -p "$SITE_DIR"
    wget -qO- https://wordpress.org/latest.tar.gz | tar -C "$SITE_DIR" --strip-components=1 -xzf -

    info "Configuring WordPress database..."
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" || error "Database creation failed."
    wp config create --path="$SITE_DIR" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --extra-php <<PHP
define('WP_REDIS_HOST', '127.0.0.1');
define('FS_METHOD', 'direct');
PHP

    info "Configuring Apache and SSL..."
    cat > "/etc/apache2/sites-available/$DOMAIN.conf" << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $SITE_DIR
    <Directory $SITE_DIR>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF
    a2ensite "$DOMAIN.conf" >> "$LOG_FILE" 2>&1
    a2enmod rewrite >> "$LOG_FILE" 2>&1
    systemctl restart apache2
    certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect >> "$LOG_FILE" 2>&1

    info "Finalizing permissions..."
    chown -R www-data:www-data "$SITE_DIR"
    chmod -R 755 "$SITE_DIR"

    log "${GREEN}Installation Complete!${NC}"
    log "Domain: https://$DOMAIN"
    log "MySQL Root Password: $DB_ROOT_PASSWORD"
    log "DB Name/User/Pass: $DB_NAME / $DB_USER / $DB_PASSWORD"
}

#--- MANAGEMENT FUNCTIONS ---
run_backup() {
    info "Starting backup process..."
    BACKUP_DIR="/website_backups"
    mkdir -p "$BACKUP_DIR"
    for site_dir in /var/www/*/; do
        if [ -f "${site_dir}wp-config.php" ]; then
            SITE_NAME=$(basename "$site_dir")
            info "Backing up $SITE_NAME..."
            wp db export "$BACKUP_DIR/${SITE_NAME}_db.sql" --path="$site_dir" --allow-root
            tar -czf "$BACKUP_DIR/${SITE_NAME}_backup_$(date +%F).tar.gz" -C "/var/www" "$SITE_NAME"
        fi
    done
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
    log "${GREEN}Backup complete.${NC}"
}

run_restore() {
    info "Starting restore process..."
    read -p "Enter path to backup file: " BACKUP_FILE
    read -p "Enter domain to restore to: " DOMAIN
    [[ -z "$BACKUP_FILE" || -z "$DOMAIN" ]] && error "Backup file and domain are required."

    SITE_DIR="/var/www/$DOMAIN"
    mkdir -p "$SITE_DIR"
    tar -xzf "$BACKUP_FILE" -C "$SITE_DIR" --strip-components=1
    wp db import "$SITE_DIR/"*.sql --path="$SITE_DIR" --allow-root
    log "${GREEN}Restore complete.${NC}"
}

run_remove() {
    info "Starting removal process..."
    read -p "Enter domain to remove: " DOMAIN
    [[ -z "$DOMAIN" ]] && error "Domain is required."

    if confirm "This will permanently delete all files, database, and configs for $DOMAIN."; then
        DB_NAME=$(wp config get dbname --path="/var/www/$DOMAIN" --allow-root)
        DB_USER=$(wp config get dbuser --path="/var/www/$DOMAIN" --allow-root)
        mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $DB_NAME; DROP USER IF EXISTS '$DB_USER'@'localhost';"
        a2dissite "$DOMAIN.conf" >> "$LOG_FILE" 2>&1
        certbot delete --cert-name "$DOMAIN" --non-interactive
        rm -rf "/var/www/$DOMAIN" "/etc/apache2/sites-available/$DOMAIN.conf"
        systemctl restart apache2
        log "${GREEN}Removal of $DOMAIN complete.${NC}"
    fi
}

#--- SCRIPT ROUTER ---
case "$1" in
    backup) run_backup ;;
    restore) run_restore ;;
    remove) run_remove ;;
    *) run_installation ;;
esac
