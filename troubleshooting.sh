#!/bin/bash

#=============================================================================
# WordPress Troubleshooting Script
#=============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
info() { echo -e "${BLUE}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}✗ Error: $1${NC}" >&2; }

# Check for root
check_root() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)" && exit 1
}

# Find WordPress installations
find_wp_installs() {
    local wp_dirs=()
    local default_path="/var/www"
    
    info "Scanning for WordPress installations in $default_path..."
    
    # Find directories containing both wp-config.php and wp-content
    while IFS= read -r dir; do
        [ -f "$dir/wp-config.php" ] && [ -d "$dir/wp-content" ] && wp_dirs+=("$dir")
    done < <(find "$default_path" -maxdepth 3 -type d -print 2>/dev/null)
    
    if [ ${#wp_dirs[@]} -eq 0 ]; then
        warning "No WordPress installations found in $default_path"
        read -p "Enter WordPress path manually (e.g. /var/www/example.com): " WP_PATH
        [ -z "$WP_PATH" ] && error "Path cannot be empty" && return 1
        [ ! -d "$WP_PATH" ] && error "Directory '$WP_PATH' not found" && return 1
        return 0
    fi
    
    echo -e "\n${BLUE}=== Found WordPress Installations ===${NC}"
    for i in "${!wp_dirs[@]}"; do
        echo "$((i+1)). ${wp_dirs[$i]}"
    done
    echo "$(( ${#wp_dirs[@]} + 1 )). Enter custom path"
    
    read -p "Select installation (1-${#wp_dirs[@]}): " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -le ${#wp_dirs[@]} ]; then
        WP_PATH="${wp_dirs[$((choice-1))]}"
        success "Selected: $WP_PATH"
        return 0
    elif [ $choice -eq $(( ${#wp_dirs[@]} + 1 )) ]; then
        read -p "Enter WordPress path manually (e.g. /var/www/example.com): " WP_PATH
        [ -z "$WP_PATH" ] && error "Path cannot be empty" && return 1
        [ ! -d "$WP_PATH" ] && error "Directory '$WP_PATH' not found" && return 1
        return 0
    else
        error "Invalid selection"
        return 1
    fi
}

# Get WordPress path
get_wp_path() {
    find_wp_installs
    return $?
}

# Fix permissions
fix_permissions() {
    info "Setting ownership to www-data:www-data..."
    chown -R www-data:www-data "$WP_PATH" || { error "Failed to set ownership"; return 1; }

    info "Setting base directory and file permissions..."
    chmod -R u=rwX,go=rX "$WP_PATH" || { error "Failed to set base permissions"; return 1; }

    if [ -d "$WP_PATH/wp-content" ]; then
        info "Setting wp-content permissions..."
        chmod -R g+w "$WP_PATH/wp-content" || { error "Failed to set wp-content permissions"; return 1; }
    fi

    if [ -f "$WP_PATH/wp-config.php" ]; then
        info "Securing wp-config.php..."
        chmod 640 "$WP_PATH/wp-config.php" || { error "Failed to secure wp-config.php"; return 1; }
    fi

    success "Permissions fixed successfully"
}

# Check service status
check_service() {
    local service=$1
    info "Checking $service status..."
    systemctl status "$service" --no-pager
    read -p "Restart $service? (y/n): " choice
    case "$choice" in
        y|Y) systemctl restart "$service" && success "$service restarted";;
        *) info "Skipping $service restart";;
    esac
}

# Check system resources
check_resources() {
    info "Checking system resources..."
    echo -e "\n${BLUE}=== Memory Usage ===${NC}"
    free -h
    
    echo -e "\n${BLUE}=== Disk Space ===${NC}"
    df -h
    
    echo -e "\n${BLUE}=== WordPress Directory Size ===${NC}"
    du -sh "$WP_PATH"
}

# Check error logs
check_logs() {
    info "Checking error logs..."
    
    echo -e "\n${BLUE}=== Apache Error Log ===${NC}"
    tail -n 20 /var/log/apache2/error.log
    
    local domain_log="/var/log/apache2/error_$(basename "$WP_PATH").log"
    [ -f "$domain_log" ] && { 
        echo -e "\n${BLUE}=== Domain Error Log ===${NC}"
        tail -n 20 "$domain_log"
    }
    
    local debug_log="$WP_PATH/wp-content/debug.log"
    if [ -f "$debug_log" ]; then
        echo -e "\n${BLUE}=== WordPress Debug Log ===${NC}"
        grep -i "error\|fatal\|warning" "$debug_log" | tail -n 30
    fi
}

# Manage plugins
manage_plugins() {
    info "Managing plugins..."
    if ! command -v wp &> /dev/null; then
        warning "WP-CLI not found. Install it or try manual plugin management."
        return 1
    fi
    
    read -p "Choose action: (1) Deactivate all (2) Reactivate all (3) Remove broken: " choice
    case "$choice" in
        1) wp plugin deactivate --all --allow-root --path="$WP_PATH" && success "All plugins deactivated";;
        2) wp plugin activate --all --path="$WP_PATH" --allow-root && success "All plugins reactivated";;
        3) 
            read -p "Enter plugin name to remove: " plugin
            rm -rf "$WP_PATH/wp-content/plugins/$plugin" && success "Plugin $plugin removed"
            ;;
        *) info "No action taken";;
    esac
}

# Clean MySQL binary logs
clean_mysql_logs() {
    info "Cleaning MySQL binary logs..."
    read -p "This will delete all binary logs. Continue? (y/n): " choice
    case "$choice" in
        y|Y)
            mysql -u root -p -e "RESET MASTER;"
            systemctl restart mysql
            success "MySQL binary logs cleaned"
            ;;
        *) info "Skipping MySQL log cleanup";;
    esac
}

# Database repair and optimization
repair_database() {
    info "Repairing and optimizing WordPress database..."
    if ! command -v wp &> /dev/null; then
        warning "WP-CLI not found. Install it to use this feature."
        return 1
    fi
    
    wp db repair --path="$WP_PATH" --allow-root && success "Database repaired"
    wp db optimize --path="$WP_PATH" --allow-root && success "Database optimized"
}

# Redis troubleshooting
redis_troubleshoot() {
    info "Checking Redis configuration..."
    if [ -f "$WP_PATH/wp-content/object-cache.php" ]; then
        warning "Redis object-cache.php found - this might cause 'Error establishing a Redis connection'"
        read -p "Disable Redis by removing object-cache.php? (y/n): " choice
        case "$choice" in
            y|Y)
                rm -f "$WP_PATH/wp-content/object-cache.php"
                success "Redis disabled - object-cache.php removed"
                ;;
            *) info "Redis remains enabled";;
        esac
    else
        info "No Redis configuration found"
    fi
}

# Toggle debug mode
toggle_debug() {
    local wp_config="$WP_PATH/wp-config.php"
    [ ! -f "$wp_config" ] && error "wp-config.php not found" && return 1
    
    if grep -q "WP_DEBUG', true" "$wp_config"; then
        info "Debug mode is currently ON"
        read -p "Disable debug mode? (y/n): " choice
        case "$choice" in
            y|Y)
                sed -i "s/WP_DEBUG', true/WP_DEBUG', false/" "$wp_config"
                sed -i "s/WP_DEBUG_LOG', true/WP_DEBUG_LOG', false/" "$wp_config"
                sed -i "s/WP_DEBUG_DISPLAY', true/WP_DEBUG_DISPLAY', false/" "$wp_config"
                success "Debug mode disabled"
                ;;
            *) info "Debug mode remains enabled";;
        esac
    else
        info "Debug mode is currently OFF"
        read -p "Enable debug mode? (y/n): " choice
        case "$choice" in
            y|Y)
                sed -i "/define( 'DB_COLLATE'/i define( 'WP_DEBUG', true );\ndefine( 'WP_DEBUG_LOG', true );\ndefine( 'WP_DEBUG_DISPLAY', false );" "$wp_config"
                success "Debug mode enabled"
                ;;
            *) info "Debug mode remains disabled";;
        esac
    fi
}

# Verify file ownership
verify_ownership() {
    info "Verifying file ownership..."
    local owner=$(stat -c '%U:%G' "$WP_PATH")
    if [ "$owner" != "www-data:www-data" ]; then
        warning "Current ownership: $owner (should be www-data:www-data)"
        read -p "Fix ownership? (y/n): " choice
        case "$choice" in
            y|Y) fix_permissions;;
            *) info "Ownership not changed";;
        esac
    else
        success "Ownership is correct: www-data:www-data"
    fi
}

# Main menu
main_menu() {
    echo -e "\n${BLUE}=== WordPress Troubleshooting Menu ===${NC}"
    echo "  1) Fix permissions - Set correct file and folder permissions for WordPress"
    echo "  2) Check service status (Apache/MySQL/PHP) - View and restart web server and database services"
    echo "  3) Check system resources - Monitor memory usage, disk space, and directory sizes"
    echo "  4) Check error logs - Review Apache, domain, and WordPress debug logs"
    echo "  5) Manage plugins - Deactivate, activate, or remove WordPress plugins"
    echo "  6) Clean MySQL binary logs - Remove MySQL binary logs to free up disk space"
    echo "  7) Repair/Optimize database - Fix and optimize WordPress database tables"
    echo "  8) Redis troubleshooting - Diagnose and fix Redis caching connection issues"
    echo "  9) Toggle debug mode - Enable or disable WordPress debug logging"
    echo "  10) Verify file ownership - Check and fix WordPress file ownership settings"
    echo "  0) Exit - Return to main menu"
    
    read -p "Choose an option (0-10): " option
    case "$option" in
        1) fix_permissions;;
        2)
            check_service apache2
            check_service mysql
            check_service php8.3-fpm
            ;;
        3) check_resources;;
        4) check_logs;;
        5) manage_plugins;;
        6) clean_mysql_logs;;
        7) repair_database;;
        8) redis_troubleshoot;;
        9) toggle_debug;;
        10) verify_ownership;;
        0) exit 0;;
        *) error "Invalid option";;
    esac
}

# Main execution
check_root
if get_wp_path; then
    while true; do
        main_menu
    done
fi