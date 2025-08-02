#!/bin/bash

#================================================================================
# rclone Installation Status & Overview Script
#================================================================================

# --- Globals & Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/config.json"
BACKUP_SOURCE="/website_backups"
LOG_DIR="/var/log"

# --- Utility Functions ---
info() { echo -e "${BLUE}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }

press_enter() { read -p $'\nPress [Enter] to continue...' "$@"; }

check_root() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root (e.g., 'sudo ./rclone.sh')"
}

show_rclone_status() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo "                         rclone Installation Status"
    echo -e "${CYAN}======================================================================${NC}"
    
    # Check rclone installation
    if command -v rclone &>/dev/null; then
        local rclone_version=$(rclone version --check=false 2>/dev/null | head -n 1 | cut -d' ' -f2 || echo "unknown")
        success "rclone is installed (version: $rclone_version)"
        echo "  Location: $(which rclone)"
    else
        warn "rclone is NOT installed"
    fi
    
    # Check jq installation
    if command -v jq &>/dev/null; then
        local jq_version=$(jq --version 2>/dev/null || echo "unknown")
        success "jq is installed ($jq_version)"
    else
        warn "jq is NOT installed (required for config management)"
    fi
    
    echo
    echo -e "${CYAN}=== Configuration Status ===${NC}"
    
    # Check config file
    if [ -f "$CONFIG_FILE" ]; then
        success "Configuration file exists: $CONFIG_FILE"
        
        # Validate JSON
        if jq empty "$CONFIG_FILE" 2>/dev/null; then
            success "Configuration file is valid JSON"
            
            # Count defined remotes
            local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
            if [ "$num_remotes" -gt 0 ]; then
                success "$num_remotes remote(s) defined in config"
            else
                warn "No remotes defined in rclone_remotes array"
            fi
        else
            error "Configuration file contains invalid JSON"
        fi
    else
        warn "Configuration file not found: $CONFIG_FILE"
    fi
    
    echo
    echo -e "${CYAN}=== Configured Remotes Status ===${NC}"
    
    # Check if rclone is installed before checking remotes
    if command -v rclone &>/dev/null; then
        local configured_remotes=$(rclone listremotes 2>/dev/null || echo "")
        if [ -n "$configured_remotes" ]; then
            success "rclone configured remotes found:"
            echo "$configured_remotes" | while read -r remote; do
                if [ -n "$remote" ]; then
                    echo "  - $remote"
                    # Test remote accessibility
                    local remote_name=${remote%:}
                    if timeout 10 rclone lsf "$remote" --max-depth 1 &>/dev/null; then
                        echo -e "    ${GREEN}✓ Accessible${NC}"
                    else
                        echo -e "    ${RED}✗ Not accessible (check auth)${NC}"
                    fi
                fi
            done
        else
            warn "No rclone remotes are currently configured"
        fi
    else
        warn "Cannot check configured remotes - rclone not installed"
    fi
    
    echo
    echo -e "${CYAN}=== Backup Directory Status ===${NC}"
    if [ -d "$BACKUP_SOURCE" ]; then
        success "Backup directory exists: $BACKUP_SOURCE"
        local backup_size=$(du -sh "$BACKUP_SOURCE" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  Size: $backup_size"
        local file_count=$(find "$BACKUP_SOURCE" -type f 2>/dev/null | wc -l || echo "unknown")
        echo "  Files: $file_count"
    else
        warn "Backup directory does not exist: $BACKUP_SOURCE"
    fi
}

# Main execution
main() {
    check_root
    show_rclone_status
    press_enter
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"