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

# Redis configuration
configure_redis() {
    read -p "Redis memory in GB (default: 1): " REDIS_MAX_MEMORY; [[ -z "$REDIS_MAX_MEMORY" ]] && REDIS_MAX_MEMORY="1"
    
    ! command -v redis-server &>/dev/null && { apt update -y && apt install -y redis-server || error "Redis installation failed"; }
    
    sed -i "/^maxmemory /d" /etc/redis/redis.conf
    echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf
    systemctl restart redis-server && systemctl enable redis-server
    
    success "Redis configured with ${REDIS_MAX_MEMORY}GB memory"
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    echo -e "${YELLOW}Redis Configuration Tool${NC}"
    echo "This tool sets up Redis caching for better performance."
    echo
    configure_redis
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"