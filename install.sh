#!/bin/bash

# Check, define variables and modify accordingly as needed

# Define variables
DB_NAME="your_domainname_db"
DB_USER="your_domainname_user"
DB_PASSWORD="your_domainname_2@"
DB_ROOT_PASSWORD="root_2@"
WP_DIR="/var/www/html" # Use either /html folder or domain folder like /your_domain.com
DOMAIN="your_domain.com"
EMAIL="example@email.com"

# Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Apache, MySQL, PHP and required PHP extensions
echo "Installing Apache, MySQL, and PHP..."
sudo apt-get install php php-fpm libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip -y
sudo a2enmod proxy_fcgi setenvif
sudo a2enconf php8.3-fpm  # Adjust version if needed


# Start and enable Apache and MySQL
echo "Starting and enabling Apache and MySQL..."
sudo systemctl start apache2
sudo systemctl enable apache2
sudo systemctl start mysql
sudo systemctl enable mysql

# Download and extract WordPress
echo "Downloading WordPress..."
wget -c http://wordpress.org/latest.tar.gz -O latest.tar.gz
echo "Extracting WordPress..."
tar -xzvf latest.tar.gz

# Move WordPress files to the web directory
echo "Moving WordPress files to $WP_DIR..."
sudo mv wordpress/* $WP_DIR

# Set permissions for WordPress directory
echo "Setting permissions for $WP_DIR..."
sudo chown -R www-data:www-data $WP_DIR
sudo chmod -R 755 $WP_DIR

# Create WordPress Database and User
echo "Creating MySQL database and user..."
sudo mysql -u root -p"$DB_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';
GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "Database and user created successfully."

# Configure wp-config.php
echo "Configuring wp-config.php..."
cd $WP_DIR
sudo mv wp-config-sample.php wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/" wp-config.php
sudo sed -i "s/username_here/$DB_USER/" wp-config.php
sudo sed -i "s/password_here/$DB_PASSWORD/" wp-config.php

# Remove default index.html if exists
if [ -f "$WP_DIR/index.html" ]; then
    echo "Removing default index.html..."
    sudo rm -f $WP_DIR/index.html
fi

# Install phpMyAdmin
echo "Installing phpMyAdmin..."
sudo apt install phpmyadmin -y

# Link phpMyAdmin to the web directory
echo "Linking phpMyAdmin to $WP_DIR..."
sudo ln -s /usr/share/phpmyadmin $WP_DIR/phpmyadmin

# Reload Apache to apply changes
echo "Reloading Apache..."
sudo systemctl restart apache2


echo "LAMP stack, WordPress, phpMyAdmin completed successfully!"

