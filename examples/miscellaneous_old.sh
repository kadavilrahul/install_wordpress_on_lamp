#!/bin/bash

# Helper function for error handling
error_exit() {
    echo "$1" >&2
    exit 1
}

# Helper function for yes/no confirmation
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}
# Function for initial setup
initial_setup() {
    while true; do
        echo
        echo "Initial Setup Menu:"
        echo "1) Set swap file size"
        echo "2) Select WordPress directory"
        echo "3) Update the system"
        echo "4) Install and configure UFW firewall"
        echo "5) Install Fail2ban"
        echo "6) Setup swap file"
        echo "7) Install additional utilities (plocate, rclone, pv, rsync)"
        echo "q) Back to main menu"
        read -p "Enter your choice: " choice

        case "$choice" in
            1)
                read -p "Enter swap file size in GB (e.g., 3): " SWAP_SIZE
                ;;
            2)
                select_directory
                ;;
            3)
                if confirm "Do you want to update the system?"; then
                    echo "Updating system..."
                    apt update && apt upgrade -y || error_exit "Failed to update system"
                fi
                ;;
            4)
                if confirm "Do you want to install and configure UFW firewall?"; then
                    echo "Installing and configuring UFW firewall..."
                    apt install ufw -y
                    ufw --force enable
                    ufw allow OpenSSH
                    ufw allow 80/tcp
                    ufw allow 443/tcp
                    ufw allow 3306
                fi
                ;;
            5)
                if confirm "Do you want to install Fail2ban?"; then
                    apt install fail2ban -y
                    systemctl enable fail2ban
                    systemctl start fail2ban
                fi
                ;;
            6)
                if confirm "Do you want to setup swap file?"; then
                    echo "Setting up swap file..."
                    fallocate -l ${SWAP_SIZE}G /swapfile
                    chmod 600 /swapfile
                    mkswap /swapfile
                    swapon /swapfile
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                fi
                ;;
            7)
                if confirm "Do you want to install additional utilities (plocate, rclone, pv, rsync)?"; then
                    apt install -y plocate rclone pv rsync
                fi
                ;;
            q)
                break
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Function to select a directory
select_directory() {
  local i=1
  local directories=()
  echo "Available directories in /var/www/:"
  for dir in /var/www/*; do
    if [ -d "$dir" ]; then
      echo "  $i) $(basename "$dir")"
      directories+=("$dir")
      ((i++))
    fi
  done

  read -p "Enter the number of the website directory: " choice
  if [[ "$choice" -ge 1 && "$choice" -lt $i ]]; then
    WP_DIR="${directories[$choice-1]}"
    echo "You selected: $WP_DIR"
  else
    echo "Invalid choice. Please try again."
    select_directory
  fi
}

#select_directory

# Create PHP info file
#echo "<?php phpinfo(); ?>" > "$WP_DIR/info.php"

# Final Apache restart
#systemctl restart apache2

#echo "Installation and configuration completed!"

# MySQL Database Inspection Commands
function show_databases {
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SHOW DATABASES;"; then
        echo "Successfully showed databases."
    else
        echo "Failed to show databases."
    fi
}

function list_mysql_users {
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SELECT User, Host FROM mysql.user;"; then
        echo "Successfully listed MySQL users."
    else
        echo "Failed to list MySQL users."
    fi
}

function check_wordpress_urls {
    if [ -z "$1" ]; then
        read -p "Enter database name: " DB_NAME
        if [ -z "$DB_NAME" ]; then
            echo "Database name is required."
            return 1
        fi
        DATABASE_NAME="$DB_NAME"
    else
        DATABASE_NAME="$1"
    fi
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "USE $DATABASE_NAME; SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl', 'home');"; then
        echo "Successfully checked WordPress URLs."
    else
        echo "Failed to check WordPress URLs."
    fi
}

function get_database_size {
    if [ -z "$1" ]; then
        read -p "Enter database name: " DB_NAME
        if [ -z "$DB_NAME" ]; then
            echo "Database name is required."
            return 1
        fi
        DATABASE_NAME="$DB_NAME"
    else
        DATABASE_NAME="$1"
    fi
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    if mysql -u root -p"$MYSQL_PWD" -e "SELECT table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    WHERE table_schema = '$DATABASE_NAME'
    GROUP BY table_schema;"; then
        echo "Successfully got database size."
    else
        echo "Failed to get database size."
    fi
}

function grant_remote_access {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        read -p "Enter database name: " DB_NAME
        read -p "Enter username: " DB_USER
        read -p "Enter password: " DB_PASS
        if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
            echo "Database name, username, and password are required."
            return 1
        fi
        DATABASE_NAME="$DB_NAME"
        USERNAME="$DB_USER"
        PASSWORD="$DB_PASS"
        read -p "Enter host (default is '%'): " HOST
        HOST="${HOST:-%}"
    else
        DATABASE_NAME="$1"
        USERNAME="$2"
        PASSWORD="$3"
        HOST="${4:-%}"
    fi
    read -p "MySQL root password: " -s MYSQL_PWD
    echo
    
    # Check MySQL bind-address configuration
    if ! grep -q "^bind-address\s*=\s*0\.0\.0\.0" /etc/mysql/my.cnf 2>/dev/null; then
        echo "Warning: MySQL may not be configured to allow remote connections."
        echo "You may need to edit /etc/mysql/my.cnf and set:"
        echo "bind-address = 0.0.0.0"
        echo "Then restart MySQL with: systemctl restart mysql"
    fi

    # Check firewall
    if ! ufw status | grep -q "3306/tcp"; then
        echo "Warning: MySQL port 3306 may not be open in firewall."
        echo "You may need to run: ufw allow 3306/tcp"
    fi

    # Create user and grant privileges
    if mysql -u root -p"$MYSQL_PWD" -e "CREATE USER IF NOT EXISTS '$USERNAME'@'%' IDENTIFIED BY '$PASSWORD';" ; then
        if mysql -u root -p"$MYSQL_PWD" -e "GRANT ALL PRIVILEGES ON $DATABASE_NAME.* TO '$USERNAME'@'%';"; then
            if mysql -u root -p"$MYSQL_PWD" -e "FLUSH PRIVILEGES;"; then
                echo "Successfully granted remote access for $USERNAME@% to database $DATABASE_NAME"
                echo "You may need to:"
                echo "1. Configure MySQL to allow remote connections"
                echo "2. Open port 3306 in firewall"
            else
                echo "Failed to flush privileges."
            fi
        else
            echo "Failed to grant privileges."
        fi
    else
        echo "Failed to create user."
    fi
}

echo "MySQL utility functions added:"
echo "  show_databases, list_mysql_users, check_wordpress_urls, get_database_size, grant_remote_access, allow_remote_access"

# PHP Configuration
function adjust_php_settings {
    read -p "PHP version (e.g. 8.1): " PHP_VERSION
    read -p "Memory limit (e.g. 512M): " MEMORY_LIMIT
    read -p "Max execution time (e.g. 300): " MAX_EXECUTION_TIME
    
    for ini_type in cli apache2 fpm; do
        ini_file="/etc/php/${PHP_VERSION}/${ini_type}/php.ini"
        if [ -f "$ini_file" ]; then
            sed -i "s/^memory_limit = .*/memory_limit = ${MEMORY_LIMIT}/" "$ini_file"
            sed -i "s/^max_execution_time = .*/max_execution_time = ${MAX_EXECUTION_TIME}/" "$ini_file"
            echo "Updated ${ini_type} php.ini"
        fi
    done
    
    if systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null; then
        echo "PHP settings updated successfully."
    else
        echo "Failed to update PHP settings."
    fi
}

# PostgreSQL Utilities
function backup_postgres_db {
    read -p "Database name: " DB_NAME
    read -p "Username: " DB_USER
    read -s -p "Password: " DB_PASS
    echo
    read -p "Backup directory: " BACKUP_DIR
    
    timestamp=$(date '+%Y%m%d_%H%M%S')
    dump_file="${BACKUP_DIR}/${DB_NAME}_${timestamp}.dump"
    
    if sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$dump_file"; then
        echo "Backup created at ${dump_file}"
    else
        echo "Backup failed."
    fi
}

# WordPress Utilities
function backup_wordpress_site {
    read -p "WordPress directory (e.g. /var/www/mysite): " WP_DIR
    read -p "Backup directory: " BACKUP_DIR
    
    if [ -f "${WP_DIR}/wp-config.php" ]; then
        timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        backup_name="$(basename ${WP_DIR})_backup_${timestamp}.tar.gz"
        
        wp db export "${WP_DIR}/wp_db.sql" --path="${WP_DIR}" --allow-root
        tar -czf "${BACKUP_DIR}/${backup_name}" -C "${WP_DIR}" . || error_exit "Backup failed"
        rm -f "${WP_DIR}/wp_db.sql"
        
        echo "WordPress backup created at ${backup_name}"
    else
        echo "Not a WordPress directory"
    fi

    if [ -f "${BACKUP_DIR}/${backup_name}" ]; then
        echo "WordPress backup created successfully."
    else
        echo "WordPress backup failed."
    fi
}

# System Utilities
function toggle_root_ssh {
    read -p "Enable or disable root SSH? (enable/disable): " ACTION
    
    if [ "$ACTION" = "disable" ]; then
        sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    else
        sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
    fi
    
    if systemctl restart ssh; then
        echo "Root SSH access ${ACTION}d successfully."
    else
        echo "Failed to toggle root SSH access."
    fi
}

echo "Additional utility functions added:"
echo "  adjust_php_settings, backup_postgres_db, backup_wordpress_site, toggle_root_ssh"

# Main menu
main_menu() {
    while true; do
        echo
        echo "Main Menu:"
        echo "1) Show MySQL databases"
        echo "2) List MySQL users"
        echo "3) Check WordPress URLs"
        echo "4) Get database size"
        echo "5) Grant remote access to MySQL"
        echo "6) Adjust PHP settings"
        echo "7) Backup PostgreSQL database"
        echo "8) Backup WordPress site"
        echo "9) Toggle root SSH access"
        echo "10) Select WordPress directory"
        echo "11) Initial setup (swap size, WordPress directory)"
        echo "12) Allow remote access to MySQL"
        echo "q) Quit"
        read -p "Enter your choice: " choice

        case "$choice" in
            1) show_databases ;;
            2) list_mysql_users ;;
            3) check_wordpress_urls ;;
            4) get_database_size ;;
            5) grant_remote_access ;;
            6) adjust_php_settings ;;
            7) backup_postgres_db ;;
            8) backup_wordpress_site ;;
            9) toggle_root_ssh ;;
            10) select_directory ;;
            11) initial_setup ;;
            12) allow_remote_access ;;
            q) exit 0 ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

# Call the main menu
main_menu
