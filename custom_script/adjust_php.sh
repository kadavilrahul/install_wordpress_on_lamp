#!/bin/bash

# Function to modify php.ini
modify_php_ini() {
    local ini_file="$1"
    echo "Modifying PHP INI file: $ini_file"

    if [ -f "$ini_file" ]; then
        sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$ini_file"
        sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$ini_file"
        sed -i "s/^memory_limit = .*/memory_limit = 512M/" "$ini_file"  # Increased to 512M
        sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$ini_file"
        sed -i "s/^max_input_time = .*/max_input_time = 300/" "$ini_file"
    else
        echo "Error: PHP INI file not found: $ini_file"
    fi
}

# Get PHP version
PHP_VERSION=$(php -v | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)

# Define possible php.ini paths
CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
APACHE_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
FPM_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

# Modify php.ini files
modify_php_ini "$CLI_INI"
modify_php_ini "$APACHE_INI"
modify_php_ini "$FPM_INI"

# Restart PHP-FPM if it's running
if systemctl is-active php${PHP_VERSION}-fpm > /dev/null 2>&1; then
    echo "Restarting PHP-FPM..."
    systemctl restart php${PHP_VERSION}-fpm
fi

echo "PHP configuration completed!"