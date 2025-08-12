#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# Main menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                    WordPress Master Installation Tool"
    echo "                   Comprehensive LAMP Stack Management"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo
}

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Prepare system for installation
prepare_system() {
    info "Preparing system for installation..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Fix any interrupted dpkg configurations
    info "Fixing any broken package configurations..."
    dpkg --configure -a 2>/dev/null || true
    apt --fix-broken install -y 2>/dev/null || true
    
    # Clean package cache
    apt clean 2>/dev/null || true
    
    # Update package lists with retries
    info "Updating package lists..."
    local retry_count=0
    while [ $retry_count -lt 3 ]; do
        if apt update -y 2>/dev/null; then
            break
        else
            warn "Package update failed, retrying... ($((retry_count + 1))/3)"
            sleep 5
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq 3 ]; then
        error "Failed to update package lists after 3 attempts. Please check your internet connection."
    fi
    
    success "System prepared successfully"
}

check_system() {
    info "Checking system requirements..."
    
    # Check OS
    if ! grep -q "Ubuntu" /etc/os-release; then
        warn "This script is designed for Ubuntu. Other distributions may not work correctly."
    else
        local ubuntu_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
        info "Detected Ubuntu $ubuntu_version"
    fi
    
    # Check disk space (at least 5GB free)
    local free_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 5242880 ]; then
        error "Insufficient disk space. At least 5GB required, but only $(($free_space / 1024 / 1024))GB available."
    fi
    
    # Check memory (at least 1GB)
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [ "$total_mem" -lt 1024 ]; then
        warn "Low memory detected (${total_mem}MB). WordPress may run slowly with less than 1GB RAM."
    fi
    
    # Check internet connectivity
    info "Testing internet connectivity..."
    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        error "No internet connection detected. Please check your network connection."
    fi
    
    # Test DNS resolution
    if ! nslookup google.com &>/dev/null; then
        warn "DNS resolution may be slow or failing"
    fi
    
    # Prepare system
    prepare_system
    
    # Install essential tools if missing
    local missing_tools=()
    command -v jq >/dev/null || missing_tools+=("jq")
    command -v dig >/dev/null || missing_tools+=("dnsutils")
    command -v curl >/dev/null || missing_tools+=("curl")
    command -v wget >/dev/null || missing_tools+=("wget")
    command -v nano >/dev/null || missing_tools+=("nano")
    command -v htop >/dev/null || missing_tools+=("htop")
    command -v unzip >/dev/null || missing_tools+=("unzip")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        info "Installing essential tools: ${missing_tools[*]}"
        
        # Install missing tools with better error handling
        if apt install -y "${missing_tools[@]}" 2>/dev/null; then
            success "Essential tools installed successfully"
        else
            warn "Some tools may have failed to install, trying individually..."
            # Try installing individually
            for tool in "${missing_tools[@]}"; do
                if apt install -y "$tool" 2>/dev/null; then
                    success "Installed $tool"
                else
                    warn "Failed to install $tool"
                fi
            done
        fi
    fi
    
    success "System requirements check completed"
}

# Configuration management
load_config() {
    local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
    if [ -f "$config_path" ]; then
        ADMIN_EMAIL=$(jq -r '.admin_email // ""' "$config_path")
        REDIS_MAX_MEMORY=$(jq -r '.redis_max_memory // "1"' "$config_path")
        DB_ROOT_PASSWORD=$(jq -r '.mysql_root_password // ""' "$config_path")
        
        # Try to get first domain from each section
        DOMAIN=$(jq -r '.main_domains[0] // ""' "$config_path")
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdomains[0] // ""' "$config_path")
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdirectory_domains[0] // ""' "$config_path")
        
        info "Configuration loaded from config.json"
        
        # Inform user about pre-setting MySQL password
        if [ -z "$DB_ROOT_PASSWORD" ]; then
            info "Tip: You can pre-set MySQL password in config.json to skip manual entry"
        fi
    else
        info "No config.json found - will create one with your settings"
    fi
}

save_config() {
    local temp_file=$(mktemp)
    local domain_type="main_domains"
    [[ "$DOMAIN" == *"."*"."* ]] && domain_type="subdomains"
    [[ "$DOMAIN" == *"/"* ]] && domain_type="subdirectory_domains"

    # Create config.json if it doesn't exist
    local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
    [ ! -f "$config_path" ] && echo '{"main_domains":[],"subdomains":[],"subdirectory_domains":[],"mysql_root_password":"","admin_email":"","redis_max_memory":"1"}' > "$config_path"

    # Preserve existing values if current variables are empty
    local current_email="${ADMIN_EMAIL}"
    local current_redis="${REDIS_MAX_MEMORY}"
    local current_pass="${DB_ROOT_PASSWORD}"
    
    # Only preserve from config.json if the variable is truly empty
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
    success "Configuration saved to config.json"
}

# Get installation inputs
get_inputs() {
    local type="$1"
    echo -e "${YELLOW}Installation Configuration:${NC}"
    
    # Load configuration to ensure we have the latest values
    load_config
    
    # Parse domains from config.json by type
    local main_domains=()
    local subdomains=()
    local subdirectories=()
    local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
    if [ -f "$config_path" ]; then
        # Read arrays properly using mapfile
        readarray -t main_domains < <(jq -r '.main_domains[]?' "$config_path" 2>/dev/null)
        readarray -t subdomains < <(jq -r '.subdomains[]?' "$config_path" 2>/dev/null)
        readarray -t subdirectories < <(jq -r '.subdirectory_domains[]?' "$config_path" 2>/dev/null)
    fi

    case $type in
        "main")
            if [ ${#main_domains[@]} -gt 0 ]; then
                echo "A) Existing main domains:"
                printf '%s\n' "${main_domains[@]}" | nl -w2 -s') '
                read -p "Select domain (number) or enter new domain (e.g., example.com): " domain_choice
                if [[ "$domain_choice" =~ ^[0-9]+$ ]]; then
                    DOMAIN="${main_domains[$((domain_choice-1))]}"
                    [ -z "$DOMAIN" ] && read -p "Enter domain (e.g., example.com): " DOMAIN
                else
                    DOMAIN="$domain_choice"
                    # Validate main domain format (no subdomains or paths)
                    while [[ "$DOMAIN" == *"."*"."* || "$DOMAIN" == *"/*" ]]; do
                        warn "Main domain should be in format 'example.com' (no subdomains or paths)"
                        read -p "Enter valid main domain: " DOMAIN
                    done
                fi
            else
                read -p "Enter domain (e.g., example.com): " DOMAIN
            fi
            INSTALL_TYPE="main_domain" ;;
            
        "subdomain")
            # Find subdomains in config (format: sub.main.com)
            local subdomain=""
            local main_domain=""
            for domain in "${subdomains[@]}"; do
                if [[ "$domain" == *"."*"."* ]]; then
                    subdomain=$(echo "$domain" | cut -d'.' -f1)
                    main_domain=$(echo "$domain" | cut -d'.' -f2-)
                    break
                fi
            done
            
            if [ ${#subdomains[@]} -gt 0 ]; then
                echo "B) Existing subdomains:"
                printf '%s\n' "${subdomains[@]}" | nl -w2 -s') '
                read -p "Select subdomain (number) or enter new subdomain (format: sub.main.com): " subdomain_choice
                
                if [[ "$subdomain_choice" =~ ^[0-9]+$ ]]; then
                    DOMAIN="${subdomains[$((subdomain_choice-1))]}"
                    [ -z "$DOMAIN" ] && read -p "Enter subdomain (format: sub.main.com): " DOMAIN
                else
                    DOMAIN="$subdomain_choice"
                    # Validate subdomain format (must have at least two dots)
                    while [[ "$DOMAIN" != *"."*"."* ]]; do
                        warn "Subdomain should be in format 'sub.example.com'"
                        read -p "Enter valid subdomain: " DOMAIN
                    done
                fi
            else
                read -p "Enter subdomain (format: sub.main.com): " DOMAIN
                # Validate subdomain format
                while [[ "$DOMAIN" != *"."*"."* ]]; do
                    warn "Subdomain should be in format 'sub.example.com'"
                    read -p "Enter valid subdomain: " DOMAIN
                done
            fi
            
            # Extract main domain and subdomain from full domain
            MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'.' -f2-)
            SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
            DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"
            INSTALL_TYPE="subdomain" ;;
            
        "subdirectory")
            # Check for existing subdirectory installations (format: domain/subdir)
            local subdir_found=""
            for domain in "${subdirectories[@]}"; do
                if [[ "$domain" == *"/"* ]]; then
                    MAIN_DOMAIN=$(echo "$domain" | cut -d'/' -f1)
                    WP_SUBDIR=$(echo "$domain" | cut -d'/' -f2)
                    subdir_found="$domain"
                    break
                fi
            done
            
            if [ ${#subdirectories[@]} -gt 0 ]; then
                echo "C) Existing subdirectories:"
                printf '%s\n' "${subdirectories[@]}" | nl -w2 -s') '
                read -p "Select subdirectory (number) or enter new (format: domain.com/subdir): " subdir_choice
                
                if [[ "$subdir_choice" =~ ^[0-9]+$ ]]; then
                    DOMAIN="${subdirectories[$((subdir_choice-1))]}"
                    [ -z "$DOMAIN" ] && read -p "Enter subdirectory (format: domain.com/subdir): " DOMAIN
                else
                    DOMAIN="$subdir_choice"
                    # Validate subdirectory format
                    while [[ "$DOMAIN" != *"/"* ]]; do
                        warn "Subdirectory should be in format 'domain.com/subdir'"
                        read -p "Enter valid subdirectory: " DOMAIN
                    done
                fi
            else
                read -p "Enter subdirectory (format: domain.com/subdir): " DOMAIN
                # Validate subdirectory format
                while [[ "$DOMAIN" != *"/"* ]]; do
                    warn "Subdirectory should be in format 'domain.com/subdir'"
                    read -p "Enter valid subdirectory: " DOMAIN
                done
            fi
            
            # Extract main domain and subdirectory
            MAIN_DOMAIN=$(echo "$DOMAIN" | cut -d'/' -f1)
            WP_SUBDIR=$(echo "$DOMAIN" | cut -d'/' -f2)
            
            # Validate subdirectory name
            while [[ "$WP_SUBDIR" == *"/"* || -z "$WP_SUBDIR" ]]; do
                warn "Subdirectory cannot contain slashes or be empty"
                read -p "Enter subdirectory (no slashes): " WP_SUBDIR
            done
            
            DOMAIN="${MAIN_DOMAIN}/${WP_SUBDIR}"
            INSTALL_TYPE="subdirectory" ;;
    esac
    
    # Use admin email from config if available
    if [ -z "$ADMIN_EMAIL" ]; then
        read -p "Enter admin email: " ADMIN_EMAIL
    else
        echo "Using admin email from config.json: $ADMIN_EMAIL"
    fi
    echo -e "${CYAN}MySQL Password Setup:${NC}"
    if [ -z "$DB_ROOT_PASSWORD" ] || [ "$DB_ROOT_PASSWORD" = "null" ]; then
        echo "No MySQL root password found in config.json"
        echo "You can either:"
        echo "1. Enter password now (will be saved to config.json)"
        echo "2. Edit config.json manually and set 'mysql_root_password' field"
        echo
        while true; do
            read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
            read -sp "Confirm password: " DB_ROOT_PASSWORD_CONFIRM; echo
            [ "$DB_ROOT_PASSWORD" = "$DB_ROOT_PASSWORD_CONFIRM" ] && break
            echo -e "${RED}Passwords do not match${NC}"
        done
        save_config
        success "MySQL password saved to config.json for future use"
    else
        echo "Using MySQL root password from config.json"
    fi
    read -p "Enter Redis memory in GB (default: 1): " REDIS_MAX_MEMORY
    [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    confirm "Proceed with installation?" || return 1
}

# LAMP stack installation
install_lamp() {
    info "Installing LAMP stack..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Clean up any broken installations first
    info "Cleaning up any broken package installations..."
    dpkg --configure -a 2>/dev/null || true
    apt --fix-broken install -y 2>/dev/null || true
    
    # Remove any broken MySQL/Apache installations
    info "Removing any broken installations..."
    apt remove --purge mysql-server* mysql-client* mysql-common apache2* libapache2-mod-php* -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    # Clean package cache
    apt clean
    
    # Update system
    info "Updating system packages..."
    local retry_count=0
    while [ $retry_count -lt 3 ]; do
        if apt update -y; then
            break
        else
            warn "Package update failed, retrying... ($((retry_count + 1))/3)"
            sleep 5
            ((retry_count++))
        fi
    done
    
    # Upgrade system (non-interactive)
    info "Upgrading system packages..."
    apt upgrade -y || warn "Some packages failed to upgrade, but continuing..."
    
    # Install packages step by step with better error handling
    info "Installing Apache web server..."
    if ! apt install -y apache2; then
        error "Failed to install Apache. Please check your internet connection and try again."
    fi
    
    info "Installing MySQL database server..."
    if ! apt install -y mysql-server; then
        error "Failed to install MySQL. Please check your internet connection and try again."
    fi
    
    info "Installing PHP and core extensions..."
    local php_core="php libapache2-mod-php php-mysql php-cli"
    if ! apt install -y $php_core; then
        error "Failed to install PHP core components."
    fi
    
    info "Installing additional PHP extensions..."
    local php_extensions="php-curl php-gd php-xml php-mbstring php-zip php-intl php-soap php-bcmath php-xmlrpc php-imagick php-opcache"
    apt install -y $php_extensions || warn "Some PHP extensions may have failed to install, but continuing..."
    
    info "Installing additional tools..."
    local tools="curl wget unzip certbot python3-certbot-apache redis-server jq dnsutils net-tools htop nano vim git"
    apt install -y $tools || warn "Some additional tools may have failed to install, but continuing..."
    
    # Enable and start services
    info "Enabling and starting services..."
    systemctl enable apache2 mysql redis-server 2>/dev/null || warn "Failed to enable some services"
    systemctl start apache2 mysql redis-server 2>/dev/null || warn "Failed to start some services"
    
    # Wait for MySQL to be ready
    info "Waiting for MySQL to be ready..."
    local mysql_ready=0
    for i in {1..30}; do
        if systemctl is-active --quiet mysql; then
            mysql_ready=1
            break
        fi
        sleep 2
    done
    
    if [ $mysql_ready -eq 0 ]; then
        error "MySQL failed to start properly"
    fi
    
    # Enable Apache modules
    info "Enabling Apache modules..."
    a2enmod rewrite ssl headers 2>/dev/null || warn "Failed to enable some Apache modules"
    systemctl reload apache2 2>/dev/null || warn "Failed to reload Apache"
    
    # Secure MySQL installation
    info "Securing MySQL installation..."
    # Wait a bit more for MySQL to be fully ready
    sleep 5
    
    # Check if MySQL has no root password (fresh installation)
    if mysql -e "SELECT 1;" 2>/dev/null; then
        info "Setting MySQL root password..."
        if mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD';" 2>/dev/null; then
            MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
            success "MySQL root password set successfully"
        else
            error "Failed to set MySQL root password"
        fi
    else
        # MySQL already has a password - test if user provided the correct one
        if mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
            info "Using provided MySQL root password"
        else
            warn "MySQL already has a different root password or connection failed"
            echo "Please enter the existing MySQL root password:"
            read -sp "MySQL root password: " EXISTING_PASSWORD; echo
            if mysql -u root -p"$EXISTING_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                DB_ROOT_PASSWORD="$EXISTING_PASSWORD"
                MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
                info "Using existing MySQL root password"
            else
                error "Invalid MySQL password provided"
            fi
        fi
    fi
    
    # Clean up MySQL security
    info "Cleaning up MySQL security settings..."
    mysql $MYSQL_AUTH -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; FLUSH PRIVILEGES;" 2>/dev/null || warn "MySQL security cleanup had warnings"
    
    # Verify installations
    info "Verifying LAMP stack installation..."
    local lamp_ok=true
    
    if ! verify_apache_installed; then
        warn "Apache verification failed"
        lamp_ok=false
    fi
    
    if ! verify_mysql_installed; then
        warn "MySQL verification failed"
        lamp_ok=false
    fi
    
    if ! verify_php_installed; then
        warn "PHP verification failed"
        lamp_ok=false
    fi
    
    if [ "$lamp_ok" = true ]; then
        success "LAMP stack installed and verified successfully"
        info "Apache: $(apache2 -v | head -n1)"
        info "MySQL: $(mysql --version)"
        info "PHP: $(php -v | head -n1)"
    else
        error "LAMP stack installation verification failed"
    fi
}

# WordPress installation
install_wordpress() {
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && site_dir="/var/www/$MAIN_DOMAIN/$WP_SUBDIR"
    
    mkdir -p "$site_dir" || error "Failed to create site directory"
    cd /tmp && wget https://wordpress.org/latest.tar.gz && tar xzf latest.tar.gz && cp -R wordpress/* "$site_dir/" && rm -rf wordpress latest.tar.gz || error "Failed to download WordPress"
    chown -R www-data:www-data "$site_dir" && chmod -R 755 "$site_dir"
    
    # Database setup
    # Generate unique database name based on installation type
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
    
    mysql $MYSQL_AUTH -e "CREATE DATABASE $DB_NAME; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" || error "Database creation failed"
    
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
    # After WordPress is configured, set secure permissions
    set_wordpress_permissions "$site_dir"
}

# Apache virtual host and SSL with conflict detection
create_vhost_ssl() {
    local domain="$1"
    local site_dir="$2"
    
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
    
    a2ensite "$domain.conf" && systemctl reload apache2 || error "Failed to enable site"
    
    # SSL installation with conflict detection
    if host "$domain" >/dev/null 2>&1; then
        install_ssl_with_conflict_detection "$domain"
    else
        warn "Domain $domain does not resolve, skipping SSL"
    fi
}

# SSL installation with conflict detection
install_ssl_with_conflict_detection() {
    local domain="$1"
    local conflicting_sites=()
    local disabled_sites=()
    
    info "Checking for SSL conflicts..."
    
    # Find potentially conflicting sites
    for site in /etc/apache2/sites-enabled/*.conf; do
        [ -f "$site" ] || continue
        site_name=$(basename "$site")
        site_domain=$(echo "$site_name" | sed 's/-le-ssl\.conf$//' | sed 's/\.conf$//')
        
        # Skip current domain
        [ "$site_domain" = "$domain" ] && continue
        
        # Check if site might conflict
        if [[ "$site_name" == *"-le-ssl.conf" ]] || grep -q "ServerName.*\." "$site" 2>/dev/null; then
            conflicting_sites+=("$site_name")
        fi
    done
    
    # Handle conflicts if found
    if [ ${#conflicting_sites[@]} -gt 0 ]; then
        warn "Found ${#conflicting_sites[@]} potentially conflicting sites"
        
        if confirm "Temporarily disable conflicting sites for SSL installation?"; then
            info "Temporarily disabling conflicting sites..."
            for site in "${conflicting_sites[@]}"; do
                if a2dissite "$site" 2>/dev/null; then
                    disabled_sites+=("$site")
                    info "Disabled: $site"
                fi
            done
            systemctl reload apache2 2>/dev/null
            sleep 2
        fi
    fi
    
    # Install SSL certificate with fallback
    info "Installing SSL certificate for $domain..."
    if certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null; then
        success "SSL certificate installed for $domain"
    elif certbot --apache -d "$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null; then
        success "SSL certificate installed for $domain (main domain only)"
    else
        warn "SSL installation failed - you may need to install manually"
    fi

    if verify_ssl_installed "$domain"; then
        success "SSL certificate installed for $domain"
    else
        warn "Failed to install SSL certificate for $domain"
    fi
    
    # Re-enable disabled sites
    if [ ${#disabled_sites[@]} -gt 0 ]; then
        info "Re-enabling previously disabled sites..."
        for site in "${disabled_sites[@]}"; do
            a2ensite "$site" 2>/dev/null && info "Re-enabled: $site"
        done
        systemctl reload apache2 2>/dev/null
    fi
}

# Redis and WP-CLI setup
setup_tools() {
    # Install WP-CLI
    if ! command -v wp &>/dev/null; then
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp || error "WP-CLI installation failed"
    fi
    
    # Configure Redis
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server
    
    cat >> "$1/wp-config.php" << EOF

// Redis Configuration
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
EOF
}

# Complete WordPress installation
install_lamp_wordpress() {
    while true; do
            # Get domains by type for proper menu display
        local main_domains=()
        local subdomains=()
        local subdirectory_domains=()
        local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
        if [ -f "$config_path" ]; then
            readarray -t main_domains < <(jq -r '.main_domains[]?' "$config_path" 2>/dev/null)
            readarray -t subdomains < <(jq -r '.subdomains[]?' "$config_path" 2>/dev/null)
            readarray -t subdirectory_domains < <(jq -r '.subdirectory_domains[]?' "$config_path" 2>/dev/null)
        fi

        echo -e "${YELLOW}WordPress Installation Types:${NC}"
        echo ""
        echo "1) Main Domain"
        if [ ${#main_domains[@]} -gt 0 ]; then
            echo "   A) Existing main domains: ${main_domains[*]}"
        fi
        echo ""
        echo "2) Subdomain"
        if [ ${#subdomains[@]} -gt 0 ]; then
            echo "   B) Existing subdomains: ${subdomains[*]}"
        fi
        echo ""
        echo "3) Subdirectory"
        if [ ${#subdirectory_domains[@]} -gt 0 ]; then
            echo "   C) Existing subdirectories: ${subdirectory_domains[*]}"
        fi
        echo ""
        echo "4) Back"
        read -p "Select type (1-4): " choice
        
        case $choice in
            1) get_inputs "main" || continue; break ;;
            2) get_inputs "subdomain" || continue; break ;;
            3)
                if [ ${#subdirectory_domains[@]} -gt 0 ]; then
                    echo "C) Existing subdirectories:"
                    for i in "${!subdirectory_domains[@]}"; do
                        echo "$((i+1))) ${subdirectory_domains[$i]}"
                    done
                    read -p "Select subdirectory (1-${#subdirectory_domains[@]}) or enter new: " subdir_choice
                    if [[ $subdir_choice =~ ^[0-9]+$ ]] && [ $subdir_choice -le ${#subdirectory_domains[@]} ]; then
                        DOMAIN="${subdirectory_domains[$((subdir_choice-1))]}"
                        MAIN_DOMAIN="${DOMAIN%/*}"
                        INSTALL_TYPE="subdirectory"
                        if ! install_lamp_with_recovery; then
                            error "LAMP installation failed. Please check the logs and try again."
                            return 1
                        fi
                        install_wordpress
                        create_vhost_ssl "$MAIN_DOMAIN" "/var/www/$MAIN_DOMAIN"
                        setup_tools "/var/www/$MAIN_DOMAIN"
                        save_config
                        success "WordPress installation completed for subdirectory $DOMAIN!"
                        echo -e "${GREEN}Main Domain: $MAIN_DOMAIN${NC}"
                        echo -e "${GREEN}Subdirectory: $DOMAIN${NC}"
                        read -p "Press Enter to continue..."
                        return
                    fi
                fi
                get_inputs "subdirectory" || continue; break ;;
            4) return ;;
            *) echo -e "${RED}Invalid option. Please select 1-4.${NC}"; sleep 1; continue ;;
        esac
        break
    done
    
    # Use the recovery-enabled installation
    if ! install_lamp_with_recovery; then
        error "LAMP installation failed. Please check the logs and try again."
        return 1
    fi
    
    install_wordpress
    
    local target_domain="$DOMAIN"
    local site_dir="/var/www/$DOMAIN"
    [ "$INSTALL_TYPE" = "subdirectory" ] && target_domain="$MAIN_DOMAIN" && site_dir="/var/www/$MAIN_DOMAIN"
    
    create_vhost_ssl "$target_domain" "$site_dir"
    setup_tools "$site_dir"
    save_config
    
    success "WordPress installation completed!"
    echo -e "${GREEN}Domain: $DOMAIN${NC}"
    echo -e "${GREEN}Database: $DB_NAME / $DB_USER / $DB_PASSWORD${NC}"
    echo -e "${GREEN}Visit: https://$DOMAIN${NC}"
    read -p "Press Enter to continue..."
}

# Set secure WordPress file and directory permissions
set_wordpress_permissions() {
    local wp_path="$1"
    if [ -z "$wp_path" ] || [ ! -d "$wp_path" ]; then
        warn "Cannot set permissions: WordPress path '$wp_path' is invalid."
        return 1
    fi

    info "Setting ownership to www-data:www-data..."
    chown -R www-data:www-data "$wp_path"

    info "Setting directory permissions to 755..."
    find "$wp_path" -type d -print0 | xargs -0 chmod 755
    
    success "Directory permissions have been set. For comprehensive and secure file permissions, please use fast_permissions.sh."
}

# Verify Apache installation
verify_apache_installed() {
    # Check if Apache is installed and running
    if command -v apache2 &>/dev/null && systemctl is-active --quiet apache2; then
        # Also check if Apache configuration directory exists
        if [ -d "/etc/apache2" ] && [ -f "/etc/apache2/apache2.conf" ]; then
            return 0 # Apache is properly installed and running
        fi
    fi
    return 1 # Apache is not properly installed or not running
}

# Verify MySQL installation
verify_mysql_installed() {
    # Check if MySQL is installed and running
    if command -v mysql &>/dev/null && systemctl is-active --quiet mysql; then
        # Try to connect to MySQL to ensure it's working
        if mysql -e "SELECT 1;" 2>/dev/null || mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            return 0 # MySQL is properly installed and accessible
        fi
    fi
    return 1 # MySQL is not properly installed or not accessible
}

# Verify PHP installation
verify_php_installed() {
    # Check if PHP is installed and Apache module is loaded
    if command -v php &>/dev/null; then
        # Check if PHP Apache module exists
        if [ -f "/etc/apache2/mods-available/php*.load" ] || apache2ctl -M 2>/dev/null | grep -q php; then
            return 0 # PHP is properly installed with Apache module
        fi
    fi
    return 1 # PHP is not properly installed or Apache module missing
}

# Verify SSL installation
verify_ssl_installed() {
    local domain="$1"
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        return 0 # SSL is installed
    else
        return 1 # SSL is not installed
    fi
}

# Recovery function for failed installations
recover_failed_installation() {
    warn "Attempting to recover from failed installation..."
    
    # Stop services that might be running
    systemctl stop apache2 mysql redis-server 2>/dev/null || true
    
    # Clean up broken packages
    info "Cleaning up broken packages..."
    dpkg --configure -a 2>/dev/null || true
    apt --fix-broken install -y 2>/dev/null || true
    
    # Remove partially installed packages
    apt remove --purge mysql-server* mysql-client* mysql-common apache2* libapache2-mod-php* php* redis-server -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    
    # Clean package cache
    apt clean
    
    # Remove configuration directories if they exist but are broken
    [ -d "/etc/mysql" ] && rm -rf /etc/mysql 2>/dev/null || true
    [ -d "/etc/apache2" ] && rm -rf /etc/apache2 2>/dev/null || true
    [ -d "/var/lib/mysql" ] && rm -rf /var/lib/mysql 2>/dev/null || true
    
    success "System cleaned up. You can now try the installation again."
}

# Installation wrapper with error handling
install_lamp_with_recovery() {
    local max_attempts=2
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        info "Installation attempt $attempt of $max_attempts"
        
        if install_lamp; then
            success "LAMP installation completed successfully!"
            return 0
        else
            warn "Installation attempt $attempt failed"
            
            if [ $attempt -lt $max_attempts ]; then
                if confirm "Would you like to clean up and try again?"; then
                    recover_failed_installation
                    ((attempt++))
                    continue
                else
                    error "Installation cancelled by user"
                fi
            else
                error "Installation failed after $max_attempts attempts"
            fi
        fi
    done
    
    return 1
}

# Main execution
main() {
    check_root
    check_system
    load_config
    install_lamp_wordpress
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"