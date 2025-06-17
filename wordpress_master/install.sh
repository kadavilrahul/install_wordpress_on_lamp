#!/bin/bash

#=============================================================================
# WordPress Master Installation Script
# Comprehensive LAMP Stack + WordPress Management Tool
# Combines all functionality from custom_script into a single interactive tool
#=============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_message "ERROR" "$1"
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Success message
success_msg() {
    log_message "SUCCESS" "$1"
    echo -e "${GREEN}✓ $1${NC}"
}

# Warning message
warning_msg() {
    log_message "WARNING" "$1"
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Info message
info_msg() {
    log_message "INFO" "$1"
    echo -e "${BLUE}ℹ $1${NC}"
}

# Confirmation prompt
confirm() {
    read -p "$(echo -e "${CYAN}$1 (y/n): ${NC}")" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Check system requirements
check_system() {
    info_msg "Checking system requirements..."
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu" /etc/os-release; then
        warning_msg "This script is designed for Ubuntu. Proceed with caution."
    fi
    
    # Check available disk space (minimum 5GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then
        error_exit "Insufficient disk space. At least 5GB required."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error_exit "No internet connection detected"
    fi
    
    success_msg "System requirements check passed"
}

#=============================================================================
# MAIN MENU SYSTEM
#=============================================================================

show_header() {
    clear
    echo -e "${PURPLE}"
    echo "============================================================================="
    echo "                    WordPress Master Installation Tool"
    echo "                   Comprehensive LAMP Stack Management"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

show_main_menu() {
    show_header
    echo -e "${YELLOW}Main Menu:${NC}"
    echo
    echo -e "  ${GREEN}INSTALLATION & SETUP${NC}"
    echo "    1) Install Complete LAMP Stack + WordPress"
    echo "    2) Install Apache + SSL Only"
    echo "    3) Install phpMyAdmin"
    echo
    echo -e "  ${GREEN}BACKUP & RESTORE${NC}"
    echo "    4) Backup WordPress Sites"
    echo "    5) Restore WordPress Sites"
    echo "    6) Backup PostgreSQL Database"
    echo "    7) Restore PostgreSQL Database"
    echo "    8) Transfer Backups from Old Server"
    echo
    echo -e "  ${GREEN}SYSTEM MANAGEMENT${NC}"
    echo "    9) Adjust PHP Configuration"
    echo "   10) Configure Redis"
    echo "   11) SSH Security Management"
    echo "   12) System Utilities (UFW, Fail2ban, Swap)"
    echo
    echo -e "  ${GREEN}WEBSITE REMOVAL${NC}"
    echo "   13) Remove Websites & Databases"
    echo
    echo -e "  ${GREEN}TROUBLESHOOTING & TOOLS${NC}"
    echo "   14) Troubleshooting Guide"
    echo "   15) MySQL Database Commands"
    echo "   16) System Status Check"
    echo
    echo "   17) Exit"
    echo
    echo -e "${CYAN}=============================================================================${NC}"
}

#=============================================================================
# CONFIGURATION MANAGEMENT
#=============================================================================

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        info_msg "Configuration loaded from $CONFIG_FILE"
    else
        info_msg "No configuration file found. Will create one during setup."
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# WordPress Master Configuration
# Generated on $(date)

# Database Configuration
DB_ROOT_PASSWORD="$DB_ROOT_PASSWORD"
ADMIN_EMAIL="$ADMIN_EMAIL"

# Redis Configuration
REDIS_MAX_MEMORY="$REDIS_MAX_MEMORY"

# Paths
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"

# Last installation details
LAST_DOMAIN="$DOMAIN"
LAST_INSTALL_TYPE="$INSTALL_TYPE"
LAST_INSTALL_DATE="$(date)"
EOF
    success_msg "Configuration saved to $CONFIG_FILE"
}

#=============================================================================
# WORDPRESS INSTALLATION FUNCTIONS
#=============================================================================

install_lamp_wordpress() {
    show_header
    echo -e "${YELLOW}WordPress Installation Options:${NC}"
    echo
    echo "1) Main Domain Installation (example.com)"
    echo "2) Subdomain Installation (blog.example.com)"
    echo "3) Subdirectory Installation (example.com/blog)"
    echo "4) Back to Main Menu"
    echo
    
    read -p "$(echo -e "${CYAN}Select installation type (1-4): ${NC}")" install_choice
    
    case $install_choice in
        1) install_wordpress_main_domain ;;
        2) install_wordpress_subdomain ;;
        3) install_wordpress_subdirectory ;;
        4) return ;;
        *) 
            echo -e "${RED}Invalid option${NC}"
            sleep 2
            install_lamp_wordpress
            ;;
    esac
}

get_installation_inputs() {
    local install_type="$1"
    
    echo -e "${YELLOW}Please provide the following information:${NC}"
    echo
    
    # Get domain information based on installation type
    case $install_type in
        "main")
            read -p "Enter main domain name (e.g., example.com): " DOMAIN
            INSTALL_TYPE="main_domain"
            ;;
        "subdomain")
            read -p "Enter main domain name (e.g., example.com): " MAIN_DOMAIN
            read -p "Enter subdomain name (e.g., blog): " SUBDOMAIN
            DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"
            INSTALL_TYPE="subdomain"
            ;;
        "subdirectory")
            read -p "Enter main domain name (e.g., example.com): " MAIN_DOMAIN
            read -p "Enter WordPress subdirectory name (e.g., blog): " WP_SUBDIR
            DOMAIN="$MAIN_DOMAIN"
            INSTALL_TYPE="subdirectory"
            ;;
    esac
    
    # Common inputs
    read -p "Enter admin email: " ADMIN_EMAIL
    
    # Database password with confirmation
    while true; do
        read -sp "Enter MySQL root password (new password): " DB_ROOT_PASSWORD
        echo
        read -sp "Confirm MySQL root password: " DB_ROOT_PASSWORD_CONFIRM
        echo
        
        if [ "$DB_ROOT_PASSWORD" = "$DB_ROOT_PASSWORD_CONFIRM" ]; then
            break
        else
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
        fi
    done
    
    # Redis memory configuration
    read -p "Enter Redis maximum memory in GB (Default is 1): " REDIS_MAX_MEMORY
    [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    
    # Confirmation
    echo
    echo -e "${YELLOW}Installation Summary:${NC}"
    echo "Domain: $DOMAIN"
    echo "Installation Type: $INSTALL_TYPE"
    echo "Admin Email: $ADMIN_EMAIL"
    echo "Redis Memory: ${REDIS_MAX_MEMORY}GB"
    echo
    
    if ! confirm "Proceed with installation?"; then
        return 1
    fi
    
    return 0
}

install_base_lamp_stack() {
    info_msg "Starting LAMP stack installation..."
    
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    
    # Update system
    info_msg "Updating system packages..."
    apt update -y || error_exit "Failed to update packages"
    apt upgrade -y || error_exit "Failed to upgrade packages"
    
    # Install Apache
    info_msg "Installing Apache..."
    apt install apache2 -y || error_exit "Failed to install Apache"
    systemctl enable apache2
    systemctl start apache2
    
    # Install MySQL
    info_msg "Installing MySQL..."
    apt install mysql-server -y || error_exit "Failed to install MySQL"
    systemctl enable mysql
    systemctl start mysql
    
    # Secure MySQL installation
    info_msg "Securing MySQL installation..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD';" || error_exit "Failed to set MySQL root password"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';" || warning_msg "Failed to remove anonymous users"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" || warning_msg "Failed to remove remote root access"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;" || warning_msg "Test database not found"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" || error_exit "Failed to flush privileges"
    
    # Install PHP and extensions
    info_msg "Installing PHP and extensions..."
    apt install php libapache2-mod-php php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl php-soap php-bcmath php-xmlrpc php-imagick php-dev php-imap php-opcache -y || error_exit "Failed to install PHP"
    
    # Enable Apache modules
    info_msg "Enabling Apache modules..."
    a2enmod rewrite ssl headers || error_exit "Failed to enable Apache modules"
    
    # Install additional tools
    info_msg "Installing additional tools..."
    apt install curl wget unzip certbot python3-certbot-apache redis-server -y || error_exit "Failed to install additional tools"
    
    # Configure Redis
    systemctl enable redis-server
    systemctl start redis-server
    
    success_msg "Base LAMP stack installation completed"
}

install_wordpress_main_domain() {
    if ! get_installation_inputs "main"; then
        return
    fi
    
    install_base_lamp_stack
    
    info_msg "Setting up WordPress for main domain: $DOMAIN"
    
    # Create directory structure
    SITE_DIR="/var/www/$DOMAIN"
    mkdir -p "$SITE_DIR" || error_exit "Failed to create site directory"
    
    # Download WordPress
    info_msg "Downloading WordPress..."
    cd /tmp
    wget https://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"
    tar xzf latest.tar.gz || error_exit "Failed to extract WordPress"
    cp -R wordpress/* "$SITE_DIR/" || error_exit "Failed to copy WordPress files"
    rm -rf wordpress latest.tar.gz
    
    # Set permissions
    chown -R www-data:www-data "$SITE_DIR"
    chmod -R 755 "$SITE_DIR"
    
    # Create database
    DB_NAME=$(echo "$DOMAIN" | sed 's/\./_/g' | sed 's/-/_/g')
    DB_USER="${DB_NAME}_user"
    DB_PASSWORD=$(openssl rand -base64 12)
    
    info_msg "Creating database: $DB_NAME"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME;" || error_exit "Failed to create database"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" || error_exit "Failed to create database user"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" || error_exit "Failed to grant privileges"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" || error_exit "Failed to flush privileges"
    
    # Configure WordPress
    info_msg "Configuring WordPress..."
    cp "$SITE_DIR/wp-config-sample.php" "$SITE_DIR/wp-config.php"
    
    # Generate WordPress salts
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    # Update wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" "$SITE_DIR/wp-config.php"
    sed -i "s/username_here/$DB_USER/" "$SITE_DIR/wp-config.php"
    sed -i "s/password_here/$DB_PASSWORD/" "$SITE_DIR/wp-config.php"
    sed -i "s/localhost/localhost/" "$SITE_DIR/wp-config.php"
    
    # Add salts
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$SITE_DIR/wp-config.php"
    sed -i "/define('DB_COLLATE', '');/a\\$SALTS" "$SITE_DIR/wp-config.php"
    
    # Add additional configurations
    cat >> "$SITE_DIR/wp-config.php" << EOF

// Additional WordPress configurations
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
EOF
    
    # Create Apache virtual host
    create_apache_vhost "$DOMAIN" "$SITE_DIR"
    
    # Install SSL certificate
    install_ssl_certificate "$DOMAIN"
    
    # Install WP-CLI
    install_wp_cli
    
    # Configure Redis for WordPress
    configure_wordpress_redis "$SITE_DIR"
    
    # Save installation summary
    save_installation_summary
    
    success_msg "WordPress installation completed for $DOMAIN"
    show_installation_summary
}

# Create Apache virtual host
create_apache_vhost() {
    local domain="$1"
    local site_dir="$2"
    
    info_msg "Creating Apache virtual host for $domain"
    
    cat > "/etc/apache2/sites-available/$domain.conf" << EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $site_dir
    
    <Directory $site_dir>
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error_$domain.log
    CustomLog \${APACHE_LOG_DIR}/access_$domain.log combined
</VirtualHost>
EOF
    
    # Enable site
    a2ensite "$domain.conf" || error_exit "Failed to enable site"
    systemctl reload apache2 || error_exit "Failed to reload Apache"
    
    success_msg "Apache virtual host created for $domain"
}

# Install SSL certificate
install_ssl_certificate() {
    local domain="$1"
    
    info_msg "Installing SSL certificate for $domain"
    
    # Check if domain resolves to this server
    if ! host "$domain" > /dev/null 2>&1; then
        warning_msg "Domain $domain does not resolve. SSL installation may fail."
        if ! confirm "Continue with SSL installation anyway?"; then
            return
        fi
    fi
    
    # Install SSL certificate
    certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" || {
        warning_msg "SSL certificate installation failed. You can install it manually later."
        return
    }
    
    success_msg "SSL certificate installed for $domain"
}

# Install WP-CLI
install_wp_cli() {
    if command -v wp &> /dev/null; then
        info_msg "WP-CLI already installed"
        return
    fi
    
    info_msg "Installing WP-CLI..."
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || error_exit "Failed to download WP-CLI"
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp || error_exit "Failed to install WP-CLI"
    
    success_msg "WP-CLI installed successfully"
}

# Configure Redis for WordPress
configure_wordpress_redis() {
    local site_dir="$1"
    
    info_msg "Configuring Redis for WordPress..."
    
    # Configure Redis memory
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server
    
    # Add Redis configuration to wp-config.php
    cat >> "$site_dir/wp-config.php" << EOF

// Redis Configuration
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);
EOF
    
    success_msg "Redis configured for WordPress"
}

# Save installation summary
save_installation_summary() {
    local summary_file="/root/installation_summary_${DOMAIN}.txt"
    
    cat > "$summary_file" << EOF
WordPress Installation Summary
==============================
Date: $(date)
Domain: $DOMAIN
Installation Type: $INSTALL_TYPE
Admin Email: $ADMIN_EMAIL

Database Information:
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
MySQL Root Password: [HIDDEN]

Site Directory: $SITE_DIR
Redis Memory: ${REDIS_MAX_MEMORY}GB

Access URLs:
Website: https://$DOMAIN
Admin Panel: https://$DOMAIN/wp-admin

Next Steps:
1. Complete WordPress setup by visiting: https://$DOMAIN
2. Install Redis Object Cache plugin for better performance
3. Configure your WordPress site as needed

Log File: $LOG_FILE
EOF
    
    success_msg "Installation summary saved to $summary_file"
}

# Show installation summary
show_installation_summary() {
    echo
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}    WordPress Installation Completed!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo
    echo -e "${YELLOW}Domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Installation Type:${NC} $INSTALL_TYPE"
    echo -e "${YELLOW}Site Directory:${NC} $SITE_DIR"
    echo
    echo -e "${YELLOW}Database Information:${NC}"
    echo -e "  Database Name: $DB_NAME"
    echo -e "  Database User: $DB_USER"
    echo -e "  Database Password: $DB_PASSWORD"
    echo
    echo -e "${YELLOW}Access URLs:${NC}"
    echo -e "  Website: ${CYAN}https://$DOMAIN${NC}"
    echo -e "  Admin Panel: ${CYAN}https://$DOMAIN/wp-admin${NC}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  1. Complete WordPress setup by visiting your website"
    echo -e "  2. Install Redis Object Cache plugin for better performance"
    echo -e "  3. Configure your WordPress site as needed"
    echo
    echo -e "${GREEN}=============================================${NC}"
    
    read -p "Press Enter to continue..."
}

# Install WordPress on subdomain
install_wordpress_subdomain() {
    if ! get_installation_inputs "subdomain"; then
        return
    fi
    
    install_base_lamp_stack
    
    info_msg "Setting up WordPress for subdomain: $DOMAIN"
    
    # Create directory structure
    SITE_DIR="/var/www/$DOMAIN"
    mkdir -p "$SITE_DIR" || error_exit "Failed to create site directory"
    
    # Download and setup WordPress (same as main domain)
    cd /tmp
    wget https://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"
    tar xzf latest.tar.gz || error_exit "Failed to extract WordPress"
    cp -R wordpress/* "$SITE_DIR/" || error_exit "Failed to copy WordPress files"
    rm -rf wordpress latest.tar.gz
    
    # Set permissions
    chown -R www-data:www-data "$SITE_DIR"
    chmod -R 755 "$SITE_DIR"
    
    # Create database
    DB_NAME=$(echo "$DOMAIN" | sed 's/\./_/g' | sed 's/-/_/g')
    DB_USER="${DB_NAME}_user"
    DB_PASSWORD=$(openssl rand -base64 12)
    
    info_msg "Creating database: $DB_NAME"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME;" || error_exit "Failed to create database"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" || error_exit "Failed to create database user"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" || error_exit "Failed to grant privileges"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" || error_exit "Failed to flush privileges"
    
    # Configure WordPress
    info_msg "Configuring WordPress..."
    cp "$SITE_DIR/wp-config-sample.php" "$SITE_DIR/wp-config.php"
    
    # Generate WordPress salts
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    # Update wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" "$SITE_DIR/wp-config.php"
    sed -i "s/username_here/$DB_USER/" "$SITE_DIR/wp-config.php"
    sed -i "s/password_here/$DB_PASSWORD/" "$SITE_DIR/wp-config.php"
    
    # Add salts and configurations
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$SITE_DIR/wp-config.php"
    sed -i "/define('DB_COLLATE', '');/a\\$SALTS" "$SITE_DIR/wp-config.php"
    
    cat >> "$SITE_DIR/wp-config.php" << EOF

// Additional WordPress configurations
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
EOF
    
    # Create Apache virtual host
    create_apache_vhost "$DOMAIN" "$SITE_DIR"
    
    # Install SSL certificate
    install_ssl_certificate "$DOMAIN"
    
    # Install WP-CLI and configure Redis
    install_wp_cli
    configure_wordpress_redis "$SITE_DIR"
    
    # Save installation summary
    save_installation_summary
    
    success_msg "WordPress installation completed for subdomain $DOMAIN"
    show_installation_summary
}

# Install WordPress on subdirectory
install_wordpress_subdirectory() {
    if ! get_installation_inputs "subdirectory"; then
        return
    fi
    
    install_base_lamp_stack
    
    info_msg "Setting up WordPress for subdirectory: $MAIN_DOMAIN/$WP_SUBDIR"
    
    # Create directory structure
    MAIN_DIR="/var/www/$MAIN_DOMAIN"
    SITE_DIR="$MAIN_DIR/$WP_SUBDIR"
    mkdir -p "$SITE_DIR" || error_exit "Failed to create site directory"
    
    # Download and setup WordPress
    cd /tmp
    wget https://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress"
    tar xzf latest.tar.gz || error_exit "Failed to extract WordPress"
    cp -R wordpress/* "$SITE_DIR/" || error_exit "Failed to copy WordPress files"
    rm -rf wordpress latest.tar.gz
    
    # Set permissions
    chown -R www-data:www-data "$SITE_DIR"
    chmod -R 755 "$SITE_DIR"
    
    # Create database
    DB_NAME=$(echo "${MAIN_DOMAIN}_${WP_SUBDIR}" | sed 's/\./_/g' | sed 's/-/_/g')
    DB_USER="${DB_NAME}_user"
    DB_PASSWORD=$(openssl rand -base64 12)
    
    info_msg "Creating database: $DB_NAME"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME;" || error_exit "Failed to create database"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" || error_exit "Failed to create database user"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" || error_exit "Failed to grant privileges"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" || error_exit "Failed to flush privileges"
    
    # Configure WordPress
    info_msg "Configuring WordPress..."
    cp "$SITE_DIR/wp-config-sample.php" "$SITE_DIR/wp-config.php"
    
    # Generate WordPress salts
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    # Update wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" "$SITE_DIR/wp-config.php"
    sed -i "s/username_here/$DB_USER/" "$SITE_DIR/wp-config.php"
    sed -i "s/password_here/$DB_PASSWORD/" "$SITE_DIR/wp-config.php"
    
    # Add salts and configurations
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$SITE_DIR/wp-config.php"
    sed -i "/define('DB_COLLATE', '');/a\\$SALTS" "$SITE_DIR/wp-config.php"
    
    # Add subdirectory specific configurations
    cat >> "$SITE_DIR/wp-config.php" << EOF

// Subdirectory WordPress configurations
define('WP_SITEURL', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
define('WP_HOME', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
EOF
    
    # Create or update Apache virtual host for main domain
    if [ ! -f "/etc/apache2/sites-available/$MAIN_DOMAIN.conf" ]; then
        create_apache_vhost "$MAIN_DOMAIN" "$MAIN_DIR"
    fi
    
    # Install SSL certificate for main domain
    install_ssl_certificate "$MAIN_DOMAIN"
    
    # Install WP-CLI and configure Redis
    install_wp_cli
    configure_wordpress_redis "$SITE_DIR"
    
    # Save installation summary
    save_installation_summary
    
    success_msg "WordPress installation completed for subdirectory $MAIN_DOMAIN/$WP_SUBDIR"
    show_installation_summary
}

#=============================================================================
# APACHE AND SSL ONLY INSTALLATION
#=============================================================================

install_apache_ssl_only() {
    show_header
    echo -e "${YELLOW}Apache + SSL Only Installation${NC}"
    echo "This will install Apache web server with SSL support for a new domain."
    echo
    
    # Get domain name for setup
    read -p "Enter your domain name: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        error_exit "Domain name required!"
    fi
    
    setup_new_domain
}

setup_new_domain() {
    # Get domain name for setup
    read -p "Enter your domain name: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo "Error: Domain name required!"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    echo "Setting up $DOMAIN..."
    
    # Update and install packages
    apt update -qq
    apt install -y apache2 certbot python3-certbot-apache dig
    
    # Enable Apache modules
    a2enmod rewrite ssl
    
    # Create web directory
    WEB_ROOT="/var/www/$DOMAIN"
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"
    
    # Create sample page
    cat > "$WEB_ROOT/index.html" << EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        .container { background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 600px; margin: 0 auto; }
        h1 { color: #333; text-align: center; }
        .status { background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; text-align: center; }
        .info { background: #f0f8ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Welcome to $DOMAIN</h1>
        <div class="status">
            <strong>✅ Your website is live and secure!</strong>
        </div>
        <div class="info">
            <p><strong>Domain:</strong> $DOMAIN</p>
            <p><strong>Status:</strong> Active with SSL certificate</p>
            <p><strong>Server:</strong> Apache on Ubuntu</p>
        </div>
        <p>Your website is now ready for content. You can upload your files to replace this page.</p>
        <hr>
        <small>Generated by Domain Setup Script</small>
    </div>
</body>
</html>
EOT
    
    # Create Apache config
    cat > "/etc/apache2/sites-available/$DOMAIN.conf" << EOT
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $WEB_ROOT
    DirectoryIndex index.html index.php
    <Directory $WEB_ROOT>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOT
    
    # Enable site
    a2ensite "$DOMAIN.conf"
    systemctl reload apache2
    
    echo "✅ Domain created: http://$DOMAIN"
    
    # Check DNS and setup SSL
    SERVER_IP=$(curl -4 -s ifconfig.me)
    DOMAIN_IP=$(dig +short A $DOMAIN | head -1)
    
    echo ""
    echo "Checking SSL setup..."
    echo "Server IP: $SERVER_IP"
    echo "Domain IP: $DOMAIN_IP"
    
    # Advanced SSL setup with conflict detection
    setup_ssl_with_conflict_detection
    
    echo ""
    echo "========================================="
    echo "✅ SETUP COMPLETE!"
    echo "========================================="
    echo "Your website: $HTTPS_URL"
    echo "Web files: $WEB_ROOT"
    echo ""
    if [[ "$HTTPS_URL" == "http://"* ]]; then
        echo "Note: SSL failed. Check DNS points to $SERVER_IP"
    fi
    
    read -p "Press Enter to continue..."
}

# Advanced SSL setup with conflict detection (from original script)
setup_ssl_with_conflict_detection() {
    # Check for potentially conflicting sites
    echo ""
    echo "Checking for conflicting sites..."
    
    # Group sites by domain (combine HTTP and SSL versions)
    DOMAIN_GROUPS=()
    SITE_FILES=()
    
    for site in /etc/apache2/sites-enabled/*.conf; do
        if [ -f "$site" ]; then
            site_name=$(basename "$site")
            # Skip the domain we're setting up
            if [ "$site_name" != "$DOMAIN.conf" ] && [ "$site_name" != "$DOMAIN-le-ssl.conf" ]; then
                # Extract domain name (remove .conf and -le-ssl suffix)
                domain_name=$(echo "$site_name" | sed 's/-le-ssl\.conf$//' | sed 's/\.conf$//')
                
                # Check if this domain is already in our list
                found=false
                for existing_domain in "${DOMAIN_GROUPS[@]}"; do
                    if [ "$existing_domain" = "$domain_name" ]; then
                        found=true
                        break
                    fi
                done
                
                if [ "$found" = false ]; then
                    DOMAIN_GROUPS+=("$domain_name")
                fi
            fi
        fi
    done
    
    SITES_TO_DISABLE=()
    if [ ${#DOMAIN_GROUPS[@]} -gt 0 ]; then
        echo ""
        echo "Found existing domains that might interfere with SSL setup:"
        for i in "${!DOMAIN_GROUPS[@]}"; do
            echo "$((i+1))) ${DOMAIN_GROUPS[i]}"
        done
        echo "$((${#DOMAIN_GROUPS[@]}+1))) Disable ALL domains"
        echo "$((${#DOMAIN_GROUPS[@]}+2))) Continue without disabling any sites"
        echo ""
        read -p "Select domains to temporarily disable (e.g., 1 2) or press Enter to skip: " DISABLE_CHOICE
        
        if [ ! -z "$DISABLE_CHOICE" ]; then
            # Check if user wants to disable all
            if [ "$DISABLE_CHOICE" = "$((${#DOMAIN_GROUPS[@]}+1))" ]; then
                echo "Disabling all domains..."
                for domain in "${DOMAIN_GROUPS[@]}"; do
                    SITES_TO_DISABLE+=("$domain.conf")
                    SITES_TO_DISABLE+=("$domain-le-ssl.conf")
                done
            else
                # Process individual selections
                for num in $DISABLE_CHOICE; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#DOMAIN_GROUPS[@]} ]; then
                        selected_domain="${DOMAIN_GROUPS[$((num-1))]}"
                        # Add both HTTP and SSL versions of the domain to disable list
                        SITES_TO_DISABLE+=("$selected_domain.conf")
                        SITES_TO_DISABLE+=("$selected_domain-le-ssl.conf")
                    fi
                done
            fi
        fi
    fi
    
    # Disable selected sites
    if [ ${#SITES_TO_DISABLE[@]} -gt 0 ]; then
        echo ""
        echo "Temporarily disabling selected sites..."
        for site in "${SITES_TO_DISABLE[@]}"; do
            echo "Disabling $site"
            a2dissite "$site" 2>/dev/null || true
        done
        systemctl reload apache2
        sleep 2
    fi
    
    # Try SSL certificate with fallback logic
    echo ""
    echo "Requesting SSL certificate..."
    if certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" --agree-tos --email "admin@$DOMAIN" --non-interactive --quiet; then
        echo "✅ SSL certificate obtained!"
        HTTPS_URL="https://$DOMAIN"
    elif certbot --apache -d "$DOMAIN" --agree-tos --email "admin@$DOMAIN" --non-interactive --quiet; then
        echo "✅ SSL certificate obtained (main domain only)!"
        HTTPS_URL="https://$DOMAIN"
    else
        echo "⚠️  SSL failed - using HTTP only"
        HTTPS_URL="http://$DOMAIN"
    fi
    
    # Re-enable previously disabled sites
    if [ ${#SITES_TO_DISABLE[@]} -gt 0 ]; then
        echo ""
        echo "Re-enabling previously disabled sites..."
        for site in "${SITES_TO_DISABLE[@]}"; do
            echo "Re-enabling $site"
            a2ensite "$site" 2>/dev/null || true
        done
        systemctl reload apache2
    fi
}

#=============================================================================
# WEBSITE AND DATABASE REMOVAL FUNCTIONS
#=============================================================================

# Function to detect WordPress installations
detect_wordpress_sites() {
    local sites=()
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                if [ "$domain" != "html" ] && [ "$domain" != "*" ]; then
                    # Check if it's a WordPress site
                    if [ -f "$dir/wp-config.php" ] || [ -f "$dir/public_html/wp-config.php" ] || [ -f "$dir/html/wp-config.php" ]; then
                        sites+=("$domain:WordPress")
                    else
                        sites+=("$domain:Plain Apache")
                    fi
                fi
            fi
        done
    fi
    echo "${sites[@]}"
}

# Function to get WordPress database details
get_wordpress_database() {
    local site_path="$1"
    local wp_config=""
    
    # Find wp-config.php in various possible locations
    if [ -f "$site_path/wp-config.php" ]; then
        wp_config="$site_path/wp-config.php"
    elif [ -f "$site_path/public_html/wp-config.php" ]; then
        wp_config="$site_path/public_html/wp-config.php"
    elif [ -f "$site_path/html/wp-config.php" ]; then
        wp_config="$site_path/html/wp-config.php"
    fi
    
    if [ -n "$wp_config" ] && [ -f "$wp_config" ]; then
        local db_name=$(grep "DB_NAME" "$wp_config" | cut -d "'" -f 4)
        local db_user=$(grep "DB_USER" "$wp_config" | cut -d "'" -f 4)
        echo "$db_name:$db_user"
    fi
}

# Function to list all MySQL databases (excluding system databases)
list_mysql_databases() {
    mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$" || echo ""
}

# Main removal function
remove_websites_and_databases() {
    show_header
    echo -e "${RED}⚠️  WEBSITE AND DATABASE REMOVAL TOOL ⚠️${NC}"
    echo -e "${YELLOW}This tool will completely remove websites and their associated databases${NC}"
    echo
    
    # Detect all sites
    local sites_array=($(detect_wordpress_sites))
    
    if [ ${#sites_array[@]} -eq 0 ]; then
        warning_msg "No websites found in /var/www directory"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${CYAN}Available websites for removal:${NC}"
    echo
    
    # Display sites with their types
    for i in "${!sites_array[@]}"; do
        local site_info="${sites_array[i]}"
        local domain=$(echo "$site_info" | cut -d':' -f1)
        local type=$(echo "$site_info" | cut -d':' -f2)
        
        if [ "$type" = "WordPress" ]; then
            echo -e "  $((i+1))) ${GREEN}$domain${NC} (${BLUE}WordPress Site${NC})"
        else
            echo -e "  $((i+1))) ${GREEN}$domain${NC} (${YELLOW}Plain Apache Site${NC})"
        fi
    done
    
    echo
    echo -e "  $((${#sites_array[@]}+1))) ${RED}Remove ALL websites and databases${NC}"
    echo -e "  $((${#sites_array[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    
    # Handle back to menu option
    if [ "$choice" = "$((${#sites_array[@]}+2))" ]; then
        return
    fi
    
    # Handle remove all option
    if [ "$choice" = "$((${#sites_array[@]}+1))" ]; then
        remove_all_websites_and_databases "${sites_array[@]}"
        return
    fi
    
    # Validate single site selection
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sites_array[@]} ]; then
        error_msg "Invalid selection"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Remove single site
    local selected_site="${sites_array[$((choice-1))]}"
    local domain=$(echo "$selected_site" | cut -d':' -f1)
    local type=$(echo "$selected_site" | cut -d':' -f2)
    
    remove_single_website "$domain" "$type"
}

# Function to remove a single website
remove_single_website() {
    local domain="$1"
    local type="$2"
    local site_path="/var/www/$domain"
    
    echo
    echo -e "${RED}⚠️  WARNING: Complete removal of $domain${NC}"
    echo -e "${YELLOW}This will permanently delete:${NC}"
    echo "  • Website files in $site_path"
    echo "  • Apache virtual host configuration"
    echo "  • SSL certificates"
    
    if [ "$type" = "WordPress" ]; then
        local db_info=$(get_wordpress_database "$site_path")
        if [ -n "$db_info" ]; then
            local db_name=$(echo "$db_info" | cut -d':' -f1)
            local db_user=$(echo "$db_info" | cut -d':' -f2)
            echo "  • MySQL database: $db_name"
            echo "  • MySQL user: $db_user"
        fi
    fi
    
    echo
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo
    read -p "$(echo -e "${CYAN}Type 'DELETE' to confirm removal: ${NC}")" confirm
    
    if [ "$confirm" != "DELETE" ]; then
        warning_msg "Removal cancelled"
        read -p "Press Enter to continue..."
        return
    fi
    
    info_msg "Starting removal of $domain..."
    
    # Remove Apache configuration
    info_msg "Removing Apache configuration..."
    
    # Disable sites first
    if [ -f "/etc/apache2/sites-enabled/$domain.conf" ]; then
        a2dissite "$domain.conf" 2>/dev/null || true
    fi
    if [ -f "/etc/apache2/sites-enabled/$domain-le-ssl.conf" ]; then
        a2dissite "$domain-le-ssl.conf" 2>/dev/null || true
    fi
    
    # Remove configuration files
    rm -f "/etc/apache2/sites-available/$domain.conf"
    rm -f "/etc/apache2/sites-available/$domain-le-ssl.conf"
    
    # Test Apache configuration before reloading
    if ! apache2ctl configtest 2>/dev/null; then
        warning_msg "Apache configuration test failed, attempting to fix..."
        # Remove any broken symlinks
        find /etc/apache2/sites-enabled/ -type l ! -exec test -e {} \; -delete 2>/dev/null || true
    fi
    
    # Remove SSL certificates and all related files
    info_msg "Removing SSL certificates..."
    
    # Remove via certbot (removes most files)
    certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
    
    # Manual cleanup of any remaining SSL files
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        rm -rf "/etc/letsencrypt/live/$domain" 2>/dev/null || true
    fi
    if [ -d "/etc/letsencrypt/archive/$domain" ]; then
        rm -rf "/etc/letsencrypt/archive/$domain" 2>/dev/null || true
    fi
    if [ -f "/etc/letsencrypt/renewal/$domain.conf" ]; then
        rm -f "/etc/letsencrypt/renewal/$domain.conf" 2>/dev/null || true
    fi
    
    # Also check for www variant
    if [ -d "/etc/letsencrypt/live/www.$domain" ]; then
        rm -rf "/etc/letsencrypt/live/www.$domain" 2>/dev/null || true
    fi
    if [ -d "/etc/letsencrypt/archive/www.$domain" ]; then
        rm -rf "/etc/letsencrypt/archive/www.$domain" 2>/dev/null || true
    fi
    if [ -f "/etc/letsencrypt/renewal/www.$domain.conf" ]; then
        rm -f "/etc/letsencrypt/renewal/www.$domain.conf" 2>/dev/null || true
    fi
    
    # Remove database if WordPress
    if [ "$type" = "WordPress" ]; then
        local db_info=$(get_wordpress_database "$site_path")
        if [ -n "$db_info" ]; then
            local db_name=$(echo "$db_info" | cut -d':' -f1)
            local db_user=$(echo "$db_info" | cut -d':' -f2)
            
            info_msg "Removing MySQL database and user..."
            mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || true
            mysql -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null || true
            mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        fi
    fi
    
    # Remove website files
    info_msg "Removing website files..."
    rm -rf "$site_path"
    
    # Reload Apache with error handling
    info_msg "Reloading Apache..."
    if apache2ctl configtest 2>/dev/null; then
        if systemctl reload apache2; then
            success_msg "Apache reloaded successfully"
        else
            warning_msg "Apache reload failed, attempting restart..."
            if systemctl restart apache2; then
                success_msg "Apache restarted successfully"
            else
                error_exit "Apache restart failed. Please check configuration manually."
            fi
        fi
    else
        warning_msg "Apache configuration test failed. Fixing configuration..."
        # Remove any remaining broken configurations
        find /etc/apache2/sites-enabled/ -type l ! -exec test -e {} \; -delete 2>/dev/null || true
        
        if apache2ctl configtest 2>/dev/null; then
            systemctl reload apache2 && success_msg "Apache configuration fixed and reloaded"
        else
            error_exit "Apache configuration still has errors. Please check manually with 'apache2ctl configtest'"
        fi
    fi
    
    success_msg "Website $domain has been completely removed!"
    read -p "Press Enter to continue..."
}

# Function to remove all websites and databases
remove_all_websites_and_databases() {
    local sites_array=("$@")
    
    echo
    echo -e "${RED}⚠️  EXTREME WARNING: COMPLETE SYSTEM CLEANUP ⚠️${NC}"
    echo -e "${YELLOW}This will remove ALL websites and databases:${NC}"
    echo
    
    for site_info in "${sites_array[@]}"; do
        local domain=$(echo "$site_info" | cut -d':' -f1)
        local type=$(echo "$site_info" | cut -d':' -f2)
        echo "  • $domain ($type)"
    done
    
    echo
    echo -e "${RED}ALL WEBSITE DATA AND DATABASES WILL BE PERMANENTLY LOST!${NC}"
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo
    read -p "$(echo -e "${CYAN}Type 'DELETE ALL' to confirm complete removal: ${NC}")" confirm
    
    if [ "$confirm" != "DELETE ALL" ]; then
        warning_msg "Mass removal cancelled"
        read -p "Press Enter to continue..."
        return
    fi
    
    info_msg "Starting complete website and database removal..."
    
    # Remove each site
    for site_info in "${sites_array[@]}"; do
        local domain=$(echo "$site_info" | cut -d':' -f1)
        local type=$(echo "$site_info" | cut -d':' -f2)
        
        info_msg "Removing $domain..."
        
        # Remove Apache configuration
        if [ -f "/etc/apache2/sites-enabled/$domain.conf" ]; then
            a2dissite "$domain.conf" 2>/dev/null || true
        fi
        if [ -f "/etc/apache2/sites-enabled/$domain-le-ssl.conf" ]; then
            a2dissite "$domain-le-ssl.conf" 2>/dev/null || true
        fi
        rm -f "/etc/apache2/sites-available/$domain.conf"
        rm -f "/etc/apache2/sites-available/$domain-le-ssl.conf"
        
        # Remove SSL certificates and all related files
        certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
        
        # Manual cleanup of any remaining SSL files
        rm -rf "/etc/letsencrypt/live/$domain" 2>/dev/null || true
        rm -rf "/etc/letsencrypt/archive/$domain" 2>/dev/null || true
        rm -f "/etc/letsencrypt/renewal/$domain.conf" 2>/dev/null || true
        rm -rf "/etc/letsencrypt/live/www.$domain" 2>/dev/null || true
        rm -rf "/etc/letsencrypt/archive/www.$domain" 2>/dev/null || true
        rm -f "/etc/letsencrypt/renewal/www.$domain.conf" 2>/dev/null || true
        
        # Remove database if WordPress
        if [ "$type" = "WordPress" ]; then
            local site_path="/var/www/$domain"
            local db_info=$(get_wordpress_database "$site_path")
            if [ -n "$db_info" ]; then
                local db_name=$(echo "$db_info" | cut -d':' -f1)
                local db_user=$(echo "$db_info" | cut -d':' -f2)
                
                mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || true
                mysql -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null || true
            fi
        fi
        
        # Remove website files
        rm -rf "/var/www/$domain"
    done
    
    # Clean up any remaining WordPress databases
    info_msg "Cleaning up any remaining WordPress databases..."
    local all_dbs=$(list_mysql_databases)
    for db in $all_dbs; do
        # Check if database might be WordPress (common patterns)
        if [[ "$db" =~ ^(wp_|wordpress_|.*_wp).*$ ]]; then
            if confirm "Remove database '$db' (appears to be WordPress)?"; then
                mysql -e "DROP DATABASE IF EXISTS \`$db\`;" 2>/dev/null || true
            fi
        fi
    done
    
    # Flush MySQL privileges
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    # Clean up any broken Apache configurations
    info_msg "Cleaning up Apache configuration..."
    find /etc/apache2/sites-enabled/ -type l ! -exec test -e {} \; -delete 2>/dev/null || true
    
    # Reload Apache with error handling
    info_msg "Reloading Apache..."
    if apache2ctl configtest 2>/dev/null; then
        if systemctl reload apache2; then
            success_msg "Apache reloaded successfully"
        else
            warning_msg "Apache reload failed, attempting restart..."
            if systemctl restart apache2; then
                success_msg "Apache restarted successfully"
            else
                error_exit "Apache restart failed. Please check configuration manually."
            fi
        fi
    else
        warning_msg "Apache configuration test failed. Fixing configuration..."
        # Remove any remaining broken configurations
        find /etc/apache2/sites-enabled/ -type l ! -exec test -e {} \; -delete 2>/dev/null || true
        
        if apache2ctl configtest 2>/dev/null; then
            systemctl reload apache2 && success_msg "Apache configuration fixed and reloaded"
        else
            error_exit "Apache configuration still has errors. Please check manually with 'apache2ctl configtest'"
        fi
    fi
    
    success_msg "All websites and databases have been completely removed!"
    warning_msg "Your server is now clean of all website data"
    read -p "Press Enter to continue..."
}

remove_existing_domain() {
    # Legacy function - redirect to new comprehensive removal tool
    remove_websites_and_databases
}

#=============================================================================
# PHPMYADMIN INSTALLATION
#=============================================================================

install_phpmyadmin() {
    show_header
    echo -e "${YELLOW}phpMyAdmin Installation${NC}"
    echo
    
    read -p "Enter web directory path (default: /var/www): " WP_DIR
    [[ -z "$WP_DIR" ]] && WP_DIR="/var/www"
    
    if [ ! -d "$WP_DIR" ]; then
        error_exit "Directory $WP_DIR does not exist"
    fi
    
    info_msg "Installing phpMyAdmin..."
    
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    
    # Pre-configure phpMyAdmin
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password " | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password " | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password " | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    
    # Install phpMyAdmin
    apt update -y
    apt install phpmyadmin -y || error_exit "Failed to install phpMyAdmin"
    
    # Create symlink
    info_msg "Creating symlink..."
    ln -sf /usr/share/phpmyadmin "$WP_DIR/phpmyadmin" || error_exit "Failed to create symlink"
    
    # Enable Apache configuration
    a2enconf phpmyadmin || warning_msg "Failed to enable phpMyAdmin configuration"
    
    # Restart Apache
    systemctl restart apache2 || error_exit "Failed to restart Apache"
    
    success_msg "phpMyAdmin installation completed!"
    echo -e "${GREEN}You can access phpMyAdmin at: http://your-domain/phpmyadmin${NC}"
    echo -e "${YELLOW}Note: Use your MySQL root credentials to login${NC}"
    
    read -p "Press Enter to continue..."
}

#=============================================================================
# BACKUP FUNCTIONS
#=============================================================================

backup_wordpress() {
    show_header
    echo -e "${YELLOW}WordPress Backup Tool${NC}"
    echo
    
    local WWW_PATH="/var/www"
    local BACKUP_DIR="/website_backups"
    local TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    
    info_msg "Starting WordPress backup process..."
    
    # Check if WWW_PATH exists
    if [ ! -d "$WWW_PATH" ]; then
        error_exit "WWW_PATH ($WWW_PATH) does not exist!"
    fi
    
    # Function to check if a directory is a WordPress installation
    is_wordpress() {
        if [ -f "$1/wp-config.php" ]; then
            return 0
        else
            return 1
        fi
    }
    
    # Function to backup WordPress site
    backup_wordpress_site() {
        local site_path="$1"
        local site_name="$2"
        
        info_msg "Starting WordPress backup for: $site_name"
        
        # Create database dump
        local db_dump_name="${site_name}_db.sql"
        
        if wp core is-installed --path="$site_path" --allow-root 2>/dev/null; then
            info_msg "Exporting database for $site_name"
            wp db export "$site_path/$db_dump_name" --path="$site_path" --allow-root || {
                warning_msg "Database export failed for $site_name"
            }
        else
            warning_msg "WordPress not properly installed in $site_name"
        fi
        
        # Create backup
        local backup_name="${site_name}_backup_${TIMESTAMP}.tar.gz"
        info_msg "Creating tar archive for $site_name"
        
        pushd "$WWW_PATH" > /dev/null || error_exit "Cannot change to www directory"
        
        # Exclude cache directories and handle file changes during backup
        tar --warning=no-file-changed -czf "$BACKUP_DIR/$backup_name" \
            --exclude="$site_name/wp-content/cache" \
            --exclude="$site_name/wp-content/wpo-cache" \
            --exclude="$site_name/wp-content/uploads/cache" \
            --exclude="$site_name/wp-content/plugins/*/cache" \
            "$site_name" || {
            local tar_exit=$?
            if [ $tar_exit -ne 0 ] && [ $tar_exit -ne 1 ]; then
                popd > /dev/null
                error_exit "Tar backup failed for $site_name"
            fi
        }
        popd > /dev/null
        
        # Cleanup database dump
        if [ -f "$site_path/$db_dump_name" ]; then
            rm -f "$site_path/$db_dump_name"
        fi
        
        success_msg "Backup completed for $site_name: $backup_name"
    }
    
    # Install WP-CLI if not available
    if ! command -v wp &> /dev/null; then
        info_msg "Installing WP-CLI..."
        install_wp_cli
    fi
    
    # Iterate through all directories in www path
    local backup_count=0
    for site_dir in "$WWW_PATH"/*; do
        if [ -d "$site_dir" ]; then
            site_name=$(basename "$site_dir")
            
            # Skip the html directory
            if [ "$site_name" = "html" ]; then
                info_msg "Skipping html directory"
                continue
            fi
            
            info_msg "Processing site: $site_name"
            
            if is_wordpress "$site_dir"; then
                backup_wordpress_site "$site_dir" "$site_name"
                ((backup_count++))
            else
                warning_msg "$site_name is not a WordPress installation"
            fi
        fi
    done
    
    # Cleanup old backups (keep last 7 days)
    info_msg "Cleaning up old backups..."
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +7 -delete
    
    if [ $backup_count -eq 0 ]; then
        warning_msg "No WordPress sites found to backup"
    else
        success_msg "Backup process completed. $backup_count sites backed up."
        echo -e "${GREEN}Backups stored in: $BACKUP_DIR${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# WordPress Restore Function
restore_wordpress() {
    show_header
    echo -e "${YELLOW}WordPress Restore Tool${NC}"
    echo
    
    local WWW_PATH="/var/www"
    local BACKUP_DIR="/website_backups"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="/var/log/website_restore_${TIMESTAMP}.log"
    
    # Install WP-CLI if not available
    if ! command -v wp &> /dev/null; then
        info_msg "Installing WP-CLI..."
        install_wp_cli
    fi
    
    # Function to check if a backup is WordPress
    is_wordpress_backup() {
        local backup_file="$1"
        tar -tzf "$backup_file" | grep -q "wp-config.php"
        return $?
    }
    
    # Function to list backups with serial numbers
    list_and_store_backups() {
        echo -e "${YELLOW}Available backups:${NC}"
        echo "----------------"
        
        readarray -t backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -type f | sort)
        
        if [ ${#backup_files[@]} -eq 0 ]; then
            echo "No backups found in $BACKUP_DIR"
            return 1
        fi
        
        for i in "${!backup_files[@]}"; do
            filename=$(basename "${backup_files[$i]}")
            echo "[$((i+1))] $filename"
        done
        
        return 0
    }
    
    # Function to restore WordPress site
    restore_wordpress_site() {
        local backup_file="$1"
        local site_name="$2"
        local target_dir="$WWW_PATH/$site_name"
        
        info_msg "Starting WordPress restoration for: $site_name"
        
        # Create target directory if it doesn't exist
        mkdir -p "$target_dir" || error_exit "Failed to create target directory"
        
        # Extract backup
        info_msg "Extracting backup archive"
        tar -xzf "$backup_file" -C "$WWW_PATH" || error_exit "Failed to extract backup"
        
        # Remove problematic files immediately after extraction
        info_msg "Removing problematic files..."
        rm -f "$target_dir/wp-content/object-cache.php"
        rm -f "$target_dir/wp-content/advanced-cache.php"
        
        # Find database dump in the extracted files
        local db_dump=""
        for possible_dump in "$target_dir"/*_db.sql "$target_dir"/wordpress_db.sql "$target_dir"/*.sql; do
            if [ -f "$possible_dump" ]; then
                db_dump="$possible_dump"
                break
            fi
        done
        
        if [ -n "$db_dump" ]; then
            info_msg "Found database dump: $db_dump"
            
            if [ -f "$target_dir/wp-config.php" ]; then
                # Add direct filesystem access
                info_msg "Configuring filesystem access..."
                sed -i "/^require_once/i define('FS_METHOD', 'direct');" "$target_dir/wp-config.php"
                
                # Enable debug mode
                info_msg "Enabling debug mode..."
                sed -i "/'WP_DEBUG'/d" "$target_dir/wp-config.php"
                sed -i "/^define('FS_METHOD'/a define('WP_DEBUG', true);\ndefine('WP_DEBUG_LOG', true);\ndefine('WP_DEBUG_DISPLAY', false);" "$target_dir/wp-config.php"
                
                info_msg "Importing database..."
                wp db import "$db_dump" --path="$target_dir" --allow-root
                if [ $? -eq 0 ]; then
                    success_msg "Database import successful"
                    rm -f "$db_dump"
                    
                    # Deactivate problematic plugins
                    info_msg "Deactivating problematic plugins..."
                    wp plugin deactivate redis-cache wp-optimize w3-total-cache wp-super-cache --path="$target_dir" --allow-root 2>/dev/null || info_msg "Note: Some plugins were already inactive"
                    
                    # Update WordPress core
                    info_msg "Updating WordPress core..."
                    wp core update --path="$target_dir" --allow-root || warning_msg "Core update failed"
                    
                    # Clear caches
                    info_msg "Clearing caches..."
                    wp rewrite flush --path="$target_dir" --allow-root || warning_msg "Rewrite flush failed"
                else
                    warning_msg "Database import failed, but continuing with restoration"
                fi
            else
                warning_msg "wp-config.php not found, skipping database import"
            fi
        else
            warning_msg "No database dump found in backup"
        fi
        
        # Fix permissions
        info_msg "Setting correct permissions"
        chown -R www-data:www-data "$target_dir"
        chmod 755 "$target_dir"
        
        success_msg "Restoration completed for $site_name"
    }
    
    # Main restoration process
    info_msg "Starting restoration process"
    
    if ! list_and_store_backups; then
        read -p "Press Enter to continue..."
        return
    fi
    
    echo
    read -p "Enter the number of the backup you want to restore: " backup_number
    
    if ! [[ "$backup_number" =~ ^[0-9]+$ ]] || \
       [ "$backup_number" -lt 1 ] || \
       [ "$backup_number" -gt ${#backup_files[@]} ]; then
        error_exit "Invalid backup number selected"
    fi
    
    selected_backup="${backup_files[$((backup_number-1))]}"
    info_msg "Selected backup: $(basename "$selected_backup")"
    
    read -p "Enter the target site name for restoration: " TARGET_SITE
    
    if [ -d "$WWW_PATH/$TARGET_SITE" ]; then
        echo -e "${RED}Target directory already exists.${NC}"
        if confirm "Do you want to overwrite?"; then
            info_msg "Removing existing directory"
            rm -rf "$WWW_PATH/$TARGET_SITE"
        else
            info_msg "Restoration cancelled by user"
            read -p "Press Enter to continue..."
            return
        fi
    fi
    
    if is_wordpress_backup "$selected_backup"; then
        restore_wordpress_site "$selected_backup" "$TARGET_SITE"
        success_msg "Restoration process completed successfully"
    else
        error_exit "Selected backup is not a WordPress backup"
    fi
    
    read -p "Press Enter to continue..."
}

#=============================================================================
# POSTGRESQL BACKUP AND RESTORE FUNCTIONS
#=============================================================================

backup_postgresql() {
    show_header
    echo -e "${YELLOW}PostgreSQL Backup Tool${NC}"
    echo
    
    # Configuration
    read -p "Enter database name (default: your_db): " DB_NAME
    [[ -z "$DB_NAME" ]] && DB_NAME="your_db"
    
    read -p "Enter database user (default: your_user): " DB_USER
    [[ -z "$DB_USER" ]] && DB_USER="your_user"
    
    read -sp "Enter database password: " DB_PASS
    echo
    
    local BACKUP_DIR="/website_backups/postgres"
    local BACKUP_RETENTION_DAYS=30
    
    info_msg "Starting PostgreSQL backup..."
    
    # Install PostgreSQL if not installed
    if ! command -v psql &>/dev/null; then
        info_msg "Installing PostgreSQL..."
        apt update -y && apt install -y postgresql postgresql-contrib || error_exit "Failed to install PostgreSQL"
    fi
    
    # Start PostgreSQL if not running
    info_msg "Checking PostgreSQL status..."
    systemctl is-active --quiet postgresql || systemctl start postgresql || error_exit "Failed to start PostgreSQL"
    
    # Ensure backup directory exists and set permissions
    info_msg "Setting up backup directory..."
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    chown postgres:postgres "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    
    # Perform backup
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local dump_backup="$BACKUP_DIR/${DB_NAME}_${timestamp}.dump"
    
    info_msg "Creating PostgreSQL backup..."
    sudo -u postgres pg_dump -Fc "$DB_NAME" -f "$dump_backup" || error_exit "Backup failed"
    
    # Clean old backups
    info_msg "Cleaning up old backups..."
    find "$BACKUP_DIR" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
    
    success_msg "Backup completed successfully!"
    echo -e "${GREEN}Backup file: $dump_backup${NC}"
    
    read -p "Press Enter to continue..."
}

restore_postgresql() {
    show_header
    echo -e "${YELLOW}PostgreSQL Restore Tool${NC}"
    echo
    
    # Configuration
    read -p "Enter database name (default: your_db): " DB_NAME
    [[ -z "$DB_NAME" ]] && DB_NAME="your_db"
    
    read -p "Enter database user (default: your_user): " DB_USER
    [[ -z "$DB_USER" ]] && DB_USER="your_user"
    
    read -sp "Enter database password: " DB_PASS
    echo
    
    local BACKUP_DIR="/website_backups/postgres"
    
    # Find the most recent dump file
    local DUMP_FILE=$(find "$BACKUP_DIR" -name "*.dump" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -n 1 | awk '{print $2}')
    
    # Check if a dump file was found
    if [ -z "$DUMP_FILE" ]; then
        echo -e "${RED}No dump file found in $BACKUP_DIR${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    info_msg "Found backup file: $DUMP_FILE"
    
    # Install PostgreSQL if not installed
    if ! command -v psql &>/dev/null; then
        info_msg "Installing PostgreSQL..."
        apt update -y
        apt install -y postgresql postgresql-contrib || error_exit "Failed to install PostgreSQL"
    fi
    
    # Start and enable PostgreSQL service
    info_msg "Starting PostgreSQL service..."
    systemctl start postgresql
    systemctl enable postgresql
    
    # Setup database and user
    info_msg "Setting up database and user..."
    sudo -u postgres psql <<EOF
-- Drop database if it exists
DROP DATABASE IF EXISTS $DB_NAME;

-- Create database
CREATE DATABASE $DB_NAME;

-- Drop user if it exists and recreate
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    # Restore the dump file
    info_msg "Restoring the database from dump..."
    sudo -u postgres pg_restore --clean --if-exists -d "$DB_NAME" "$DUMP_FILE" || warning_msg "Some restore warnings occurred"
    
    # Verify database
    info_msg "Verifying database..."
    sudo -u postgres psql -d "$DB_NAME" -c "\dt"
    
    success_msg "Database restoration completed successfully!"
    
    read -p "Press Enter to continue..."
}

#=============================================================================
# TRANSFER BACKUPS AND SYSTEM MANAGEMENT FUNCTIONS
#=============================================================================

transfer_backups() {
    show_header
    echo -e "${YELLOW}Transfer Backups from Old Server${NC}"
    echo
    
    read -p "Are you on the source/old server? (yes/no): " ON_SOURCE_SERVER
    if [[ "$ON_SOURCE_SERVER" != "yes" ]]; then
        echo -e "${RED}Please run this script on the source/old server.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter the destination IP address: " DEST_IP
    if [ -z "$DEST_IP" ]; then
        error_exit "Destination IP address required!"
    fi
    
    local DEST_BACKUP_DIR="/website_backups"
    local SOURCE_BACKUP_DIR="/website_backups"
    
    if [ ! -d "$SOURCE_BACKUP_DIR" ]; then
        error_exit "Source backup directory $SOURCE_BACKUP_DIR does not exist!"
    fi
    
    info_msg "Transferring backups to $DEST_IP"
    
    # Create directory on destination
    ssh root@"$DEST_IP" "mkdir -p $DEST_BACKUP_DIR" || error_exit "Failed to create directory on destination"
    
    # Transfer files
    rsync -avz --progress "$SOURCE_BACKUP_DIR/" root@"$DEST_IP":"$DEST_BACKUP_DIR" || error_exit "Transfer failed"
    
    success_msg "Backup transfer completed!"
    read -p "Press Enter to continue..."
}

adjust_php_config() {
    show_header
    echo -e "${YELLOW}PHP Configuration Adjustment${NC}"
    echo
    
    # Get PHP version
    local PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    
    if [ -z "$PHP_VERSION" ]; then
        error_exit "PHP is not installed"
    fi
    
    info_msg "Detected PHP version: $PHP_VERSION"
    
    # Modify php.ini files
    for ini_file in "/etc/php/$PHP_VERSION/cli/php.ini" "/etc/php/$PHP_VERSION/apache2/php.ini" "/etc/php/$PHP_VERSION/fpm/php.ini"; do
        if [ -f "$ini_file" ]; then
            info_msg "Modifying $ini_file"
            sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$ini_file"
            sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$ini_file"
            sed -i "s/^memory_limit = .*/memory_limit = 512M/" "$ini_file"
            sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$ini_file"
            sed -i "s/^max_input_time = .*/max_input_time = 300/" "$ini_file"
        fi
    done
    
    # Restart services
    systemctl restart apache2 2>/dev/null || true
    systemctl restart php"$PHP_VERSION"-fpm 2>/dev/null || true
    
    success_msg "PHP configuration updated!"
    read -p "Press Enter to continue..."
}

configure_redis() {
    show_header
    echo -e "${YELLOW}Redis Configuration${NC}"
    echo
    
    read -p "Enter Redis maximum memory in GB (default: 1): " REDIS_MAX_MEMORY
    [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    
    info_msg "Configuring Redis with ${REDIS_MAX_MEMORY}GB memory limit..."
    
    # Install Redis if not installed
    if ! command -v redis-server &> /dev/null; then
        info_msg "Installing Redis..."
        apt update -y
        apt install redis-server -y || error_exit "Failed to install Redis"
    fi
    
    # Configure Redis memory
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    
    # Restart Redis
    systemctl restart redis-server || error_exit "Failed to restart Redis"
    systemctl enable redis-server
    
    success_msg "Redis configured with ${REDIS_MAX_MEMORY}GB memory limit"
    read -p "Press Enter to continue..."
}

ssh_security_management() {
    show_header
    echo -e "${YELLOW}SSH Security Management${NC}"
    echo
    echo "1) Disable root SSH login"
    echo "2) Enable root SSH login"
    echo "3) Back to Main Menu"
    echo
    
    read -p "$(echo -e "${CYAN}Choose option (1-3): ${NC}")" ssh_choice
    
    case $ssh_choice in
        1)
            info_msg "Disabling root SSH login..."
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null || true
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config 2>/dev/null || true
            systemctl restart ssh
            success_msg "Root SSH login disabled"
            ;;
        2)
            info_msg "Enabling root SSH login..."
            sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null || true
            sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config 2>/dev/null || true
            systemctl restart ssh
            success_msg "Root SSH login enabled"
            ;;
        3) return ;;
        *) 
            echo -e "${RED}Invalid option${NC}"
            sleep 2
            ssh_security_management
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

system_utilities() {
    show_header
    echo -e "${YELLOW}System Utilities${NC}"
    echo
    
    # Get swap size
    read -p "Enter swap file size in GB (default: 2): " SWAP_SIZE
    [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="2"
    
    # System update
    if confirm "Update the system?"; then
        info_msg "Updating system..."
        apt update && apt upgrade -y || warning_msg "System update failed"
    fi
    
    # UFW Firewall
    if confirm "Install and configure UFW firewall?"; then
        info_msg "Installing UFW firewall..."
        apt install ufw -y
        ufw --force enable
        ufw allow OpenSSH
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 3306
        success_msg "UFW firewall configured"
    fi
    
    # Fail2ban
    if confirm "Install Fail2ban?"; then
        info_msg "Installing Fail2ban..."
        apt install fail2ban -y
        systemctl enable fail2ban
        systemctl start fail2ban
        success_msg "Fail2ban installed and started"
    fi
    
    # Swap file
    if confirm "Setup swap file?"; then
        info_msg "Setting up ${SWAP_SIZE}GB swap file..."
        fallocate -l "${SWAP_SIZE}G" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        success_msg "Swap file created"
    fi
    
    # Additional utilities
    if confirm "Install additional utilities (plocate, rclone, pv, rsync)?"; then
        info_msg "Installing additional utilities..."
        apt install -y plocate rclone pv rsync || warning_msg "Some utilities failed to install"
        success_msg "Additional utilities installed"
    fi
    
    success_msg "System utilities configuration completed!"
    read -p "Press Enter to continue..."
}

#=============================================================================
# TROUBLESHOOTING AND GUIDES
#=============================================================================

show_troubleshooting_guide() {
    show_header
    echo -e "${YELLOW}Troubleshooting Guide${NC}"
    echo
    
    cat << 'EOF'
1. If wp-admin fails to load after restoration:
   a) Deactivate all plugins via WP CLI:
      wp plugin deactivate --all --allow-root --path=/var/www/your_website.com
   
   b) Manually remove broken plugins:
      rm -rf /var/www/your_website.com/wp-content/plugins/plugin_name
   
   c) Reactivate plugins:
      wp plugin activate --all --path=/var/www/your_website.com --allow-root

2. Check service status:
   Apache:  sudo systemctl status apache2
   MySQL:   sudo systemctl status mysql
   PHP-FPM: systemctl status php8.3-fpm

3. Check system resources:
   RAM:        free -h
   Disk:       df -h
   Directory:  du -sh /var/lib/mysql

4. Check logs:
   Apache error:     tail -n 20 /var/log/apache2/error.log
   Site specific:    tail -n 50 /var/log/apache2/error_your_website.com.log
   WordPress debug:  tail -n 20 /var/www/your_site/wp-content/debug.log

5. Enable WordPress debug mode (add to wp-config.php):
   define('WP_DEBUG', true);
   define('WP_DEBUG_LOG', true);
   define('WP_DEBUG_DISPLAY', false);

6. If MySQL binary logs are too large:
   mysql -u root -p
   SHOW BINARY LOGS;
   RESET MASTER;
   EXIT;

7. Redis connection errors:
   Delete: /var/www/your_site/wp-content/object-cache.php
EOF
    
    echo
    read -p "Press Enter to continue..."
}

mysql_commands_guide() {
    show_header
    echo -e "${YELLOW}MySQL Database Commands Guide${NC}"
    echo
    
    cat << 'EOF'
Access MySQL database:
  sudo mysql -u root -p

Check existing databases:
  SHOW DATABASES;

Check existing users:
  SELECT User FROM mysql.user;

Login to specific database:
  mysql -u database_username -p database_name

Check WordPress URLs in database:
  SELECT option_name, option_value FROM wp_options 
  WHERE option_name IN ('siteurl', 'home');

Check database size:
  SELECT table_schema AS "Database",
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size (MB)"
  FROM information_schema.tables
  WHERE table_schema = "database_name"
  GROUP BY table_schema;

Exit MySQL:
  EXIT;
EOF
    
    echo
    read -p "Press Enter to continue..."
}

system_status_check() {
    show_header
    echo -e "${YELLOW}System Status Check${NC}"
    echo
    
    info_msg "Checking system status..."
    echo
    
    # System information
    echo -e "${CYAN}=== System Information ===${NC}"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo
    
    # Resource usage
    echo -e "${CYAN}=== Resource Usage ===${NC}"
    echo "Memory:"
    free -h
    echo
    echo "Disk Usage:"
    df -h | grep -E '^/dev/'
    echo
    
    # Service status
    echo -e "${CYAN}=== Service Status ===${NC}"
    services=("apache2" "mysql" "redis-server")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "$service: ${GREEN}Running${NC}"
        else
            echo -e "$service: ${RED}Stopped${NC}"
        fi
    done
    echo
    
    # Network status
    echo -e "${CYAN}=== Network Status ===${NC}"
    echo "Active connections:"
    ss -tuln | grep -E ':(80|443|3306|22)\s'
    echo
    
    # WordPress sites
    echo -e "${CYAN}=== WordPress Sites ===${NC}"
    if [ -d "/var/www" ]; then
        for site in /var/www/*; do
            if [ -d "$site" ] && [ -f "$site/wp-config.php" ]; then
                site_name=$(basename "$site")
                echo -e "WordPress site found: ${GREEN}$site_name${NC}"
            fi
        done
    fi
    
    echo
    read -p "Press Enter to continue..."
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    check_root
    check_system
    load_config
    
    while true; do
        show_main_menu
        read -p "$(echo -e "${CYAN}Please select an option (1-17): ${NC}")" choice
        
        case $choice in
            1) install_lamp_wordpress ;;
            2) install_apache_ssl_only ;;
            3) install_phpmyadmin ;;
            4) backup_wordpress ;;
            5) restore_wordpress ;;
            6) backup_postgresql ;;
            7) restore_postgresql ;;
            8) transfer_backups ;;
            9) adjust_php_config ;;
            10) configure_redis ;;
            11) ssh_security_management ;;
            12) system_utilities ;;
            13) remove_websites_and_databases ;;
            14) show_troubleshooting_guide ;;
            15) mysql_commands_guide ;;
            16) system_status_check ;;
            17) 
                echo -e "${GREEN}Thank you for using WordPress Master!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Start the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
