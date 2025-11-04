#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/lamp_installation_$(date +%Y%m%d_%H%M%S).log"

# Get script directory for sourcing WSL functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source WSL functions (will set ENVIRONMENT_MODE if not already set)
source "$SCRIPT_DIR/../wsl/wsl_functions.sh"
source "$SCRIPT_DIR/../wsl/wsl_completion.sh"

# Initialize environment if not already done
if [[ -z "$ENVIRONMENT_MODE" ]]; then
    set_environment_mode "auto"
fi

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
    echo "                    LAMP Stack Installation Tool"
    echo "                   Apache + MySQL + PHP + Redis"
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
    
    # Create config.json if it doesn't exist
    local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
    [ ! -f "$config_path" ] && echo '{"mysql_root_password":"","admin_email":"","redis_max_memory":"1"}' > "$config_path"

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
       '. + {
           admin_email: $email,
           redis_max_memory: $redis,
           mysql_root_password: $pass
       }' \
       "$config_path" > "$temp_file" && mv "$temp_file" "$config_path"
    success "Configuration saved to config.json"
}

# Get installation inputs
get_inputs() {
    echo -e "${YELLOW}LAMP Stack Configuration:${NC}"
    
    # Load configuration to ensure we have the latest values
    load_config
    
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
    
    confirm "Proceed with LAMP stack installation?" || return 1
}

# LAMP stack installation
install_lamp() {
    info "Installing LAMP stack..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Backup Apache configurations before any removal
    local apache_backup_dir="/tmp/apache_backup_$(date +%Y%m%d_%H%M%S)"
    if [ -d "/etc/apache2/sites-available" ] && [ "$(ls -A /etc/apache2/sites-available 2>/dev/null)" ]; then
        info "Backing up existing Apache configurations..."
        mkdir -p "$apache_backup_dir"
        cp -r /etc/apache2/sites-available "$apache_backup_dir/" 2>/dev/null || true
        cp -r /etc/apache2/sites-enabled "$apache_backup_dir/" 2>/dev/null || true
        
        # Save list of enabled sites
        local enabled_sites_file="$apache_backup_dir/enabled_sites.txt"
        for site in /etc/apache2/sites-enabled/*.conf; do
            if [ -L "$site" ] && [ -e "$site" ]; then
                basename "$site" >> "$enabled_sites_file"
            fi
        done
        success "Apache configurations backed up to $apache_backup_dir"
    fi
    
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
    
    # Restore Apache configurations if they were backed up
    if [ -n "$apache_backup_dir" ] && [ -d "$apache_backup_dir/sites-available" ]; then
        info "Restoring Apache configurations..."
        
        # Restore sites-available
        for conf in "$apache_backup_dir/sites-available"/*.conf; do
            if [ -f "$conf" ]; then
                local conf_name=$(basename "$conf")
                if [ ! -f "/etc/apache2/sites-available/$conf_name" ]; then
                    cp "$conf" "/etc/apache2/sites-available/" 2>/dev/null && info "Restored config: $conf_name"
                fi
            fi
        done
        
        # Re-enable previously enabled sites
        if [ -f "$apache_backup_dir/enabled_sites.txt" ]; then
            while IFS= read -r site; do
                if [ -f "/etc/apache2/sites-available/$site" ]; then
                    a2ensite "$site" 2>/dev/null && info "Re-enabled site: $site"
                fi
            done < "$apache_backup_dir/enabled_sites.txt"
        fi
        
        success "Apache configurations restored"
    fi
    
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
    
    # Configure Redis
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server
    
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
        if mysql -e "SELECT 1;" &>/dev/null || mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            return 0 # MySQL is properly installed and accessible
        fi
    fi
    return 1 # MySQL is not properly installed or not accessible
}

# Verify PHP installation
verify_php_installed() {
    # Check if PHP is installed and Apache module is loaded
    if command -v php &>/dev/null; then
        # Check if PHP Apache module is loaded
        if apache2ctl -M 2>/dev/null | grep -q php; then
            return 0 # PHP is properly installed with Apache module
        fi
    fi
    return 1 # PHP is not properly installed or Apache module missing
}

# Recovery function for failed installations
recover_failed_installation() {
    warn "Attempting to recover from failed installation..."
    
    # Backup Apache configurations before recovery
    local apache_backup_dir="/tmp/apache_recovery_backup_$(date +%Y%m%d_%H%M%S)"
    if [ -d "/etc/apache2/sites-available" ] && [ "$(ls -A /etc/apache2/sites-available 2>/dev/null)" ]; then
        info "Backing up Apache configurations before recovery..."
        mkdir -p "$apache_backup_dir"
        cp -r /etc/apache2/sites-available "$apache_backup_dir/" 2>/dev/null || true
        cp -r /etc/apache2/sites-enabled "$apache_backup_dir/" 2>/dev/null || true
        
        # Save list of enabled sites
        local enabled_sites_file="$apache_backup_dir/enabled_sites.txt"
        for site in /etc/apache2/sites-enabled/*.conf; do
            if [ -L "$site" ] && [ -e "$site" ]; then
                basename "$site" >> "$enabled_sites_file"
            fi
        done
        info "Apache configurations backed up to $apache_backup_dir"
    fi
    
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
    
    # Note: Apache backups will be restored when Apache is reinstalled in install_lamp()
    
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

# Complete LAMP installation
install_lamp_only() {
    get_inputs || return 1
    
    # Use the recovery-enabled installation
    if ! install_lamp_with_recovery; then
        error "LAMP installation failed. Please check the logs and try again."
        return 1
    fi
    
    save_config
    
    success "LAMP stack installation completed!"
    echo -e "${GREEN}Apache: $(apache2 -v | head -n1)${NC}"
    echo -e "${GREEN}MySQL: $(mysql --version)${NC}"
    echo -e "${GREEN}PHP: $(php -v | head -n1)${NC}"
    echo -e "${GREEN}Redis: $(redis-server --version)${NC}"
    
    if is_wsl_mode; then
        local wsl_ip=$(get_wsl_ip)
        echo -e "${GREEN}WSL IP: $wsl_ip${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    check_system
    load_config
    install_lamp_only
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"