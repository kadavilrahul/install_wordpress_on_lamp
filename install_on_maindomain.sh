#!/bin/bash

# Function to display error messages and exit
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Prompt for input variables
read -p "Enter main domain name (e.g., example.com): " MAIN_DOMAIN
read -p "Enter admin email: " ADMIN_EMAIL
read -sp "Enter MySQL root password (new password): " DB_ROOT_PASSWORD

read -p "Enter Redis maximum memory in GB (e.g., 6): " REDIS_MAX_MEMORY
echo  # New line after password input

# Update system packages
echo "Updating system packages..."
apt update && apt upgrade -y || error_exit "Failed to update system packages"

# 1. Install LAMP Stack with PHP-FPM
echo "Installing LAMP Stack..."
apt-get install -y apache2 mysql-server php php-fpm libapache2-mod-php php-mysql php-cli php-common php-mbstring php-gd php-intl php-xml php-curl php-zip certbot python3-certbot-apache || { echo "Failed to install LAMP stack"; exit 1; }

# Enable PHP-FPM in Apache
echo "Configuring Apache to use PHP-FPM..."
a2enmod proxy_fcgi setenvif
a2enconf php8.3-fpm  # Adjust version if needed
systemctl restart apache2

# Start and enable PHP-FPM
echo "Starting PHP-FPM..."
systemctl enable --now php8.3-fpm

# Configure MySQL bind address
sed -i 's/^bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
sed -i 's/^mysqlx-bind-address.*=.*/mysqlx-bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Configure Apache
sed -i 's/index.html/index.php/' /etc/apache2/mods-enabled/dir.conf
a2enmod rewrite
systemctl start mysql

# Secure MySQL installation
mysql -u root -p"$DB_ROOT_PASSWORD" <<MYSQL_SCRIPT
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 2. WordPress Setup
echo "Setting up WordPress..."
DB_NAME=$(echo "$MAIN_DOMAIN" | tr '.' '_')_db
DB_USER=$(echo "$MAIN_DOMAIN" | tr '.' '_')_user
DB_PASSWORD="$(echo "$MAIN_DOMAIN" | tr '.' '_')_2@"
WP_DIR="/var/www/$MAIN_DOMAIN"

mkdir -p "$WP_DIR" || error_exit "Failed to create WordPress directory"

# Create WordPress database and user
mysql -u root -p"$DB_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';
GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Download and setup WordPress
wget -c http://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"
tar -xzvf latest.tar.gz
mv wordpress/* "$WP_DIR"
rm -rf wordpress latest.tar.gz

# Configure wp-config.php
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"
sed -i "s/database_name_here/$DB_NAME/" "$WP_DIR/wp-config.php"
sed -i "s/username_here/$DB_USER/" "$WP_DIR/wp-config.php"
sed -i "s/password_here/$DB_PASSWORD/" "$WP_DIR/wp-config.php"

# Set permissions
chown -R www-data:www-data "$WP_DIR"
chmod -R 755 "$WP_DIR"

# Create Apache Virtual Host configuration
VHOST_FILE="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
cat > "$VHOST_FILE" <<VHOST
<VirtualHost *:80>
    ServerAdmin $ADMIN_EMAIL
    ServerName $MAIN_DOMAIN
    ServerAlias www.$MAIN_DOMAIN
    DocumentRoot $WP_DIR
    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$MAIN_DOMAIN.log
    CustomLog \${APACHE_LOG_DIR}/access_$MAIN_DOMAIN.log combined
</VirtualHost>
VHOST

# Enable the site
a2ensite "$MAIN_DOMAIN.conf"
systemctl reload apache2

# Stop Apache temporarily for SSL setup
systemctl stop apache2

# Install SSL certificate
certbot certonly --standalone -d "$MAIN_DOMAIN" -d "www.$MAIN_DOMAIN" -m "$ADMIN_EMAIL" --agree-tos --no-eff-email || error_exit "SSL certificate installation failed"

# Create SSL Virtual Host configuration
SSL_VHOST_FILE="/etc/apache2/sites-available/$MAIN_DOMAIN-ssl.conf"
cat > "$SSL_VHOST_FILE" <<VHOST
<VirtualHost *:443>
    ServerAdmin $ADMIN_EMAIL
    ServerName $MAIN_DOMAIN
    ServerAlias www.$MAIN_DOMAIN
    DocumentRoot $WP_DIR

    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error_$MAIN_DOMAIN.log
    CustomLog \${APACHE_LOG_DIR}/access_$MAIN_DOMAIN.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem
</VirtualHost>

# HTTP to HTTPS redirect
<VirtualHost *:80>
    ServerName $MAIN_DOMAIN
    ServerAlias www.$MAIN_DOMAIN
    Redirect permanent / https://$MAIN_DOMAIN/
</VirtualHost>
VHOST

# Enable SSL modules and configuration
a2enmod ssl
a2enmod headers
a2ensite "$MAIN_DOMAIN-ssl.conf"

# Start Apache
systemctl start apache2

# 3. Install WP-CLI
echo "Installing WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || error_exit "Failed to download WP-CLI"
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Redis
apt install redis-server -y
echo -e "maxmemory ${REDIS_MAX_MEMORY}gb\nmaxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
sysctl -p
systemctl enable redis-server
systemctl restart redis-server

# Create a summary file with installation details
cat > "/root/installation_summary_$MAIN_DOMAIN.txt" <<SUMMARY
WordPress Installation Summary
============================
Date: $(date)

Domain Information:
-----------------
Main Domain: $MAIN_DOMAIN
WordPress Directory: $WP_DIR

Database Information:
-------------------
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
MySQL Root Password: $DB_ROOT_PASSWORD

Important Paths:
--------------
WordPress Root: $WP_DIR

SSL Certificate:
--------------
Certificate Path: /etc/letsencrypt/live/$MAIN_DOMAIN/
Auto-renewal: Twice daily check (0:00 and 12:00)

Additional Services:
-----------------
Redis: Enabled (${REDIS_MAX_MEMORY}GB max memory)
OPcache: Enabled

Please save this information securely!
SUMMARY

# Set proper permissions for the summary file
chmod 600 /root/installation_summary_$MAIN_DOMAIN.txt

echo "============================================="
echo "Installation Complete!"
echo "============================================="
echo "A complete summary has been saved to: /root/installation_summary_$MAIN_DOMAIN.txt"
echo ""
echo "Quick Access Information:"
echo "------------------------"
echo "WordPress URL: https://$MAIN_DOMAIN"
echo "phpMyAdmin URL: https://$MAIN_DOMAIN/phpmyadmin"
echo "PHP Info URL: https://$MAIN_DOMAIN/info.php"
echo ""
echo "Database Information:"
echo "-------------------"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo "Database Password: $DB_PASSWORD"
echo ""
echo "Remote Desktop Access:"
echo "--------------------"
echo "Username: $NEW_USER"
echo "Password: $USER_PASSWORD"
echo ""
echo "IMPORTANT: Please save the installation summary file securely!"
echo "For security reasons, consider removing info.php after testing."
echo "============================================="
