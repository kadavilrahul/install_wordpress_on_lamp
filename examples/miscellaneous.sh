#!/bin/bash

# Helper function for error handling
error_exit() {
    echo "$1" >&2
    exit 1
}

# Initial required inputs
echo "Please provide the following basic information:"
read -p "Enter swap file size in GB (e.g., 3): " SWAP_SIZE

# 1. Initial System Update
if confirm "Do you want to update the system?"; then
    echo "Updating system..."
    apt update && apt upgrade -y || error_exit "Failed to update system"
fi

# 3. Configure PHP
if confirm "Do you want to configure PHP?"; then
    echo "Configuring PHP..."
    PHP_INI_PATH=$(php -i | grep "Loaded Configuration File" | awk '{print $5}')
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 64M/" "$PHP_INI_PATH"
    sed -i "s/post_max_size = .*/post_max_size = 64M/" "$PHP_INI_PATH"
    sed -i "s/memory_limit = .*/memory_limit = 256M/" "$PHP_INI_PATH"
    sed -i "s/max_execution_time = .*/max_execution_time = 300/" "$PHP_INI_PATH"
    sed -i "s/max_input_time = .*/max_input_time = 300/" "$PHP_INI_PATH"
fi

# 8. Install and configure additional services
if confirm "Do you want to install and configure UFW firewall?"; then
    echo "Installing and configuring UFW firewall..."
    apt install ufw -y
    ufw --force enable
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 3306
fi

if confirm "Do you want to install Fail2ban?"; then
    apt install fail2ban -y
    systemctl enable fail2ban
    systemctl start fail2ban
fi

if confirm "Do you want to setup swap file?"; then
    echo "Setting up swap file..."
    fallocate -l ${SWAP_SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if confirm "Do you want to install additional utilities (plocate, rclone, pv, rsync)?"; then
    apt install -y plocate rclone pv rsync
fi

echo "Installation and configuration completed!"
