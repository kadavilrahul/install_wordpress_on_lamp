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

# Check if PostgreSQL is installed and running
check_postgresql() {
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get PostgreSQL credentials
get_postgresql_auth() {
    if check_postgresql; then
        # Check if we can connect as postgres user without password
        if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
            PG_AUTH_METHOD="sudo"
            return 0
        else
            echo -e "${CYAN}PostgreSQL Authentication Required:${NC}"
            read -sp "Enter PostgreSQL password for postgres user: " PG_PASSWORD; echo
            export PGPASSWORD="$PG_PASSWORD"
            PG_AUTH_METHOD="password"
        fi
    fi
    return 1
}

# Execute PostgreSQL command
pg_execute() {
    local query="$1"
    if [ "$PG_AUTH_METHOD" = "sudo" ]; then
        sudo -u postgres psql -c "$query" 2>/dev/null
    else
        PGPASSWORD="$PG_PASSWORD" psql -U postgres -h localhost -c "$query" 2>/dev/null
    fi
}

# Execute PostgreSQL command for specific database
pg_execute_db() {
    local db="$1"
    local query="$2"
    if [ "$PG_AUTH_METHOD" = "sudo" ]; then
        sudo -u postgres psql -d "$db" -c "$query" 2>/dev/null
    else
        PGPASSWORD="$PG_PASSWORD" psql -U postgres -h localhost -d "$db" -c "$query" 2>/dev/null
    fi
}

# Website removal with proper MySQL and PostgreSQL authentication and testing
remove_websites_and_databases() {
    local has_mysql=false
    local has_postgresql=false
    
    # Check and get MySQL credentials
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        has_mysql=true
        if [ -z "$DB_ROOT_PASSWORD" ]; then
            echo -e "${CYAN}MySQL Authentication Required:${NC}"
            read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
        fi
        
        # Test MySQL connection
        if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            warn "Invalid MySQL password or MySQL not accessible - will skip MySQL databases"
            has_mysql=false
        else
            MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
        fi
    fi
    
    # Check and get PostgreSQL credentials
    if check_postgresql; then
        has_postgresql=true
        get_postgresql_auth
    fi
    
    if [ "$has_mysql" = false ] && [ "$has_postgresql" = false ]; then
        warn "No database servers (MySQL or PostgreSQL) are accessible"
    fi
    
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
    
    # Remove database if WordPress or has database configuration
    if [[ "$site_type" == *"WordPress"* ]] && [ -f "$site_path/wp-config.php" ]; then
        info "Removing WordPress database..."
        local db_name=$(grep "DB_NAME" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        local db_user=$(grep "DB_USER" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        local db_host=$(grep "DB_HOST" "$site_path/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        
        # Determine if it's MySQL or PostgreSQL
        local is_postgresql=false
        if [ -n "$db_host" ] && [[ "$db_host" == *"5432"* ]]; then
            is_postgresql=true
        fi
        
        # Also check for config.json files that might indicate PostgreSQL
        if [ -f "$site_path/generator/config.json" ] || [ -f "$site_path/config.json" ]; then
            local config_file=""
            [ -f "$site_path/generator/config.json" ] && config_file="$site_path/generator/config.json"
            [ -f "$site_path/config.json" ] && config_file="$site_path/config.json"
            
            if [ -n "$config_file" ]; then
                # Check if it has PostgreSQL configuration
                local pg_host=$(jq -r '.host // ""' "$config_file" 2>/dev/null)
                local pg_port=$(jq -r '.port // ""' "$config_file" 2>/dev/null)
                local pg_database=$(jq -r '.database // ""' "$config_file" 2>/dev/null)
                local pg_username=$(jq -r '.username // ""' "$config_file" 2>/dev/null)
                
                if [[ "$pg_port" == "5432" ]] || [[ -n "$pg_database" && -n "$pg_username" ]]; then
                    is_postgresql=true
                    [ -n "$pg_database" ] && db_name="$pg_database"
                    [ -n "$pg_username" ] && db_user="$pg_username"
                fi
            fi
        fi
        
        if [ -n "$db_name" ]; then
            if [ "$is_postgresql" = true ] && [ "$has_postgresql" = true ]; then
                info "Dropping PostgreSQL database: $db_name"
                if pg_execute "DROP DATABASE IF EXISTS \"$db_name\";"; then
                    success "PostgreSQL database $db_name dropped"
                else
                    warn "Failed to drop PostgreSQL database $db_name"
                fi
                
                if [ -n "$db_user" ]; then
                    info "Dropping PostgreSQL user: $db_user"
                    if pg_execute "DROP USER IF EXISTS \"$db_user\";"; then
                        success "PostgreSQL user $db_user dropped"
                    else
                        warn "Failed to drop PostgreSQL user $db_user"
                    fi
                fi
            elif [ "$has_mysql" = true ]; then
                info "Dropping MySQL database: $db_name"
                if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
                    success "MySQL database $db_name dropped"
                else
                    warn "Failed to drop MySQL database $db_name"
                fi
                
                if [ -n "$db_user" ]; then
                    info "Dropping MySQL user: $db_user"
                    if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
                        success "MySQL user $db_user dropped"
                    else
                        warn "Failed to drop MySQL user $db_user"
                    fi
                fi
                
                mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
            fi
        fi
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