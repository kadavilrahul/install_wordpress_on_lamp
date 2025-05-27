#!/bin/bash

# Prompt user for main domain
read -p "Enter your main domain (e.g., example.com): " MAIN_DOMAIN

WEB_ROOT="/var/www/$MAIN_DOMAIN"
APACHE_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"

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
    <title>Welcome to $MAIN_DOMAIN</title>
</head>
<body>
    <h1>Welcome to $MAIN_DOMAIN</h1>
    <p>This is a sample HTML website hosted on Apache.</p>
</body>
</html>
EOT

# Create an Apache virtual host configuration file
cat <<EOT | sudo tee "$APACHE_CONF"
<VirtualHost *:80>
    ServerName $MAIN_DOMAIN
    DocumentRoot $WEB_ROOT

    <Directory $WEB_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$MAIN_DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$MAIN_DOMAIN-access.log combined
</VirtualHost>
EOT

# Enable the site and reload Apache
sudo a2ensite "$MAIN_DOMAIN.conf"
sudo systemctl reload apache2

# Obtain an SSL certificate for the main domain using Certbot
sudo certbot --apache -d "$MAIN_DOMAIN" --agree-tos --email admin@$MAIN_DOMAIN --non-interactive

# Reload Apache to apply changes
sudo systemctl reload apache2

# Success message
echo "Website for $MAIN_DOMAIN has been created and secured with SSL!"
echo "Web root directory: $WEB_ROOT"
