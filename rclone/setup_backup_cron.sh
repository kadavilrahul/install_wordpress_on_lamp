#!/bin/bash

# Colors and globals
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BACKUP_SCRIPT="$BASE_DIR/backup_restore/backup_wordpress.sh"
BACKUP_DIR="/website_backups"
RCLONE_LOG="/var/log/rclone.log"
CONFIG_FILE="$BASE_DIR/config.json"

# Utility functions
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }

# Auto-setup backup cron jobs
setup_backup_cron() {
    echo -e "${CYAN}============================================================================="
    echo "                      Auto-Setup Backup Cron Jobs"
    echo -e "=============================================================================${NC}"
    
    # Check backup script
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        error "Backup script not found: $BACKUP_SCRIPT"
    fi
    success "Backup script found"
    
    # Check rclone
    if ! command -v rclone &> /dev/null; then
        error "Rclone not installed. Please install rclone first."
    fi
    success "Rclone installed"
    
    # Check rclone remotes
    local remotes=$(rclone listremotes 2>/dev/null)
    if [ -z "$remotes" ]; then
        error "No rclone remotes configured. Please configure at least one remote first."
    fi
    
    # Auto-select first remote
    local first_remote=$(echo "$remotes" | head -1 | sed 's/:$//')
    info "Using remote: $first_remote"
    
    # Check config file for backup locations
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Config file not found: $CONFIG_FILE"
    fi
    
    # Install jq if needed
    if ! command -v jq &> /dev/null; then
        info "Installing jq..."
        apt update && apt install -y jq
    fi
    
    # Detect which websites actually exist on this server
    local existing_websites=()
    local www_path="/var/www"
    
    if [ -d "$www_path" ]; then
        for site_dir in "$www_path"/*; do
            if [ -d "$site_dir" ]; then
                site_name=$(basename "$site_dir")
                if [ "$site_name" != "html" ]; then
                    # Check if backup location exists in config for this website
                    local backup_path=$(jq -r ".backup_locations[\"$site_name\"] // empty" "$CONFIG_FILE" 2>/dev/null)
                    if [ -n "$backup_path" ]; then
                        existing_websites+=("$site_name:$backup_path")
                        info "Found website: $site_name → $backup_path"
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#existing_websites[@]} -eq 0 ]; then
        error "No websites found on this server that match config backup locations"
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    success "Backup directory created: $BACKUP_DIR"
    
    # Current crontab
    local current_crons=$(crontab -l 2>/dev/null || echo "")
    
    # Remove existing backup crons
    local new_crons=$(echo "$current_crons" | grep -v "$BACKUP_SCRIPT" | grep -v "rclone.*$BACKUP_DIR")
    
    # Show backup script menu to user first
    echo
    echo -e "${CYAN}Let's see what backup options are available...${NC}"
    echo "1" | timeout 10 bash "$BACKUP_SCRIPT" 2>/dev/null | grep -A 10 "Available WordPress Sites:" | head -15
    
    echo
    echo -e "${YELLOW}Backup Selection for Cron Job:${NC}"
    echo "----------------------------------------"
    echo "  1) Select specific site (option 1)"
    echo "  2) Backup ALL websites (option 2)"
    echo "  3) Custom option number"
    echo "----------------------------------------"
    
    read -p "Choose backup method for cron (1-3): " backup_method
    
    local backup_command=""
    case $backup_method in
        1)
            backup_command="echo \"1\" | bash $BACKUP_SCRIPT"
            info "Selected: Backup first discovered site"
            ;;
        2)
            backup_command="echo \"2\" | bash $BACKUP_SCRIPT"
            info "Selected: Backup ALL websites"
            ;;
        3)
            read -p "Enter option number to auto-select: " option_num
            if [[ "$option_num" =~ ^[0-9]+$ ]]; then
                backup_command="echo \"$option_num\" | bash $BACKUP_SCRIPT"
                info "Selected: Auto-select option $option_num"
            else
                error "Invalid option number"
            fi
            ;;
        *)
            error "Invalid selection"
            ;;
    esac
    
    # Add backup cron
    if [ -n "$new_crons" ]; then
        new_crons="$new_crons"$'\n'
    fi
    new_crons="${new_crons}30 02 * * * $backup_command"$'\n'
    
    # Add rclone crons only for existing websites
    for website_info in "${existing_websites[@]}"; do
        local website=$(echo "$website_info" | cut -d: -f1)
        local backup_path=$(echo "$website_info" | cut -d: -f2)
        local remote_path="${first_remote}:${backup_path}"
        new_crons="${new_crons}00 04 * * * /usr/bin/rclone copy $BACKUP_DIR ${remote_path} --include=\"*${website}*\" --log-file=$RCLONE_LOG"$'\n'
    done
    
    # Add cleanup cron
    new_crons="${new_crons}05 04 * * * find $BACKUP_DIR -type f -exec rm -f {} \\;"
    
    # Install crontab
    echo "$new_crons" | crontab -
    
    if [ $? -eq 0 ]; then
        success "Backup cron jobs configured successfully!"
        echo
        echo -e "${GREEN}Scheduled Tasks:${NC}"
        echo -e "${BLUE}• 2:30 AM daily: WordPress backup (automated selection)${NC}"
        echo -e "${BLUE}• 4:00 AM daily: Upload to website-specific remote paths${NC}"
        echo -e "${BLUE}• 4:05 AM daily: Cleanup local backup files${NC}"
        echo
        echo -e "${YELLOW}Remote: $first_remote${NC}"
        echo -e "${YELLOW}Backup dir: $BACKUP_DIR${NC}"
        echo -e "${YELLOW}Log file: $RCLONE_LOG${NC}"
        echo
        echo -e "${CYAN}Active backup locations:${NC}"
        for website_info in "${existing_websites[@]}"; do
            local website=$(echo "$website_info" | cut -d: -f1)
            local backup_path=$(echo "$website_info" | cut -d: -f2)
            echo -e "${BLUE}• $website → $first_remote:$backup_path${NC}"
        done
    else
        error "Failed to configure cron jobs"
    fi
    
    echo
    echo -e "${CYAN}Current backup cron jobs:${NC}"
    crontab -l | grep -E "(backup_wordpress|rclone)"
}

# Main execution
main() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
    
    setup_backup_cron
    echo
    read -p "Press Enter to continue..."
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"