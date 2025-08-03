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

# Main execution
main() {
    check_root
    echo -e "${YELLOW}Apache Configuration Repair Tool${NC}"
    echo "This tool repairs broken Apache virtual host configurations."
    echo
    fix_all_apache_configs
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"