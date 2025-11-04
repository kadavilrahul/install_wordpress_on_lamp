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
    for service in apache2 mysql postgresql redis-server; do
        systemctl is-active --quiet "$service" && echo -e "$service: ${GREEN}Running${NC}" || echo -e "$service: ${RED}Stopped${NC}"
    done
    echo
    
    # Database Status
    echo -e "${CYAN}=== Database Status ===${NC}"
    # MySQL databases
    mysql_databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "^Database$" | grep -v "^information_schema$" | grep -v "^performance_schema$" | grep -v "^mysql$" | wc -l 2>/dev/null || echo "0")
    echo -e "MySQL: ${GREEN}Running${NC} | ${mysql_databases} databases"
    
    # PostgreSQL databases
    if systemctl is-active --quiet postgresql; then
        postgres_databases=$(sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -v "^\s*$" | grep -v "^\s*template" | grep -v "^\s*postgres$" | wc -l)
        postgres_db_list=$(sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -v "^\s*$" | grep -v "^\s*template" | grep -v "^\s*postgres$" | tr '\n' ',' | sed 's/,$//')
        echo -e "PostgreSQL: ${GREEN}Running${NC} | ${postgres_databases} databases (${postgres_db_list})"
    else
        echo -e "PostgreSQL: ${RED}Stopped${NC}"
    fi
    echo
    echo -e "${CYAN}=== Website Status ===${NC}"
    
    # WordPress Websites
    echo -e "${YELLOW}WordPress Websites:${NC}"
    local wp_count=0
    [ -d "/var/www" ] && for site in /var/www/*; do
        if [ -d "$site" ] && [ -f "$site/wp-config.php" ]; then
            local domain=$(basename "$site")
            [ "$domain" = "html" ] && continue
            
            # Check SSL status
            local ssl_status=""
            if apache2ctl -S 2>/dev/null | grep -q "$domain.*443"; then
                ssl_status=" - SSL"
            fi
            
            echo -e "  $((++wp_count)). $domain - ${GREEN}Active${NC} (MySQL)${ssl_status}"
        fi
    done
    [ $wp_count -eq 0 ] && echo "  No WordPress websites found"
    
    # Static Websites
    echo -e "${YELLOW}Static Websites:${NC}"
    local static_count=0
    [ -d "/var/www" ] && for site in /var/www/*; do
        if [ -d "$site" ]; then
            local domain=$(basename "$site")
            [ "$domain" = "html" ] && continue
            [ -f "$site/wp-config.php" ] && continue
            
            # Check if it's a static site
            if [ -f "$site/index.html" ] || [ -f "$site/index.php" ] || [ -n "$(find "$site" -maxdepth 2 -name \"*.html\" -o -name \"*.php\" -o -name \"*.css\" -o -name \"*.js\" 2>/dev/null | head -1)" ]; then
                local db_type=""
                if [ -f "$site/config.json" ] && command -v jq >/dev/null && jq -e '.database' "$site/config.json" >/dev/null 2>&1; then
                    db_type="PostgreSQL"
                fi
                
                # Check SSL status
                local ssl_status=""
                if apache2ctl -S 2>/dev/null | grep -q "$domain.*443"; then
                    ssl_status=" - SSL"
                fi
                
                echo -e "  $((++static_count)). $domain - ${GREEN}Active${NC}${db_type:+ ($db_type)}${ssl_status}"
            fi
        fi
    done
    [ $static_count -eq 0 ] && echo "  No static websites found"
    
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    system_status_check
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"