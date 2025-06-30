#!/bin/bash

# MySQL Utilities
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

function verify_mysql_root {
    local MYSQL_PWD="$1"
    if ! mysql -u root -p"$MYSQL_PWD" -e "SELECT 1" 2>/dev/null; then
        echo "ERROR: Invalid MySQL root password"
        return 1
    fi
    return 0
}

function grant_remote_access {
    # Accept parameters or prompt for them
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        while true; do
            read -p "MySQL root password: " -s MYSQL_PWD
            echo
            if verify_mysql_root "$MYSQL_PWD"; then
                break
            fi
            echo "Please try again"
        done
        read -p "Database name: " DB_NAME
        read -p "MySQL username: " DB_USER
        read -p "Remote IP (or % for any): " REMOTE_IP
        REMOTE_IP=${REMOTE_IP:-%}
    else
        if ! verify_mysql_root "$1"; then
            return 1
        fi
        MYSQL_PWD="$1"
        DB_NAME="$2"
        DB_USER="$3"
        REMOTE_IP="${4:-%}"
    fi

    # Configure remote access
    sed -i 's/^bind-address\s*=\s*.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf
    systemctl restart mysql
    ufw allow 3306/tcp

    # Create remote user with password and grant privileges
    mysql -u root -p"$MYSQL_PWD" -e "DROP USER IF EXISTS '${DB_USER}'@'${REMOTE_IP}';"
    mysql -u root -p"$MYSQL_PWD" -e "CREATE USER '${DB_USER}'@'${REMOTE_IP}' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -p"$MYSQL_PWD" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${REMOTE_IP}';"
    mysql -u root -p"$MYSQL_PWD" -e "FLUSH PRIVILEGES;"
    
    # Also ensure localhost access exists
    mysql -u root -p"$MYSQL_PWD" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

    echo "Remote access configured for ${DB_USER}@${REMOTE_IP} to ${DB_NAME}"
    echo "Testing connection..."
    if mysql -h 127.0.0.1 -u "$DB_USER" -p"$MYSQL_PWD" "$DB_NAME" -e "SHOW TABLES;"; then
        echo "Connection test successful"
    else
        echo "Connection test failed - check MySQL error logs"
    fi
}

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

# PostgreSQL Backup
function backup_postgres_db {
    echo "Listing PostgreSQL databases..."
    databases=$(sudo -u postgres psql -l -t | cut -d'|' -f1 | sed -e 's/ //g' -e '/^$/d' | grep -v template)
    
    if [ -z "$databases" ]; then
        echo "No PostgreSQL databases found."
        return 1
    fi

    echo "Available databases:"
    local i=1
    local db_array=()
    for db in $databases; do
        echo "  $i) $db"
        db_array+=("$db")
        ((i++))
    done

    read -p "Select database number: " choice
    if [[ "$choice" -ge 1 && "$choice" -lt $i ]]; then
        DB_NAME="${db_array[$choice-1]}"
        echo "Selected database: $DB_NAME"
    else
        echo "Invalid choice."
        return 1
    fi

    read -p "Backup directory: " BACKUP_DIR
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"
    
    timestamp=$(date '+%Y%m%d_%H%M%S')
    dump_file="${BACKUP_DIR}/${DB_NAME}_${timestamp}.dump"
    
    if sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$dump_file"; then
        echo "Backup created at ${dump_file}"
    else
        echo "Backup failed."
    fi
}

# WordPress Backup
function backup_wordpress_site {
    read -p "WordPress directory (e.g. /var/www/mysite): " WP_DIR
    read -p "Backup directory: " BACKUP_DIR
    
    if [ -f "${WP_DIR}/wp-config.php" ]; then
        timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        backup_name="$(basename ${WP_DIR})_backup_${timestamp}.tar.gz"
        
        wp db export "${WP_DIR}/wp_db.sql" --path="${WP_DIR}" --allow-root
        tar -czf "${BACKUP_DIR}/${backup_name}" -C "${WP_DIR}" . || echo "Backup failed"
        rm -f "${WP_DIR}/wp_db.sql"
        
        echo "WordPress backup created at ${backup_name}"
    else
        echo "Not a WordPress directory"
    fi
}

# SSH Security
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

# Directory Selection
function select_directory {
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

# Main Menu
function main_menu {
    while true; do
        echo
        echo "Miscellaneous Utilities Menu:"
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
            q) exit 0 ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

# Call the main menu if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi