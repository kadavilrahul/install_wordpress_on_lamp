#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_cli_$(date +%Y%m%d_%H%M%S).log"

# Get script directory (handle symlinks)
if [ -L "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CONFIG_FILE="$SCRIPT_DIR/../config.json"

# Source WSL functions if available
if [ -f "$SCRIPT_DIR/../wsl/wsl_functions.sh" ]; then
    source "$SCRIPT_DIR/../wsl/wsl_functions.sh"
    source "$SCRIPT_DIR/../wsl/wsl_completion.sh"
    
    # Initialize environment if not already done
    if [[ -z "$ENVIRONMENT_MODE" ]]; then
        set_environment_mode "auto"
    fi
fi

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }

# Check root
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Load configuration
load_config() {
    local config_path="$CONFIG_FILE"
    if [ -f "$config_path" ]; then
        ADMIN_EMAIL=$(jq -r '.admin_email // ""' "$config_path")
        DB_ROOT_PASSWORD=$(jq -r '.mysql_root_password // ""' "$config_path")
        REDIS_MAX_MEMORY=$(jq -r '.redis_max_memory // "1"' "$config_path")
    fi
}

# Save configuration
save_config() {
    local temp_file=$(mktemp)
    local domain_type="main_domains"
    [[ "$DOMAIN" == *"."*"."* ]] && domain_type="subdomains"
    [[ "$DOMAIN" == *"/"* ]] && domain_type="subdirectory_domains"

    local config_path="$CONFIG_FILE"
    [ ! -f "$config_path" ] && echo '{"main_domains":[],"subdomains":[],"subdirectory_domains":[],"mysql_root_password":"","admin_email":"","redis_max_memory":"1"}' > "$config_path"

    local current_email="${ADMIN_EMAIL}"
    local current_redis="${REDIS_MAX_MEMORY}"
    local current_pass="${DB_ROOT_PASSWORD}"
    
    [ -z "$current_email" ] && current_email=$(jq -r '.admin_email // ""' "$config_path")
    [ -z "$current_redis" ] && current_redis=$(jq -r '.redis_max_memory // "1"' "$config_path")
    [ -z "$current_pass" ] && current_pass=$(jq -r '.mysql_root_password // ""' "$config_path")

    jq --arg email "$current_email" \
       --arg redis "$current_redis" \
       --arg pass "$current_pass" \
       --arg domain "$DOMAIN" \
       --arg type "$domain_type" \
       '. + {
           admin_email: $email,
           redis_max_memory: $redis,
           mysql_root_password: $pass
       } | .[$type] = (.[$type] + [$domain] | unique)' \
       "$config_path" > "$temp_file" && mv "$temp_file" "$config_path"
    success "Configuration saved"
}

# Verify Apache installation
verify_apache_installed() {
    if command -v apache2 &>/dev/null && systemctl is-active --quiet apache2; then
        if [ -d "/etc/apache2" ] && [ -f "/etc/apache2/apache2.conf" ]; then
            return 0
        fi
    fi
    return 1
}

# Verify MySQL installation
verify_mysql_installed() {
    if command -v mysql &>/dev/null && systemctl is-active --quiet mysql; then
        if mysql -e "SELECT 1;" &>/dev/null || mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Verify PHP installation
verify_php_installed() {
    if command -v php &>/dev/null; then
        if apache2ctl -M 2>/dev/null | grep -q php; then
            return 0
        fi
    fi
    return 1
}

# Install missing components
install_lamp_components() {
    export DEBIAN_FRONTEND=noninteractive
    local need_install=false
    
    info "Checking LAMP stack components..."
    
    if ! verify_apache_installed; then
        info "Apache not found or not running, will install"
        need_install=true
    else
        success "Apache already installed and running"
    fi
    
    if ! verify_mysql_installed; then
        info "MySQL not found or not running, will install"
        need_install=true
    else
        success "MySQL already installed and running"
    fi
    
    if ! verify_php_installed; then
        info "PHP not found or not loaded, will install"
        need_install=true
    else
        success "PHP already installed and loaded"
    fi
    
    if [ "$need_install" = false ]; then
        success "All LAMP components already installed"
        return 0
    fi
    
    info "Installing missing LAMP components..."
    
    # Update system
    apt update -y || warn "apt update had warnings"
    
    # Install Apache if needed
    if ! verify_apache_installed; then
        info "Installing Apache..."
        apt install -y apache2 || error "Failed to install Apache"
        systemctl enable apache2
        systemctl start apache2
    fi
    
    # Install MySQL if needed
    if ! verify_mysql_installed; then
        info "Installing MySQL..."
        apt install -y mysql-server || error "Failed to install MySQL"
        systemctl enable mysql
        systemctl start mysql
        
        # Set MySQL password
        sleep 3
        if mysql -e "SELECT 1;" &>/dev/null; then
            mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD';" &>/dev/null
            success "MySQL root password set"
        fi
    fi
    
    # Install PHP if needed
    if ! verify_php_installed; then
        info "Installing PHP..."
        apt install -y php libapache2-mod-php php-mysql php-cli php-curl php-gd php-xml php-mbstring php-zip php-intl php-soap php-bcmath php-xmlrpc php-imagick php-opcache || warn "Some PHP packages failed to install"
        a2enmod php8.3 || a2enmod php || warn "Failed to enable PHP module"
        systemctl restart apache2
    fi
    
    # Install additional tools
    info "Installing additional tools..."
    apt install -y curl wget unzip certbot python3-certbot-apache redis-server jq dnsutils &>/dev/null || warn "Some tools failed to install"
    
    # Enable Apache modules
    a2enmod rewrite ssl headers proxy proxy_http proxy_wstunnel &>/dev/null || warn "Some Apache modules failed to enable"
    systemctl reload apache2 &>/dev/null || true
    
    success "LAMP components installed"
}

# Install WordPress
install_wordpress() {
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && site_dir="/var/www/$MAIN_DOMAIN/$WP_SUBDIR"
    
    info "Installing WordPress to $site_dir..."
    
    mkdir -p "$site_dir"
    cd /tmp
    wget -q https://wordpress.org/latest.tar.gz || error "Failed to download WordPress"
    tar xzf latest.tar.gz
    cp -R wordpress/* "$site_dir/"
    rm -rf wordpress latest.tar.gz
    chown -R www-data:www-data "$site_dir"
    chmod -R 755 "$site_dir"
    
    # Database setup
    case "$INSTALL_TYPE" in
        "subdomain")
            DB_NAME=$(echo "${SUBDOMAIN}_${MAIN_DOMAIN}" | tr '.' '_' | tr '-' '_')_db
            DB_USER=$(echo "${SUBDOMAIN}_${MAIN_DOMAIN}" | tr '.' '_' | tr '-' '_')_user
            DB_PASSWORD="$(echo "${SUBDOMAIN}_${MAIN_DOMAIN}" | tr '.' '_' | tr '-' '_')_2@"
            ;;
        "subdirectory")
            DB_NAME=$(echo "${MAIN_DOMAIN}_${WP_SUBDIR}" | tr '.' '_' | tr '-' '_')_db
            DB_USER=$(echo "${MAIN_DOMAIN}_${WP_SUBDIR}" | tr '.' '_' | tr '-' '_')_user
            DB_PASSWORD="$(echo "${MAIN_DOMAIN}_${WP_SUBDIR}" | tr '.' '_' | tr '-' '_')_2@"
            ;;
        *)
            DB_NAME=$(echo "$DOMAIN" | tr '.' '_' | tr '-' '_')_db
            DB_USER=$(echo "$DOMAIN" | tr '.' '_' | tr '-' '_')_user
            DB_PASSWORD="$(echo "$DOMAIN" | tr '.' '_' | tr '-' '_')_2@"
            ;;
    esac
    
    info "Creating database: $DB_NAME"
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME; CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%'; FLUSH PRIVILEGES;" &>/dev/null || error "Failed to create database"
    
    # Configure WordPress
    cp "$site_dir/wp-config-sample.php" "$site_dir/wp-config.php"
    sed -i "s#database_name_here#$DB_NAME#g; s#username_here#$DB_USER#g; s#password_here#$DB_PASSWORD#g" "$site_dir/wp-config.php"
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$site_dir/wp-config.php"
    sed -i "/define('DB_COLLATE', '');/a\\$SALTS" "$site_dir/wp-config.php"
    
    cat >> "$site_dir/wp-config.php" << EOF

define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
EOF
    
    if [ "$INSTALL_TYPE" = "subdirectory" ]; then
        cat >> "$site_dir/wp-config.php" << EOF
define('WP_SITEURL', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
define('WP_HOME', 'https://$MAIN_DOMAIN/$WP_SUBDIR');
EOF
    fi
    
    chown -R www-data:www-data "$site_dir"
    find "$site_dir" -type d -exec chmod 755 {} \;
    
    success "WordPress installed"
}

# Create Apache virtual host
create_vhost() {
    local domain="$1"
    local site_dir="$2"
    
    info "Creating virtual host for $domain..."
    
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
    
    a2ensite "$domain.conf" &>/dev/null
    systemctl reload apache2 &>/dev/null || warn "Apache reload had warnings"
    
    success "Virtual host created"
}

# Install SSL
install_ssl() {
    local domain="$1"
    
    if ! host "$domain" &>/dev/null; then
        warn "Domain $domain does not resolve, skipping SSL"
        return
    fi
    
    info "Installing SSL certificate for $domain..."
    
    if certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" &>/dev/null; then
        success "SSL certificate installed for $domain and www.$domain"
    elif certbot --apache -d "$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" &>/dev/null; then
        success "SSL certificate installed for $domain"
    else
        warn "SSL installation failed - you may need to install manually"
    fi
}

# Setup Redis and WP-CLI
setup_tools() {
    local site_dir="$1"
    
    # Install WP-CLI
    if ! command -v wp &>/dev/null; then
        info "Installing WP-CLI..."
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
    
    # Configure Redis
    if systemctl is-active --quiet redis-server; then
        sed -i "/^maxmemory /d" /etc/redis/redis.conf
        echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
        systemctl restart redis-server &>/dev/null
        
        cat >> "$site_dir/wp-config.php" << EOF

// Redis Configuration
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
EOF
        success "Redis configured"
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 -d DOMAIN [-e EMAIL] [-p PASSWORD] [-r REDIS_MEMORY]

Install WordPress on a domain, subdomain, or subdirectory.

OPTIONS:
    -d DOMAIN           Domain to install (required)
                        Examples: 
                          example.com (main domain)
                          sub.example.com (subdomain)
                          example.com/folder (subdirectory)
    -e EMAIL            Admin email (required if not in config.json)
    -p PASSWORD         MySQL root password (required if not in config.json)
    -r REDIS_MEMORY     Redis max memory in GB (default: 1)
    -s                  Skip SSL installation
    -h                  Show this help message

EXAMPLES:
    # Install on main domain
    $0 -d example.com -e admin@example.com -p MyPassword123

    # Install on subdomain
    $0 -d blog.example.com

    # Install on subdirectory
    $0 -d example.com/shop

    # Skip SSL
    $0 -d example.com -s

EOF
}

# Parse command line arguments
SKIP_SSL=false

while getopts "d:e:p:r:sh" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        e) ADMIN_EMAIL="$OPTARG" ;;
        p) DB_ROOT_PASSWORD="$OPTARG" ;;
        r) REDIS_MAX_MEMORY="$OPTARG" ;;
        s) SKIP_SSL=true ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Main execution
main() {
    check_root
    
    # Show header
    echo -e "${CYAN}=============================================================================${NC}"
    echo -e "${CYAN}                    WordPress CLI Installation Tool${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
    echo
    
    # Validate domain
    if [ -z "$DOMAIN" ]; then
        error "Domain is required. Use -d option or see -h for help."
    fi
    
    # Load config
    load_config
    
    # Set defaults
    [ -z "$REDIS_MAX_MEMORY" ] && REDIS_MAX_MEMORY="1"
    
    # Validate required parameters
    if [ -z "$ADMIN_EMAIL" ]; then
        error "Admin email is required. Use -e option or set in config.json"
    fi
    
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        error "MySQL root password is required. Use -p option or set in config.json"
    fi
    
    # Determine installation type
    if [[ "$DOMAIN" == *"/"* ]]; then
        INSTALL_TYPE="subdirectory"
        MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'/' -f1)
        WP_SUBDIR=$(echo "$DOMAIN" | cut -d'/' -f2)
        info "Installing WordPress on subdirectory: $MAIN_DOMAIN/$WP_SUBDIR"
    elif [[ "$DOMAIN" == *"."*"."* ]]; then
        INSTALL_TYPE="subdomain"
        SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
        MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'.' -f2-)
        info "Installing WordPress on subdomain: $DOMAIN"
    else
        INSTALL_TYPE="main_domain"
        info "Installing WordPress on main domain: $DOMAIN"
    fi
    
    # Install LAMP components if needed
    install_lamp_components
    
    # Install WordPress
    install_wordpress
    
    # Create virtual host
    local target_domain="$DOMAIN"
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && target_domain="$MAIN_DOMAIN" && site_dir="/var/www/$MAIN_DOMAIN"
    
    create_vhost "$target_domain" "$site_dir"
    
    # Install SSL unless skipped
    if [ "$SKIP_SSL" = false ]; then
        install_ssl "$target_domain"
    fi
    
    # Setup tools
    setup_tools "$site_dir"
    
    # Save config
    save_config
    
    # Show completion message
    echo
    success "WordPress installation completed!"
    echo
    echo -e "${GREEN}Domain: $DOMAIN${NC}"
    echo -e "${GREEN}Database: $DB_NAME${NC}"
    echo -e "${GREEN}Database User: $DB_USER${NC}"
    echo -e "${GREEN}Database Password: $DB_PASSWORD${NC}"
    echo -e "${GREEN}Document Root: $site_dir${NC}"
    
    if [ "$SKIP_SSL" = false ]; then
        echo -e "${GREEN}URL: https://$DOMAIN${NC}"
    else
        echo -e "${GREEN}URL: http://$DOMAIN${NC}"
    fi
    
    echo
    info "Log file: $LOG_FILE"
}

# Run main
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
