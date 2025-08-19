#!/bin/bash

# Enable Automatic Log Purging for MySQL
# This script configures MySQL to automatically purge old binary logs after 1 day

set -e

echo "=== MySQL Automatic Log Purging Setup ==="
echo

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    echo "Error: MySQL is not installed on this system."
    exit 1
fi

# Define MySQL configuration file path
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"

# Check if MySQL configuration file exists
if [ ! -f "$MYSQL_CONF" ]; then
    echo "Error: MySQL configuration file not found at $MYSQL_CONF"
    echo "Please check your MySQL installation."
    exit 1
fi

echo "Found MySQL configuration file at: $MYSQL_CONF"

# Create backup of original configuration
BACKUP_FILE="${MYSQL_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup of original configuration..."
sudo cp "$MYSQL_CONF" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Check if expire_logs_days is already configured
if grep -q "^expire_logs_days" "$MYSQL_CONF"; then
    echo "Warning: expire_logs_days is already configured in $MYSQL_CONF"
    echo "Current setting:"
    grep "^expire_logs_days" "$MYSQL_CONF"
    echo
    read -p "Do you want to update it to 1 day? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo sed -i 's/^expire_logs_days.*/expire_logs_days = 1/' "$MYSQL_CONF"
        echo "Updated expire_logs_days to 1 day"
    else
        echo "Keeping existing configuration"
        exit 0
    fi
else
    # Add expire_logs_days setting under [mysqld] section
    echo "Adding expire_logs_days = 1 to MySQL configuration..."
    
    if grep -q "^\[mysqld\]" "$MYSQL_CONF"; then
        # Add after [mysqld] section
        sudo sed -i '/^\[mysqld\]/a expire_logs_days = 1' "$MYSQL_CONF"
    else
        # Add [mysqld] section with the setting
        echo -e "\n[mysqld]\nexpire_logs_days = 1" | sudo tee -a "$MYSQL_CONF" > /dev/null
    fi
    echo "Configuration added successfully"
fi

echo
echo "Current MySQL configuration for log purging:"
grep -A 5 -B 1 "expire_logs_days" "$MYSQL_CONF" || echo "Configuration added"

echo
echo "Restarting MySQL service..."
sudo systemctl restart mysql

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo
echo "Verifying MySQL service status..."
if sudo systemctl is-active --quiet mysql; then
    echo "✓ MySQL service is running"
else
    echo "✗ MySQL service failed to start"
    echo "Please check the logs: sudo journalctl -u mysql -n 20"
    exit 1
fi

echo
echo "Verifying the configuration..."
mysql -e "SHOW VARIABLES LIKE 'expire_logs_days';" 2>/dev/null || {
    echo "Note: Could not verify configuration via MySQL command."
    echo "This might require MySQL authentication. The configuration file has been updated."
}

echo
echo "=== MySQL Automatic Log Purging Setup Complete ==="
echo "Binary logs will now be automatically purged after 1 day."
echo "Backup of original configuration: $BACKUP_FILE"