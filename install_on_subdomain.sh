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
read -p "Enter main domain name (e.g., silkroademart.com): " MAIN_DOMAIN
read -p "Enter subdomain name (e.g., wholesale or products): " SUBDOMAIN
read -p "Enter admin email: " ADMIN_EMAIL
read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD
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

echo "Subdomain WordPress and SSL installation complete!"
echo "Subdomain: $FULL_DOMAIN"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo "Database Password: $DB_PASSWORD"
echo "Admin Email: $ADMIN_EMAIL"
echo "Please save these credentials securely!"
