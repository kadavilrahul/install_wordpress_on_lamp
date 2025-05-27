#!/bin/bash

# Get user inputs
read -p "Enter subdomain (e.g., new.example.com): " SUBDOMAIN
read -p "Enter main domain (e.g., example.com): " MAIN_DOMAIN
read -p "Enter web root path [default: /var/www/$SUBDOMAIN]: " WEB_ROOT_INPUT
read -p "Enter Apache configuration path [default: /etc/apache2/sites-available/$SUBDOMAIN.conf]: " APACHE_CONF_INPUT

# Set default values if inputs are empty
WEB_ROOT=${WEB_ROOT_INPUT:-"/var/www/$SUBDOMAIN"}
APACHE_CONF=${APACHE_CONF_INPUT:-"/etc/apache2/sites-available/$SUBDOMAIN.conf"}

# Display entered values and ask for confirmation
echo -e "\nPlease confirm the following settings:"
echo "Subdomain: $SUBDOMAIN"
echo "Main Domain: $MAIN_DOMAIN"
echo "Web Root Path: $WEB_ROOT"
echo "Apache Config Path: $APACHE_CONF"
read -p "Are these settings correct? (y/n): " CONFIRM

if [ "${CONFIRM,,}" != "y" ]; then
    echo "Setup cancelled by user"
    exit 1
fi

# Update and install necessary packages
sudo apt update
sudo apt install -y apache2 certbot python3-certbot-apache

# Create the web root directory
if [ ! -d "$WEB_ROOT" ]; then
    sudo mkdir -p "$WEB_ROOT"
fi

# Set permissions
sudo chown -R $USER:$USER "$WEB_ROOT"
sudo chmod -R 755 "$WEB_ROOT"

# Create a sample HTML file
cat <<EOT > "$WEB_ROOT/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $SUBDOMAIN</title>
</head>
<body>
    <h1>Welcome to $SUBDOMAIN</h1>
    <p>This is a sample HTML website hosted on Apache.</p>
</body>
</html>
EOT

# Create an Apache virtual host configuration file
cat <<EOT | sudo tee "$APACHE_CONF"
<VirtualHost *:80>
    ServerName $SUBDOMAIN
    DocumentRoot $WEB_ROOT

    <Directory $WEB_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUBDOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUBDOMAIN-access.log combined
</VirtualHost>
EOT

# Enable the site and reload Apache
sudo a2ensite "$SUBDOMAIN.conf"
sudo systemctl reload apache2

# Obtain an SSL certificate for the subdomain using Certbot
sudo certbot --apache -d "$SUBDOMAIN" --agree-tos --email admin@$MAIN_DOMAIN --non-interactive

# Reload Apache to apply changes
sudo systemctl reload apache2

# Success message
echo "Website for $SUBDOMAIN has been created and secured with SSL!"
echo "Web root directory: $WEB_ROOT"
