#!/bin/bash

# Minimalistic WordPress Installation Script with Full Features

#--- CONFIGURATION ---
LOG_FILE="/var/log/wordpress_install_$(date +%Y%m%d_%H%M%S).log"

#--- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

#--- UTILITY FUNCTIONS ---
log() { echo "$1" | tee -a "$LOG_FILE"; }
info() { log "${BLUE}INFO:${NC} $1"; }
error() { log "${RED}ERROR:${NC} $1"; exit 1; }

#--- SCRIPT START ---
clear

# Check root
[[ $EUID -ne 0 ]] && error "This script must be run as root."

# Get user input
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter your admin email: " ADMIN_EMAIL
read -sp "Enter a new MySQL root password: " DB_ROOT_PASSWORD
echo

[[ -z "$DOMAIN" || -z "$ADMIN_EMAIL" || -z "$DB_ROOT_PASSWORD" ]] && error "All fields are required."

# 1. Install LAMP & Tools
info "Installing LAMP, Redis, Certbot, and WP-CLI..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >> "$LOG_FILE" 2>&1
apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql php-redis redis-server certbot python3-certbot-apache curl >> "$LOG_FILE" 2>&1 || error "Package installation failed."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# 2. Secure MySQL
info "Securing MySQL and setting root password..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD'; FLUSH PRIVILEGES;" || error "Failed to secure MySQL."

# 3. Setup WordPress
info "Setting up WordPress directory and files..."
SITE_DIR="/var/www/$DOMAIN"
DB_NAME=$(echo "$DOMAIN" | sed 's/\./_/g')
DB_USER="${DB_NAME}_user"
DB_PASSWORD=$(openssl rand -base64 12)

mkdir -p "$SITE_DIR"
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
cp -r wordpress/* "$SITE_DIR/"
rm -rf wordpress latest.tar.gz

# 4. Configure WordPress & Database
info "Creating database and configuring wp-config.php..."
mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" || error "Database setup failed."

cp "$SITE_DIR/wp-config-sample.php" "$SITE_DIR/wp-config.php"
SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "s/database_name_here/$DB_NAME/;s/username_here/$DB_USER/;s/password_here/$DB_PASSWORD/" "$SITE_DIR/wp-config.php"
sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$SITE_DIR/wp-config.php"
sed -i "/define('DB_COLLATE', '');/a $SALTS" "$SITE_DIR/wp-config.php"

# 5. Configure Redis
info "Configuring Redis and linking with WordPress..."
systemctl enable --now redis-server >> "$LOG_FILE" 2>&1
cat >> "$SITE_DIR/wp-config.php" << EOF

define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('FS_METHOD', 'direct');
EOF

# 6. Configure Apache & SSL
info "Configuring Apache virtual host and installing SSL..."
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

certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect >> "$LOG_FILE" 2>&1 || info "Certbot had issues, but setup continues. You may need to run it again."

# 7. Finalize Permissions
info "Setting final permissions..."
chown -R www-data:www-data "$SITE_DIR"
chmod -R 755 "$SITE_DIR"

#--- SUMMARY ---
info "Installation Summary:"
log "---------------------"
log "Domain: https://$DOMAIN"
log "MySQL Root Password: $DB_ROOT_PASSWORD"
log "Database Name: $DB_NAME"
log "Database User: $DB_USER"
log "Database Password: $DB_PASSWORD"
log "${GREEN}Installation Complete!${NC}"
