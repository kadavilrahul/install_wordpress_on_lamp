#!/bin/bash

# Helper function for error handling
error_exit() {
    echo "$1" >&2
    exit 1
}

# Initial required inputs
echo "Please provide the following basic information:"
read -p "Enter web directory path (e.g., /var/www): " WP_DIR

# Install phpMyAdmin
echo "Installing phpMyAdmin..."
apt install phpmyadmin -y || error_exit "Failed to install phpMyAdmin"

# Create symlink
echo "Creating symlink..."
ln -s /usr/share/phpmyadmin "$WP_DIR/phpmyadmin" || error_exit "Failed to create symlink"

echo "phpMyAdmin installation completed!"
