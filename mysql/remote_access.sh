#!/bin/bash

# MySQL Remote Access Configuration Script
# Improved version with better security and error handling

CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config.json"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if MySQL is running
check_mysql_status() {
    if ! systemctl is-active --quiet mysql; then
        log_message "ERROR: MySQL service is not running"
        exit 1
    fi
}

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR: Config file $CONFIG_FILE not found"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "ERROR: jq is not installed. Please install it first: sudo apt-get install jq"
    exit 1
fi

# Read root password from config
ROOT_PASS=$(jq -r '.mysql_root_password' "$CONFIG_FILE")
if [ -z "$ROOT_PASS" ] || [ "$ROOT_PASS" = "null" ]; then
    log_message "ERROR: mysql_root_password not found in config.json"
    exit 1
fi

# Check MySQL service status
check_mysql_status

# Test MySQL connection first
if ! mysql -u root -p"$ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    log_message "ERROR: Cannot connect to MySQL with provided credentials"
    exit 1
fi

# Backup current MySQL configuration
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
if [ -f "$MYSQL_CONF" ]; then
    sudo cp "$MYSQL_CONF" "$MYSQL_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    log_message "MySQL configuration backed up"
else
    log_message "WARNING: MySQL configuration file not found at $MYSQL_CONF"
fi

# Configure MySQL for remote access
log_message "Configuring MySQL for remote access..."

# Check if bind-address exists and modify it
if grep -q "^bind-address" "$MYSQL_CONF"; then
    sudo sed -i 's/^bind-address.*=.*/bind-address = 0.0.0.0/' "$MYSQL_CONF"
else
    # Add bind-address if it doesn't exist
    sudo bash -c "echo 'bind-address = 0.0.0.0' >> $MYSQL_CONF"
fi

# Check if mysqlx-bind-address exists and modify it
if grep -q "^mysqlx-bind-address" "$MYSQL_CONF"; then
    sudo sed -i 's/^mysqlx-bind-address.*=.*/mysqlx-bind-address = 0.0.0.0/' "$MYSQL_CONF"
fi

# Get list of databases (excluding system databases)
DATABASES=$(mysql -u root -p"$ROOT_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")

if [ -z "$DATABASES" ]; then
    log_message "WARNING: No user databases found"
else
    log_message "Found databases: $DATABASES"
fi

# Configure remote access for each database
for DB in $DATABASES; do
    log_message "Configuring remote access for database: $DB"
    
    # Get existing users for this database (fixed query)
    USERS=$(mysql -u root -p"$ROOT_PASS" -e "SELECT DISTINCT User FROM mysql.db WHERE Db = '$DB' OR Db = '%';" 2>/dev/null | tail -n +2)
    
    if [ -z "$USERS" ]; then
        log_message "  No specific users found for database $DB"
        continue
    fi
    
    for USER in $USERS; do
        # Skip if user is empty or contains special characters that might cause issues
        if [ -z "$USER" ] || [[ "$USER" =~ [[:space:]] ]]; then
            continue
        fi
        
        log_message "  Processing user: $USER"
        
        # Handle known user specially
        if [ "$USER" = "test_silkroademart_com_user" ]; then
            mysql -u root -p"$ROOT_PASS" -e "
                CREATE USER IF NOT EXISTS 'test_silkroademart_com_user'@'%' IDENTIFIED BY 'test_silkroademart_com_2@';
                GRANT ALL PRIVILEGES ON test_silkroademart_com_db.* TO 'test_silkroademart_com_user'@'%';
                FLUSH PRIVILEGES;
            " 2>/dev/null && log_message "  Successfully configured test_silkroademart_com_user@%" || log_message "  Warning: Failed to configure test_silkroademart_com_user@%"
        else
            # Check if user@'%' already exists
            USER_EXISTS=$(mysql -u root -p"$ROOT_PASS" -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='$USER' AND host='%';" 2>/dev/null)
            
            if [ "$USER_EXISTS" -eq 0 ]; then
                # Get the password hash from localhost user
                PWD_HASH=$(mysql -u root -p"$ROOT_PASS" -sN -e "SELECT authentication_string FROM mysql.user WHERE user='$USER' AND host='localhost' LIMIT 1;" 2>/dev/null)
                
                if [ -n "$PWD_HASH" ] && [ "$PWD_HASH" != "NULL" ]; then
                    mysql -u root -p"$ROOT_PASS" -e "
                        CREATE USER '$USER'@'%' IDENTIFIED WITH mysql_native_password AS '$PWD_HASH';
                        GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$USER'@'%';
                        FLUSH PRIVILEGES;
                    " 2>/dev/null && log_message "  Successfully granted remote access to $USER@%" || log_message "  Warning: Failed to grant privileges for $USER@%"
                else
                    log_message "  Warning: Could not retrieve password hash for $USER"
                fi
            else
                log_message "  User $USER@'%' already exists, updating privileges..."
                mysql -u root -p"$ROOT_PASS" -e "
                    GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$USER'@'%';
                    FLUSH PRIVILEGES;
                " 2>/dev/null && log_message "  Successfully updated privileges for $USER@%" || log_message "  Warning: Failed to update privileges for $USER@%"
            fi
        fi
    done
done

# Configure root user for remote access (with security warning)
log_message "Configuring root user for remote access..."
log_message "WARNING: Enabling remote root access is a security risk. Consider creating dedicated users instead."

mysql -u root -p"$ROOT_PASS" -e "
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$ROOT_PASS';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
" 2>/dev/null && log_message "Successfully configured root@%" || log_message "Warning: Failed to configure root@%"

# Restart MySQL to apply changes
log_message "Restarting MySQL service..."
if sudo systemctl restart mysql; then
    log_message "MySQL service restarted successfully"
    # Wait a moment for MySQL to fully start
    sleep 3
else
    log_message "ERROR: Failed to restart MySQL service"
    exit 1
fi

# Test remote connection
log_message "Testing remote connection..."
if mysql -h 127.0.0.1 -u root -p"$ROOT_PASS" -e "SHOW DATABASES;" &>/dev/null; then
    log_message "MySQL remote configuration successful!"
    echo ""
    echo "=== CONNECTION INFORMATION ==="
    echo "Host: $(curl -s ifconfig.me || echo 'your_server_ip')"
    echo "Port: 3306"
    echo ""
    echo "Root access:"
    echo "User: root"
    echo "Password: [configured_root_password]"
    echo ""
    echo "Database users configured:"
    mysql -u root -p"$ROOT_PASS" -e "SELECT DISTINCT User, Host FROM mysql.user WHERE Host = '%' AND User != 'root';" 2>/dev/null || echo "Failed to retrieve user list"
    echo ""
    echo "=== SECURITY RECOMMENDATIONS ==="
    echo "1. Configure firewall to allow port 3306 only from trusted IPs"
    echo "2. Use SSL/TLS for remote connections"
    echo "3. Create specific users for each application instead of using root"
    echo "4. Regularly update MySQL and monitor access logs"
    echo ""
    echo "=== FIREWALL CONFIGURATION ==="
    echo "To allow specific IPs only:"
    echo "sudo ufw allow from YOUR_IP_ADDRESS to any port 3306"
    echo "sudo ufw reload"
else
    log_message "ERROR: MySQL remote configuration failed"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check if MySQL is running: sudo systemctl status mysql"
    echo "2. Verify firewall settings: sudo ufw status"
    echo "3. Check MySQL error logs: sudo tail -f /var/log/mysql/error.log"
    echo "4. Test local connection: mysql -u root -p"
    echo "5. Verify bind-address in config: grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf"
    exit 1
fi