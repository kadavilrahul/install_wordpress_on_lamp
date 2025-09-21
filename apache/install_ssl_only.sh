#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"

# Get script directory for sourcing WSL functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source WSL functions (will set ENVIRONMENT_MODE if not already set)
source "$SCRIPT_DIR/../wsl/wsl_functions.sh"
source "$SCRIPT_DIR/../wsl/wsl_ssl.sh"

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

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

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

# Configuration management
load_config() {
    local config_path="$(dirname "${BASH_SOURCE[0]}")/../config.json"
    if [ -f "$config_path" ]; then
        ADMIN_EMAIL=$(jq -r '.admin_email // ""' "$config_path")
        REDIS_MAX_MEMORY=$(jq -r '.redis_max_memory // "1"' "$config_path")
        DB_ROOT_PASSWORD=$(jq -r '.mysql_root_password // ""' "$config_path")
        
        # Load domain arrays properly
        readarray -t MAIN_DOMAINS < <(jq -r '.main_domains[]?' "$config_path" 2>/dev/null)
        readarray -t SUBDOMAINS < <(jq -r '.subdomains[]?' "$config_path" 2>/dev/null)
        readarray -t SUBDIRECTORY_DOMAINS < <(jq -r '.subdirectory_domains[]?' "$config_path" 2>/dev/null)
        
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
    local counter=1
    declare -a domain_options
    local has_domains=false
    
    echo "Available domains from config.json:"
    echo ""
    
    # Add main domains
    if [ ${#MAIN_DOMAINS[@]} -gt 0 ]; then
        echo "A) Main domains:"
        for domain in "${MAIN_DOMAINS[@]}"; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
            has_domains=true
        done
        echo ""
    fi
    
    # Add subdomains
    if [ ${#SUBDOMAINS[@]} -gt 0 ]; then
        echo "B) Subdomains:"
        for domain in "${SUBDOMAINS[@]}"; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
            has_domains=true
        done
        echo ""
    fi
    
    # Add subdirectory domains
    if [ ${#SUBDIRECTORY_DOMAINS[@]} -gt 0 ]; then
        echo "C) Subdirectory domains:"
        for domain in "${SUBDIRECTORY_DOMAINS[@]}"; do
            echo "   $counter) $domain"
            domain_options[$counter]="$domain"
            ((counter++))
            has_domains=true
        done
        echo ""
    fi
    
    if [ "$has_domains" = false ]; then
        echo "No domains found in config.json"
        echo ""
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
    
    # Check if we're in WSL and setup appropriate SSL
    if is_wsl_mode; then
        local wsl_ip=$(get_wsl_ip)
        info "WSL environment detected - using self-signed SSL certificates"
        setup_wsl_ssl "$DOMAIN" "$wsl_ip" "$WEB_ROOT"
        show_wsl_hosts_info "$DOMAIN" "$wsl_ip"
    else
        # Check DNS and setup SSL for regular Linux
        SERVER_IP=$(curl -4 -s ifconfig.me)
        DOMAIN_IP=$(dig +short A $DOMAIN | head -1)
        
        echo ""
        echo "Checking SSL setup..."
        echo "Server IP: $SERVER_IP"
        echo "Domain IP: $DOMAIN_IP"
        
        # Advanced SSL setup with conflict detection
        setup_ssl_with_conflict_detection
    fi
    
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

# Main execution
main() {
    check_root
    load_config
    install_apache_ssl_only
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"