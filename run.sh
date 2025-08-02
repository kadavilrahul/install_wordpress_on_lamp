#!/bin/bash

# WordPress LAMP Stack Installer - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; exit 1; }

# Check root
[[ $EUID -ne 0 ]] && err "Run as root: sudo $0"

# System prep
prep_system() {
    info "Preparing system..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt upgrade -y
    apt install -y curl wget unzip software-properties-common
    ok "System ready"
}

# Install Apache
install_apache() {
    info "Installing Apache..."
    apt install -y apache2
    systemctl enable apache2
    systemctl start apache2
    ufw allow 'Apache Full' 2>/dev/null || true
    ok "Apache installed"
}

# Install MySQL
install_mysql() {
    info "Installing MySQL..."
    apt install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
    
    # Secure installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root123';"
    mysql -u root -proot123 -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -proot123 -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -proot123 -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -proot123 -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -proot123 -e "FLUSH PRIVILEGES;"
    
    ok "MySQL installed (root password: root123)"
}

# Install PHP
install_php() {
    info "Installing PHP..."
    apt install -y php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl php-soap
    
    # Configure PHP
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' /etc/php/*/apache2/php.ini
    sed -i 's/post_max_size = .*/post_max_size = 64M/' /etc/php/*/apache2/php.ini
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/*/apache2/php.ini
    sed -i 's/memory_limit = .*/memory_limit = 256M/' /etc/php/*/apache2/php.ini
    
    systemctl restart apache2
    ok "PHP installed"
}

# Install WordPress
install_wordpress() {
    local domain="${1:-example.com}"
    local db_name="${2:-wordpress}"
    local db_user="${3:-wpuser}"
    local db_pass="${4:-$(openssl rand -base64 12)}"
    
    info "Installing WordPress for $domain..."
    
    # Create database
    mysql -u root -proot123 -e "CREATE DATABASE IF NOT EXISTS $db_name;"
    mysql -u root -proot123 -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    mysql -u root -proot123 -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
    mysql -u root -proot123 -e "FLUSH PRIVILEGES;"
    
    # Download WordPress
    local wp_dir="/var/www/$domain"
    mkdir -p "$wp_dir"
    cd /tmp
    wget -q https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -r wordpress/* "$wp_dir/"
    rm -rf wordpress latest.tar.gz
    
    # Configure WordPress
    cp "$wp_dir/wp-config-sample.php" "$wp_dir/wp-config.php"
    sed -i "s/database_name_here/$db_name/" "$wp_dir/wp-config.php"
    sed -i "s/username_here/$db_user/" "$wp_dir/wp-config.php"
    sed -i "s/password_here/$db_pass/" "$wp_dir/wp-config.php"
    
    # Set permissions
    chown -R www-data:www-data "$wp_dir"
    chmod -R 755 "$wp_dir"
    
    # Create Apache vhost
    cat > "/etc/apache2/sites-available/$domain.conf" <<EOF
<VirtualHost *:80>
    ServerName $domain
    DocumentRoot $wp_dir
    <Directory $wp_dir>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    
    a2ensite "$domain.conf"
    a2enmod rewrite
    systemctl reload apache2
    
    ok "WordPress installed for $domain"
    info "Database: $db_name | User: $db_user | Pass: $db_pass"
}

# Install SSL
install_ssl() {
    local domain="$1"
    info "Installing SSL for $domain..."
    
    apt install -y certbot python3-certbot-apache
    certbot --apache -d "$domain" --non-interactive --agree-tos --email admin@"$domain" || warn "SSL setup failed"
    
    ok "SSL configured"
}

# Install WP-CLI
install_wpcli() {
    info "Installing WP-CLI..."
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
    ok "WP-CLI installed"
}

# Main menu
menu() {
    echo -e "${C}WordPress LAMP Stack Installer${N}"
    echo "1) Full LAMP Stack Installation"
    echo "2) Install WordPress Site"
    echo "3) Install SSL Certificate"
    echo "4) Install WP-CLI"
    echo "0) Exit"
    read -p "Select option: " choice
    
    case "$choice" in
        1) 
            prep_system
            install_apache
            install_mysql
            install_php
            install_wpcli
            ok "LAMP stack installed successfully!"
            ;;
        2)
            read -p "Domain name: " domain
            read -p "Database name (default: wordpress): " db_name
            db_name=${db_name:-wordpress}
            install_wordpress "$domain" "$db_name"
            ;;
        3)
            read -p "Domain name: " domain
            install_ssl "$domain"
            ;;
        4)
            install_wpcli
            ;;
        0) exit 0 ;;
        *) warn "Invalid option" && menu ;;
    esac
}

# Main
case "${1:-menu}" in
    lamp) prep_system; install_apache; install_mysql; install_php; install_wpcli ;;
    wordpress) install_wordpress "$2" "$3" "$4" "$5" ;;
    ssl) install_ssl "$2" ;;
    wpcli) install_wpcli ;;
    menu) menu ;;
    *) echo "Usage: $0 [lamp|wordpress|ssl|wpcli|menu]" ;;
esac