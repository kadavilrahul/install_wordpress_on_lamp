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

# Main execution
main() {
    check_root
    system_status_check
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"