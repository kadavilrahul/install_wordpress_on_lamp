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

# Main execution
main() {
    check_root
    echo -e "${YELLOW}Miscellaneous Tools${NC}"
    echo "This tool provides additional utilities and system tools."
    echo
    echo "Available tools:"
    echo "1) Adjust PHP Configuration"
    echo "2) Launch miscellaneous.sh"
    echo "3) Back"
    echo
    read -p "Select option (1-3): " choice
    
    case $choice in
        1) adjust_php_config ;;
        2) bash "$(dirname "${BASH_SOURCE[0]}")/miscellaneous.sh" ;;
        3) return ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"