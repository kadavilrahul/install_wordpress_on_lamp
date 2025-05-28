#!/bin/bash

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

# Prompt for input variables
read -p "Enter main domain name (e.g., exanple.com): " MAIN_DOMAIN
read -p "Enter subdomain name (e.g., blog): " SUBDOMAIN
read -p "Enter admin email: " ADMIN_EMAIL
read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD
read -p "Enter Redis maximum memory in GB (Default is 1GB, it should be nearly equal to your database size): " REDIS_MAX_MEMORY
[[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
echo  # New line after password input

# Construct full domain
FULL_DOMAIN="$SUBDOMAIN.$MAIN_DOMAIN"

# Update system packages
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y apache2 mysql-server php php-fpm libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc unzip wget certbot python3-certbot-apache

# Prepare domain-based database credentials
DB_NAME=$(echo "$FULL_DOMAIN" | tr '.' '_')_db
DB_USER=$(echo "$FULL_DOMAIN" | tr '.' '_')_user
DB_PASSWORD="$(echo "$FULL_DOMAIN" | tr '.' '_')_2@"
WP_DIR="/var/www/$FULL_DOMAIN"

# Create directory for the WordPress site
mkdir -p "$WP_DIR"

# Create MySQL database and user
mysql -u root -p"$DB_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';
GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Download and extract WordPress
wget -c http://wordpress.org/latest.tar.gz -O latest.tar.gz
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
VHOST_FILE="/etc/apache2/sites-available/$FULL_DOMAIN.conf"
cat > "$VHOST_FILE" <<VHOST
<VirtualHost *:80>
    ServerAdmin $ADMIN_EMAIL
    ServerName $FULL_DOMAIN
    DocumentRoot $WP_DIR
    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$FULL_DOMAIN.log
    CustomLog \${APACHE_LOG_DIR}/access_$FULL_DOMAIN.log combined
</VirtualHost>
VHOST

# Enable the site and reload Apache
a2ensite "$FULL_DOMAIN.conf"
systemctl reload apache2

# Stop Apache temporarily for SSL setup
systemctl stop apache2

# Install SSL for subdomain
certbot certonly --standalone -d "$FULL_DOMAIN" -m "$ADMIN_EMAIL" --agree-tos --no-eff-email

# Create SSL Virtual Host configuration
SSL_VHOST_FILE="/etc/apache2/sites-available/$FULL_DOMAIN-ssl.conf"
cat > "$SSL_VHOST_FILE" <<VHOST
<VirtualHost *:443>
    ServerAdmin $ADMIN_EMAIL
    ServerName $FULL_DOMAIN
    DocumentRoot $WP_DIR

    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error_$FULL_DOMAIN.log
    CustomLog \${APACHE_LOG_DIR}/access_$FULL_DOMAIN.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$FULL_DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$FULL_DOMAIN/privkey.pem
</VirtualHost>

# HTTP to HTTPS redirect
<VirtualHost *:80>
    ServerName $FULL_DOMAIN
    Redirect permanent / https://$FULL_DOMAIN/
</VirtualHost>
VHOST

# Enable SSL modules and configuration
a2enmod ssl
a2enmod headers
a2enmod rewrite
a2ensite "$FULL_DOMAIN-ssl.conf"

# Restart Apache
systemctl start apache2

# Install WP-CLI
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

# Configure OPcache
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_INI_FILE="/etc/php/$PHP_VERSION/apache2/php.ini"

sed -i \
    -e '/;\s*opcache.enable=/s/^;//' \
    -e '/opcache.enable=/s/=.*/=1/' \
    -e '/;\s*opcache.memory_consumption=/s/^;//' \
    -e '/opcache.memory_consumption=/s/=.*/=512/' \
    -e '/;\s*opcache.interned_strings_buffer=/s/^;//' \
    -e '/opcache.interned_strings_buffer=/s/=.*/=8/' \
    -e '/;\s*opcache.max_accelerated_files=/s/^;//' \
    -e '/opcache.max_accelerated_files=/s/=.*/=10000/' \
    -e '/;\s*opcache.revalidate_freq=/s/^;//' \
    -e '/opcache.revalidate_freq=/s/=.*/=60/' \
    -e '/;\s*opcache.save_comments=/s/^;//' \
    -e '/opcache.save_comments=/s/=.*/=1/' "$PHP_INI_FILE"

# Configure MySQL log purging
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
echo -e "[mysqld]\nexpire_logs_days = 1" | sudo tee -a $MYSQL_CONF > /dev/null

# Restart to apply changes
systemctl restart mysql
systemctl restart apache2
systemctl restart php8.3-fpm

# Before the final echo statements, add this code:

# Create a summary file with installation details
cat > "/root/installation_summary_$FULL_DOMAIN.txt" <<SUMMARY
WordPress Subdomain Installation Summary
=======================================
Date: $(date)

Domain Information:
-----------------
Main Domain: $MAIN_DOMAIN
Subdomain: $SUBDOMAIN
Full Domain: $FULL_DOMAIN
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
Certificate Path: /etc/letsencrypt/live/$FULL_DOMAIN/
Auto-renewal: Twice daily check (0:00 and 12:00)

Please save this information securely!

SSL Certificate:
--------------
Certificate Path: /etc/letsencrypt/live/$FULL_DOMAIN/
Auto-renewal: Twice daily check (0:00 and 12:00)

Additional Services:
-----------------
Redis: Enabled (${REDIS_MAX_MEMORY}GB max memory)
OPcache: Enabled
SUMMARY

# Set proper permissions for the summary file
chmod 600 /root/installation_summary_$FULL_DOMAIN.txt

echo "============================================="
echo "Subdomain WordPress Installation Complete!"
echo "============================================="
echo "A complete summary has been saved to: /root/installation_summary_$FULL_DOMAIN.txt"
echo ""
echo "Quick Access Information:"
echo "------------------------"
echo "WordPress URL: https://$FULL_DOMAIN"
echo ""
echo "Database Information:"
echo "-------------------"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo "Database Password: $DB_PASSWORD"
echo "Admin Email: $ADMIN_EMAIL"
echo ""
echo "IMPORTANT: Please save the installation summary file securely!"
echo "============================================="
