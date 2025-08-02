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
    echo -e "${PURPLE}"
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
    if [ -f "config.json" ]; then
        ADMIN_EMAIL=$(jq -r '.admin_email // ""' config.json)
        REDIS_MAX_MEMORY=$(jq -r '.redis_max_memory // "1"' config.json)
        DB_ROOT_PASSWORD=$(jq -r '.mysql_root_password // ""' config.json)
        

        
        # Try to get first domain from each section
        DOMAIN=$(jq -r '.main_domains[0] // ""' config.json)
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdomains[0] // ""' config.json)
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdirectory_domains[0] // ""' config.json)
        
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
    [ ! -f "config.json" ] && echo '{"main_domains":[],"subdomains":[],"subdirectory_domains":[],"mysql_root_password":"","admin_email":"","redis_max_memory":"1"}' > config.json

    # Preserve existing values if current variables are empty
    local current_email="${ADMIN_EMAIL}"
    local current_redis="${REDIS_MAX_MEMORY}"
    local current_pass="${DB_ROOT_PASSWORD}"
    
    # Only preserve from config.json if the variable is truly empty
    [ -z "$current_email" ] && current_email=$(jq -r '.admin_email // ""' config.json)
    [ -z "$current_redis" ] && current_redis=$(jq -r '.redis_max_memory // "1"' config.json)
    [ -z "$current_pass" ] && current_pass=$(jq -r '.mysql_root_password // ""' config.json)

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
       config.json > "$temp_file" && mv "$temp_file" config.json
    success "Configuration saved to config.json"
}

# Menu system
show_menu() {
    clear
    echo -e "${CYAN}============================================================================="
    echo "                            Website Master"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Main Menu:${NC}"
    echo "  1) Install LAMP Stack + WordPress - Complete LAMP installation with WordPress setup"
    echo "  2) Backup/Restore - Backup and restore WordPress sites and databases"
    echo "  3) Install Apache + SSL Only - Set up web server with SSL for existing domains"
    echo "  4) Miscellaneous Tools - Additional utilities and system tools"
    echo "  5) MySQL Remote Access - Configure MySQL for remote connections"
    echo "  6) Troubleshooting - Diagnose and fix common website issues"
    echo "  7) Rclone Management - Manage cloud storage backups with Google Drive"
    echo "  8) Configure Redis - Set up Redis caching for better performance"
    echo "  9) Remove Websites & Databases - Clean removal of websites and associated data"
    echo "  10) Remove Orphaned Databases - Clean up databases without corresponding websites"
    echo "  11) Fix Apache Configs - Repair broken Apache virtual host configurations"
    echo "  12) System Status Check - View system resources and service status"
    echo "  0) Exit - Close the Website Master tool"
    echo -e "${CYAN}=============================================================================${NC}"
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
    if [ -f "config.json" ]; then
        main_domains=($(jq -r '.main_domains[]?' config.json 2>/dev/null))
        subdomains=($(jq -r '.subdomains[]?' config.json 2>/dev/null))
        subdirectories=($(jq -r '.subdirectory_domains[]?' config.json 2>/dev/null))
    fi

    case $type in
        "main")
            if [ ${#main_domains[@]} -gt 0 ]; then
                echo "Existing main domains:"
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
                echo "Existing subdomains:"
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
                echo "Existing subdirectories:"
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
        local subdirectories=()
        if [ -f "config.json" ]; then
            main_domains=($(jq -r '.main_domains[]?' config.json 2>/dev/null))
            subdomains=($(jq -r '.subdomains[]?' config.json 2>/dev/null))
            subdirectory_domains=($(jq -r '.subdirectory_domains[]?' config.json 2>/dev/null))
        fi

        echo -e "${YELLOW}WordPress Installation Types:${NC}"
        echo "1) Main Domain"
        [ ${#main_domains[@]} -gt 0 ] && echo "   Existing main domains: ${main_domains[@]}"
        echo "2) Subdomain"
        [ ${#subdomains[@]} -gt 0 ] && echo "   Existing subdomains: ${subdomains[@]}"
        echo "3) Subdirectory"
        [ ${#subdirectory_domains[@]} -gt 0 ] && echo "   Existing subdirectories: ${subdirectory_domains[@]}"
        echo "4) Back"
        read -p "Select type (1-4): " choice
        
        case $choice in
            1) get_inputs "main" || continue; break ;;
            2) get_inputs "subdomain" || continue; break ;;
            3)
                if [ ${#subdirectory_domains[@]} -gt 0 ]; then
                    echo "Existing subdirectories:"
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


#=============================================================================
# APACHE AND SSL ONLY INSTALLATION
#=============================================================================

install_apache_ssl_only() {
    show_header
    echo -e "${YELLOW}Apache + SSL Only Installation${NC}"
    echo "This will install Apache web server with SSL support for a new domain."
    echo
    
    setup_new_domain
}


setup_new_domain() {
    # Load available domains from config.json
    load_config
    
    # Create selection menu for domains
    echo "Available domains from config.json:"
    echo "1) Main domains:"
    local counter=1
    declare -a domain_options
    
    # Add main domains
    if [ -n "$MAIN_DOMAINS" ]; then
        for domain in $MAIN_DOMAINS; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
        done
    fi
    
    # Add subdomains
    if [ -n "$SUBDOMAINS" ]; then
        echo "2) Subdomains:"
        for domain in $SUBDOMAINS; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
        done
    fi
    
    # Add subdirectory domains
    if [ -n "$SUBDIRECTORY_DOMAINS" ]; then
        echo "3) Subdirectory domains:"
        for domain in $SUBDIRECTORY_DOMAINS; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
        done
    fi
    
    echo "   0) Enter custom domain"
    echo ""
    
    # Get user selection
    read -p "Select domain number: " selection
    
    if [ "$selection" = "0" ]; then
        read -p "Enter your domain name: " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo "Error: Domain name required!"
            read -p "Press Enter to continue..."
            return
        fi
    elif [ -n "${domain_options[$selection]}" ]; then
        DOMAIN="${domain_options[$selection]}"
        echo "Selected: $DOMAIN"
    else
        echo "Invalid selection!"
        read -p "Press Enter to continue..."
        return
    fi
    save_config  # Save the domain to config.json
    
    echo ""
    echo "Setting up $DOMAIN..."
    
    # Update and install packages
    apt update -qq
    apt install -y apache2 certbot python3-certbot-apache dig
    
    # Enable Apache modules
    a2enmod rewrite ssl
    
    # Determine web directory based on domain type
    if [[ "$DOMAIN" == *"/"* ]]; then
        # Subdirectory domain (e.g., silkroademart.com/new)
        BASE_DOMAIN=$(echo "$DOMAIN" | cut -d'/' -f1)
        SUBDIRECTORY=$(echo "$DOMAIN" | cut -d'/' -f2-)
        WEB_ROOT="/var/www/$BASE_DOMAIN/$SUBDIRECTORY"
        APACHE_DOMAIN="$BASE_DOMAIN"
    else
        # Regular domain or subdomain
        WEB_ROOT="/var/www/$DOMAIN"
        APACHE_DOMAIN="$DOMAIN"
    fi
    
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"
    
    echo "Web directory created: $WEB_ROOT"
    
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













# PHP configuration
adjust_php_config() {
    local PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    [ -z "$PHP_VERSION" ] && error "PHP not installed"
    
    info "Adjusting PHP $PHP_VERSION configuration..."
    for ini in "/etc/php/$PHP_VERSION/cli/php.ini" "/etc/php/$PHP_VERSION/apache2/php.ini" "/etc/php/$PHP_VERSION/fpm/php.ini"; do
        [ -f "$ini" ] && sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/; s/^post_max_size = .*/post_max_size = 64M/; s/^memory_limit = .*/memory_limit = 512M/; s/^max_execution_time = .*/max_execution_time = 300/' "$ini"
    done
    
    systemctl restart apache2 php"$PHP_VERSION"-fpm 2>/dev/null || true
    success "PHP configuration updated"
    read -p "Press Enter to continue..."
}

# Redis configuration
configure_redis() {
    read -p "Redis memory in GB (default: 1): " REDIS_MAX_MEMORY; [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    
    ! command -v redis-server &>/dev/null && { apt update -y && apt install -y redis-server || error "Redis installation failed"; }
    
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server && systemctl enable redis-server
    
    success "Redis configured with ${REDIS_MAX_MEMORY}GB memory"
    read -p "Press Enter to continue..."
}


# Website removal
# Website removal with proper MySQL authentication and testing
remove_websites_and_databases() {
    # Get MySQL credentials first
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    
    # Test MySQL connection
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL not accessible"
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
    
    # Discover websites with better detection
    local sites=()
    local site_types=()
    
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                
                if [ -f "$dir/wp-config.php" ]; then
                    sites+=("$domain")
                    site_types+=("WordPress")
                else
                    # Check for subdirectory WordPress installations
                    has_wp_subdir=false
                    for subdir in "$dir"*/; do
                        if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                            subdir_name=$(basename "$subdir")
                            sites+=("$domain/$subdir_name")
                            site_types+=("WordPress-SubDir")
                            has_wp_subdir=true
                        fi
                    done
                    
                    # If no WordPress subdirs, it's a regular site
                    if [ "$has_wp_subdir" = false ]; then
                        sites+=("$domain")
                        site_types+=("Static")
                    fi
                fi
            fi
        done
    fi
    
    [ ${#sites[@]} -eq 0 ] && { warn "No websites found in /var/www"; read -p "Press Enter..."; return; }
    
    echo -e "${RED}Website Removal Tool${NC}"
    echo -e "${YELLOW}Available websites:${NC}"
    echo
    for i in "${!sites[@]}"; do
        echo -e "  $((i+1))) ${GREEN}${sites[i]}${NC} (${site_types[i]})"
    done
    echo
    echo -e "  $((${#sites[@]}+1))) ${RED}Remove ALL websites${NC}"
    echo -e "  $((${#sites[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#sites[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#sites[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL websites and databases!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; read -p "Press Enter..."; return; }
        
        for i in "${!sites[@]}"; do
            remove_single_site "${sites[i]}" "${site_types[i]}"
        done
        success "All websites removed"
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sites[@]} ]; then
            warn "Invalid selection"
            read -p "Press Enter..."
            return
        fi
        
        local selected_site="${sites[$((choice-1))]}"
        local selected_type="${site_types[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Website: ${GREEN}$selected_site${NC}"
        echo -e "  Type: $selected_type"
        if [[ "$selected_type" == *"WordPress"* ]]; then
            echo -e "  Database and user will be removed"
        fi
        echo -e "  Apache configuration will be removed"
        echo -e "  SSL certificates will be removed"
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; read -p "Press Enter..."; return; }
        
        remove_single_site "$selected_site" "$selected_type"
    fi
    
    # Reload Apache configuration
    info "Reloading Apache configuration..."
    if apache2ctl configtest 2>/dev/null; then
        systemctl reload apache2 && success "Apache reloaded successfully"
    else
        warn "Apache configuration has issues, attempting restart..."
        systemctl restart apache2 && success "Apache restarted successfully"
    fi
    
    read -p "Press Enter to continue..."
}

# Remove single website function
remove_single_site() {
    local site="$1"
    local site_type="$2"
    
    info "Removing $site..."
    
    # Handle subdirectory installations
    if [[ "$site" == *"/"* ]]; then
        local main_domain=$(echo "$site" | cut -d'/' -f1)
        local subdir=$(echo "$site" | cut -d'/' -f2)
        local site_path="/var/www/$main_domain/$subdir"
        local domain_for_apache="$main_domain"
    else
        local site_path="/var/www/$site"
        local domain_for_apache="$site"
    fi
    
    # Remove Apache configurations
    info "Removing Apache configurations for $domain_for_apache..."
    a2dissite "$domain_for_apache.conf" 2>/dev/null || true
    a2dissite "$domain_for_apache-le-ssl.conf" 2>/dev/null || true
    a2dissite "$domain_for_apache-ssl.conf" 2>/dev/null || true
    rm -f "/etc/apache2/sites-available/$domain_for_apache.conf"
    rm -f "/etc/apache2/sites-available/$domain_for_apache-le-ssl.conf"
    rm -f "/etc/apache2/sites-available/$domain_for_apache-ssl.conf"
    
    # Remove SSL certificates
    info "Removing SSL certificates for $domain_for_apache..."
    certbot delete --cert-name "$domain_for_apache" --non-interactive 2>/dev/null || true
    
    # Remove database if WordPress
    if [[ "$site_type" == *"WordPress"* ]] && [ -f "$site_path/wp-config.php" ]; then
        info "Removing WordPress database..."
        local db_name=$(grep "DB_NAME" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        local db_user=$(grep "DB_USER" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        
        if [ -n "$db_name" ]; then
            info "Dropping database: $db_name"
            if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
                success "Database $db_name dropped"
            else
                warn "Failed to drop database $db_name"
            fi
        fi
        
        if [ -n "$db_user" ]; then
            info "Dropping user: $db_user"
            if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
                success "User $db_user dropped"
            else
                warn "Failed to drop user $db_user"
            fi
        fi
        
        mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi
    
    # Remove website files
    info "Removing website files from $site_path..."
    if rm -rf "$site_path"; then
        success "Website files removed"
    else
        warn "Failed to remove some website files"
    fi
    
    if verify_website_removed "$domain_for_apache"; then
        success "$site removed successfully"
    else
        warn "Failed to remove $site completely"
    fi
}

# Remove orphaned/redundant databases
remove_orphaned_databases() {
    echo -e "${YELLOW}Scanning for orphaned databases...${NC}"
    
    # Get MySQL credentials
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    
    # Test MySQL connection
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL not accessible"
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
    
    # Get all databases (excluding system databases)
    local all_dbs=($(mysql $MYSQL_AUTH -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys|phpmyadmin)$"))
    
    # Get all existing websites
    local existing_sites=()
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                existing_sites+=("$domain")
                
                # Check for subdirectory WordPress installations
                for subdir in "$dir"*/; do
                    if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                        subdir_name=$(basename "$subdir")
                        existing_sites+=("$domain/$subdir_name")
                    fi
                done
            fi
        done
    fi
    
    # Find orphaned databases
    local orphaned_dbs=()
    local orphaned_users=()
    
    for db in "${all_dbs[@]}"; do
        local is_orphaned=true
        
        # Check if database belongs to any existing website
        for site in "${existing_sites[@]}"; do
            # Convert site name to expected database name format
            local expected_db=$(echo "$site" | sed 's/\./_/g' | sed 's/-/_/g' | sed 's/\//_/g')
            
            if [[ "$db" == "$expected_db" ]]; then
                is_orphaned=false
                break
            fi
        done
        
        # Also check if database is referenced in any wp-config.php"
        if [ "$is_orphaned" = true ]; then
            for dir in /var/www/*/; do
                if [ -f "$dir/wp-config.php" ]; then
                    local config_db=$(grep "DB_NAME" "$dir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                    if [[ "$db" == "$config_db" ]]; then
                        is_orphaned=false
                        break
                    fi
                fi
                
                # Check subdirectories
                for subdir in "$dir"*/; do
                    if [ -f "$subdir/wp-config.php" ]; then
                        local config_db=$(grep "DB_NAME" "$subdir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                        if [[ "$db" == "$config_db" ]]; then
                            is_orphaned=false
                            break 2
                        fi
                    fi
                done
            done
        fi
        
        if [ "$is_orphaned" = true ]; then
            orphaned_dbs+=("$db")
            # Find associated user (common pattern: dbname_user)
            # Find associated user by checking common naming patterns
            local user_found=""
            local potential_user1="${db}_user"
            local base_name=$(echo "$db" | sed 's/_db$//')
            local potential_user2="${base_name}_user"

            if mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user1';" 2>/dev/null | grep -q "^${potential_user1}$"; then
                user_found="$potential_user1"
            elif [ "$base_name" != "$db" ] && mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user2';" 2>/dev/null | grep -q "^${potential_user2}$"; then
                user_found="$potential_user2"
            fi
            orphaned_users+=("$user_found")
        fi
    done
    
    if [ ${#orphaned_dbs[@]} -eq 0 ]; then
        success "No orphaned databases found"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${RED}Found ${#orphaned_dbs[@]} orphaned database(s):${NC}"
    echo
    for i in "${!orphaned_dbs[@]}"; do
        echo -e "  $((i+1))) ${YELLOW}${orphaned_dbs[i]}${NC}"
        if [ -n "${orphaned_users[i]}" ]; then
            echo -e "      User: ${orphaned_users[i]}"
        fi
        
        # Show database size
        local db_size=$(mysql $MYSQL_AUTH -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.tables WHERE table_schema = '${orphaned_dbs[i]}';" 2>/dev/null | tail -n 1)
        if [ -n "$db_size" ] && [ "$db_size" != "NULL" ]; then
            echo -e "      Size: ${db_size} MB"
        fi
    done
    
    echo
    echo -e "  $((${#orphaned_dbs[@]}+1))) ${RED}Remove ALL orphaned databases${NC}"
    echo -e "  $((${#orphaned_dbs[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#orphaned_dbs[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#orphaned_dbs[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL orphaned databases and users!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; return; }
        
        for i in "${!orphaned_dbs[@]}"; do
            remove_single_database "${orphaned_dbs[i]}" "${orphaned_users[i]}"
        done
        read -p "Press Enter to continue..."
        success "All orphaned databases removed"
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#orphaned_dbs[@]} ]; then
            read -p "Press Enter to continue..."
            warn "Invalid selection"
            return
        fi
        
        local selected_db="${orphaned_dbs[$((choice-1))]}"
        local selected_user="${orphaned_users[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Database: ${YELLOW}$selected_db${NC}"
        if [ -n "$selected_user" ]; then
            echo -e "  User: ${YELLOW}$selected_user${NC}"
        fi
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; return; }
        
        read -p "Press Enter to continue..."
        remove_single_database "$selected_db" "$selected_user"
    fi
}

# Remove single database and user
remove_single_database() {
    local db_name="$1"
    local db_user="$2"
    
    info "Removing database: $db_name"
    
    if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
        success "Database $db_name dropped"
    else
        warn "Failed to drop database $db_name"
    fi

    if [ -n "$db_user" ]; then
        info "Removing user: $db_user"
        if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
            success "User $db_user dropped"
        else
            warn "Failed to drop user $db_user"
        fi
    fi
    
    mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    success "Database cleanup completed"
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

# Verify WordPress installation
verify_wordpress_installed() {
    local site_dir="$1"
    if [ -d "$site_dir" ] && [ -f "$site_dir/wp-config.php" ]; then
        return 0 # WordPress is installed
    else
        return 1 # WordPress is not installed
    fi
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

# Verify website removal
verify_website_removed() {
    local domain="$1"
    local site_path="/var/www/$domain"
    local apache_config="/etc/apache2/sites-available/$domain.conf"
    local apache_ssl_config="/etc/apache2/sites-available/$domain-le-ssl.conf"

    if [ -d "$site_path" ] || [ -f "$apache_config" ] || [ -f "$apache_ssl_config" ]; then
        return 1 # Website not removed
    else
        return 0 # Website removed
    fi
}

# Check for maintenance file
check_maintenance_file() {
    local site_path="$1"
    if [ -f "$site_path/.maintenance" ]; then
        warn "Maintenance file detected at '$site_path/.maintenance'. This could be the reason for the maintenance page."
    else
        info "No .maintenance file found at '$site_path/.maintenance'."
    fi
}

# Fix Apache configurations
fix_all_apache_configs() {
    info "Scanning Apache configurations..."
    local fixed=0
    
    for config in /etc/apache2/sites-available/*.conf; do
        [ -f "$config" ] || continue
        domain=$(basename "$config" .conf)
        
        if grep -q "ServerAdmin.*Error:" "$config" || grep -q "ServerAdmin.*root@.*#" "$config"; then
            warn "Fixing broken config: $domain"
            cp "$config" "${config}.broken.$(date +%Y%m%d_%H%M%S)"
            
            cat > "$config" << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/$domain
    <Directory /var/www/$domain>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$domain.log
    CustomLog \${APACHE_LOG_DIR}/access_$domain.log combined
</VirtualHost>
EOF
            ((fixed++))
        fi
    done
    
    [ $fixed -gt 0 ] && { success "Fixed $fixed configurations"; systemctl reload apache2; } || info "No broken configurations found"
    apache2ctl configtest && success "Apache configuration is valid" || warn "Apache configuration has issues"
    read -p "Press Enter to continue..."
}


# System status check
system_status_check() {
    clear
    echo -e "${YELLOW}System Status Check${NC}"
    echo
    echo -e "${CYAN}=== System Information ===${NC}"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo "Uptime: $(uptime -p 2>/dev/null || echo "Unknown")"
    echo
    echo -e "${CYAN}=== Resource Usage ===${NC}"
    echo "Memory:"; free -h
    echo "Disk Usage:"
    echo "-----------------------------------------------"
    df -h --output=source,size,used,avail,pcent,target | awk 'NR==1 {print $1"    "$2"   "$3"   "$4"   "$5"   "$6} NR>1 && /^\/dev\// {printf "%-10s %5s %5s %5s %5s %s\n", $1, $2, $3, $4, $5, $6}'
    echo "-----------------------------------------------"
    echo
    echo -e "${CYAN}=== Service Status ===${NC}"
    for service in apache2 mysql redis-server; do
        systemctl is-active --quiet "$service" && echo -e "$service: ${GREEN}Running${NC}" || echo -e "$service: ${RED}Stopped${NC}"
    done
    echo
    echo -e "${CYAN}=== WordPress Sites ===${NC}"
    [ -d "/var/www" ] && for site in /var/www/*; do
        [ -d "$site" ] && [ -f "$site/wp-config.php" ] && echo -e "WordPress: ${GREEN}$(basename "$site")${NC}"
    done
    read -p "Press Enter to continue..."
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

    if [ -n "$1" ]; then
        case "$1" in
            install_apache_ssl_only) install_apache_ssl_only ;;
            remove_websites_and_databases) remove_websites_and_databases ;;
            remove_orphaned_databases) remove_orphaned_databases ;;
            *) echo "Invalid function: $1" ;;
        esac
        exit 0
    fi
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1) install_lamp_wordpress ;;
            2) bash backup_restore.sh ;;
            3) install_apache_ssl_only ;;
            4) bash miscellaneous.sh ;;
            5) bash mysql_remote.sh ;;
            6) bash troubleshooting.sh ;;
            7) bash rclone.sh ;;
            8) configure_redis ;;
            9) remove_websites_and_databases ;;
            10) remove_orphaned_databases ;;
            11) fix_all_apache_configs ;;
            12) system_status_check ;;
            0) echo -e "${GREEN}Thank you for using WordPress Master!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}



# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"