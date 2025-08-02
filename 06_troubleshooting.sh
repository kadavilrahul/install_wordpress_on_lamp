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

# Check for maintenance file
check_maintenance_file() {
    local site_path="$1"
    if [ -f "$site_path/.maintenance" ]; then
        warn "Maintenance file detected at '$site_path/.maintenance'. This could be the reason for the maintenance page."
    else
        info "No .maintenance file found at '$site_path/.maintenance'."
    fi
}

# Main execution
main() {
    check_root
    echo -e "${YELLOW}Troubleshooting Tool${NC}"
    echo "This tool helps diagnose and fix common website issues."
    echo
    echo "Available troubleshooting options:"
    echo "1) Check maintenance file"
    echo "2) Launch troubleshooting.sh"
    echo "3) Back"
    echo
    read -p "Select option (1-3): " choice
    
    case $choice in
        1) 
            read -p "Enter website path (e.g., /var/www/example.com): " site_path
            check_maintenance_file "$site_path"
            read -p "Press Enter to continue..."
            ;;
        2) bash "$(dirname "${BASH_SOURCE[0]}")/troubleshooting.sh" ;;
        3) return ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"