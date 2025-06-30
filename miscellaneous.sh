#!/bin/bash

# System Utilities
function system_utilities() {
    read -p "Swap size in GB (default: 2): " SWAP_SIZE; [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="2"
    
    confirm "Update system?" && { apt update && apt upgrade -y || warn "Update failed"; }
    
    if confirm "Install UFW firewall?"; then
        apt install -y ufw && ufw --force enable && ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 3306 && success "UFW configured"
    fi
    
    confirm "Install Fail2ban?" && { apt install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban && success "Fail2ban installed"; }
    
    if confirm "Setup ${SWAP_SIZE}GB swap?"; then
        fallocate -l "${SWAP_SIZE}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab && success "Swap created"
    fi
    
    confirm "Install utilities (plocate, rclone, pv, rsync)?" && { apt install -y plocate rclone pv rsync && success "Utilities installed"; }
    
    success "System utilities configuration completed"
    read -p "Press Enter to continue..."
}

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
    # Function to modify php.ini
    modify_php_ini() {
        local ini_file="$1"
        echo "Modifying PHP INI file: $ini_file"

        if [ -f "$ini_file" ]; then
            sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$ini_file"
            sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$ini_file"
            sed -i "s/^memory_limit = .*/memory_limit = 512M/" "$ini_file"
            sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$ini_file"
            sed -i "s/^max_input_time = .*/max_input_time = 300/" "$ini_file"
        else
            echo "Error: PHP INI file not found: $ini_file"
        fi
    }

    # Get PHP version
    PHP_VERSION=$(php -v | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    echo "Detected PHP version: ${PHP_VERSION}"

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

    # Restart Apache if it's running
    if systemctl is-active apache2 > /dev/null 2>&1; then
        echo "Restarting Apache..."
        systemctl restart apache2
    fi

    echo "PHP configuration completed!"
    read -p "Press Enter to continue..."
}

# PHP Configuration
function adjust_php_config {
    local PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    [ -z "$PHP_VERSION" ] && { echo "PHP not installed"; return 1; }

    echo "Adjusting PHP $PHP_VERSION configuration..."
    for ini in "/etc/php/$PHP_VERSION/cli/php.ini" "/etc/php/$PHP_VERSION/apache2/php.ini" "/etc/php/$PHP_VERSION/fpm/php.ini"; do
        [ -f "$ini" ] && sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/; s/^post_max_size = .*/post_max_size = 64M/; s/^memory_limit = .*/memory_limit = 512M/; s/^max_execution_time = .*/max_execution_time = 300/' "$ini"
    done

    systemctl restart apache2 php"$PHP_VERSION"-fpm 2>/dev/null || true
    echo "PHP configuration updated"
}

# View PHP Information
function view_php_info {
    clear
    echo "PHP Information"
    echo
    echo "1) Open in browser"
    echo "2) Back to menu"
    echo
    read -p "Select option: " choice
    
    case $choice in
        1)
            if [ ! -f "/var/www/html/phpinfo.php" ]; then
                echo "Creating phpinfo.php in /var/www/html..."
                echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
                chown www-data:www-data /var/www/html/phpinfo.php
                chmod 644 /var/www/html/phpinfo.php
            fi
            SERVER_IP=$(hostname -I | awk '{print $1}')
            xdg-open "http://${SERVER_IP}/phpinfo.php" || echo "Failed to open browser"
            ;;
        2) return ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
    
    read -p "Press Enter to continue..."
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

# SSH Security Management
function toggle_root_ssh {
    echo "1) Disable root SSH  2) Enable root SSH  3) Back"
    read -p "Choose (1-3): " choice
    
    case $choice in
        1)
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config* 2>/dev/null
            systemctl restart ssh
            echo "Root SSH disabled successfully"
            ;;
        2)
            sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config* 2>/dev/null
            systemctl restart ssh
            echo "Root SSH enabled successfully"
            ;;
        3)
            return
            ;;
        *)
            echo "Invalid option"
            sleep 1
            toggle_root_ssh
            return
            ;;
    esac
    read -p "Press Enter to continue..."
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
        echo "11) View PHP Info"
        echo "12) System Utilities"
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
            11) view_php_info ;;
            12) system_utilities ;;
            q) exit 0 ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

# Call the main menu if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi