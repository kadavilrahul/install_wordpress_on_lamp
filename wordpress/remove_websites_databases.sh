#!/bin/bash

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

# Configuration management
load_config() {
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../config.json" ]; then
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

# Main execution
main() {
    check_root
    load_config
    remove_websites_and_databases
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"