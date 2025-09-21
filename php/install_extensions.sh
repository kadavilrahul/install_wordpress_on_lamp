#!/bin/bash

# PHP Extensions Installation Script
# Installs missing PHP extensions for optimal WordPress performance

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Function to check if extension is installed
is_extension_installed() {
    local extension="$1"
    case "$extension" in
        "opcache")
            # OpCache shows as "Zend OPcache" in php -m
            php -m 2>/dev/null | grep -q "Zend OPcache"
            ;;
        *)
            php -m 2>/dev/null | grep -q "^$extension$"
            ;;
    esac
}

# Function to get PHP version
get_php_version() {
    php -v 2>/dev/null | head -n 1 | cut -d' ' -f2 | cut -d'.' -f1-2
}

# Function to install PHP extension
install_php_extension() {
    local extension="$1"
    local package_name="$2"
    
    info "Installing PHP extension: $extension"
    
    if is_extension_installed "$extension"; then
        success "PHP $extension extension is already installed"
        return 0
    fi
    
    # Update package list
    info "Updating package list..."
    apt update -y >/dev/null 2>&1 || warn "Failed to update package list"
    
    # Install the extension
    info "Installing $package_name..."
    if apt install -y "$package_name" >/dev/null 2>&1; then
        success "Successfully installed $package_name"
        
        # Verify installation
        if is_extension_installed "$extension"; then
            success "PHP $extension extension is now loaded"
            return 0
        else
            warn "Extension installed but not loaded. Restarting Apache..."
            systemctl restart apache2 && success "Apache restarted" || warn "Failed to restart Apache"
            
            # Check again after restart
            if is_extension_installed "$extension"; then
                success "PHP $extension extension is now loaded after Apache restart"
                return 0
            else
                error "Extension installed but still not loading. Manual configuration may be required."
                return 1
            fi
        fi
    else
        error "Failed to install $package_name"
        return 1
    fi
}

# Function to configure Redis extension
configure_redis_extension() {
    info "Configuring Redis extension..."
    
    # Check if Redis server is installed and running
    if ! command -v redis-server >/dev/null 2>&1; then
        info "Redis server not found. Installing redis-server..."
        apt install -y redis-server || error "Failed to install redis-server"
    fi
    
    # Start and enable Redis service
    systemctl start redis-server 2>/dev/null || warn "Failed to start Redis server"
    systemctl enable redis-server 2>/dev/null || warn "Failed to enable Redis server"
    
    # Check Redis service status
    if systemctl is-active --quiet redis-server; then
        success "Redis server is running"
    else
        warn "Redis server is not running. You may need to configure it manually."
    fi
    
    success "Redis extension configuration completed"
}

# Function to configure OpCache extension
configure_opcache_extension() {
    info "Configuring OpCache extension..."
    
    local php_version=$(get_php_version)
    local opcache_ini="/etc/php/$php_version/apache2/conf.d/10-opcache.ini"
    
    # Create OpCache configuration if it doesn't exist
    if [ ! -f "$opcache_ini" ]; then
        info "Creating OpCache configuration file: $opcache_ini"
        cat > "$opcache_ini" << EOF
; OpCache Configuration for WordPress
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=2
opcache.fast_shutdown=1
opcache.validate_timestamps=1
opcache.save_comments=1
opcache.enable_file_override=0
EOF
        success "OpCache configuration created"
    else
        info "OpCache configuration file already exists"
    fi
    
    success "OpCache extension configuration completed"
}

# Function to show extension status
show_extension_status() {
    echo -e "${CYAN}============================================================================="
    echo "                     PHP Extensions Status Check"
    echo -e "=============================================================================${NC}"
    
    local extensions=("mysqli" "curl" "gd" "mbstring" "xml" "zip" "imagick" "redis" "opcache" "pgsql")
    local installed_count=0
    local total_count=${#extensions[@]}
    
    echo -e "${YELLOW}Checking PHP extensions...${NC}"
    echo
    
    for ext in "${extensions[@]}"; do
        if is_extension_installed "$ext"; then
            echo -e "  ${GREEN}✓${NC} $ext"
            ((installed_count++))
        else
            echo -e "  ${RED}✗${NC} $ext"
        fi
    done
    
    echo
    echo -e "${CYAN}Summary: $installed_count/$total_count extensions installed${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Main installation function
main() {
    check_root
    
    echo -e "${CYAN}============================================================================="
    echo "                     PHP Extensions Installer"
    echo "                   Install Redis and OpCache Extensions"
    echo -e "=============================================================================${NC}"
    echo
    
    # Show current status
    show_extension_status
    echo
    
    # Check what needs to be installed
    local needs_redis=false
    local needs_opcache=false
    
    if ! is_extension_installed "redis"; then
        needs_redis=true
    fi
    
    if ! is_extension_installed "opcache"; then
        needs_opcache=true
    fi
    
    if [ "$needs_redis" = false ] && [ "$needs_opcache" = false ]; then
        success "All required extensions are already installed!"
        show_extension_status
        exit 0
    fi
    
    # Confirm installation
    echo -e "${YELLOW}Missing extensions detected:${NC}"
    [ "$needs_redis" = true ] && echo -e "  ${RED}✗${NC} redis - Required for object caching and performance"
    [ "$needs_opcache" = true ] && echo -e "  ${RED}✗${NC} opcache - Required for PHP performance optimization"
    echo
    
    if ! confirm "Would you like to install the missing extensions?"; then
        info "Installation cancelled by user"
        exit 0
    fi
    
    echo
    info "Starting PHP extensions installation..."
    
    # Install Redis extension
    if [ "$needs_redis" = true ]; then
        echo
        info "=== Installing Redis Extension ==="
        if install_php_extension "redis" "php-redis"; then
            configure_redis_extension
        else
            error "Failed to install Redis extension"
        fi
    fi
    
    # Install OpCache extension
    if [ "$needs_opcache" = true ]; then
        echo
        info "=== Installing OpCache Extension ==="
        if install_php_extension "opcache" "php-opcache"; then
            configure_opcache_extension
        else
            error "Failed to install OpCache extension"
        fi
    fi
    
    # Restart Apache to ensure all extensions are loaded
    echo
    info "Restarting Apache to load new extensions..."
    if systemctl restart apache2; then
        success "Apache restarted successfully"
    else
        warn "Failed to restart Apache. You may need to restart it manually."
    fi
    
    # Final status check
    echo
    info "=== Final Status Check ==="
    show_extension_status
    
    echo
    success "PHP extensions installation completed!"
    echo
    echo -e "${CYAN}Next steps:${NC}"
    echo "1. Verify extensions are working: php -m | grep -E '(redis|opcache)'"
    echo "2. For WordPress Redis caching, install a Redis object cache plugin"
    echo "3. OpCache will automatically improve PHP performance"
    echo "4. Monitor performance improvements in your WordPress admin dashboard"
    echo
}

# Handle command line arguments
case "${1:-}" in
    "--status"|"-s")
        show_extension_status
        exit 0
        ;;
    "--redis")
        check_root
        install_php_extension "redis" "php-redis" && configure_redis_extension
        exit $?
        ;;
    "--opcache")
        check_root
        install_php_extension "opcache" "php-opcache" && configure_opcache_extension
        exit $?
        ;;
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --status, -s     Show extension status only"
        echo "  --redis          Install Redis extension only"
        echo "  --opcache        Install OpCache extension only"
        echo "  --help, -h       Show this help"
        exit 0
        ;;
esac

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"