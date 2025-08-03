#!/bin/bash

#================================================================================
# rclone Show Existing Remotes Details Script
#================================================================================

# --- Globals & Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config.json"
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

show_existing_remotes() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo "                         Existing rclone Remotes"
    echo -e "${CYAN}======================================================================${NC}"
    
    # Check from config.json
    echo -e "${YELLOW}=== Remotes defined in config.json ===${NC}"
    if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
        local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        if [ "$num_remotes" -gt 0 ]; then
            jq -r '.rclone_remotes[] | "Remote: \(.remote_name)\n  Client ID: \(.client_id)\n  Client Secret: \(.client_secret[0:20])...\n"' "$CONFIG_FILE" 2>/dev/null
        else
            warn "No remotes defined in config.json"
        fi
    else
        warn "Config file not found or invalid JSON"
    fi
    
    echo
    echo -e "${YELLOW}=== Actually configured rclone remotes ===${NC}"
    
    if command -v rclone &>/dev/null; then
        local configured_remotes=$(rclone listremotes 2>/dev/null || echo "")
        if [ -n "$configured_remotes" ]; then
            echo "$configured_remotes" | while read -r remote; do
                if [ -n "$remote" ]; then
                    local remote_name=${remote%:}
                    echo -e "${GREEN}Remote: $remote${NC}"
                    
                    # Get remote type and some config details
                    local remote_type=$(rclone config show "$remote_name" 2>/dev/null | grep "type" | cut -d'=' -f2 | tr -d ' ' || echo "unknown")
                    echo "  Type: $remote_type"
                    
                    # Test accessibility
                    if timeout 10 rclone lsf "$remote" --max-depth 1 &>/dev/null; then
                        echo -e "  Status: ${GREEN}✓ Accessible${NC}"
                        
                        # Get storage usage if accessible
                        local usage=$(timeout 10 rclone about "$remote" 2>/dev/null | grep "Total:" | awk '{print $2, $3}' || echo "unknown")
                        if [ "$usage" != "unknown" ]; then
                            echo "  Storage Used: $usage"
                        fi
                    else
                        echo -e "  Status: ${RED}✗ Not accessible${NC}"
                    fi
                    echo
                fi
            done
        else
            warn "No rclone remotes are currently configured"
            echo "Use option 1 to install rclone, then option 2 to configure remotes."
        fi
    else
        warn "rclone is not installed"
        echo "Use option 1 to install rclone first."
    fi
}

# Main execution
main() {
    check_root
    show_existing_remotes
    press_enter
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"