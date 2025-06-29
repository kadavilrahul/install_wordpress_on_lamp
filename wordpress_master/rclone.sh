#!/bin/bash

#================================================================================
# rclone Multi-Remote Management Script for Google Drive
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

# === Global rclone Functions ===

install_rclone_package() {
    info "Installing rclone package..."
    if command -v rclone &>/dev/null; then
        warn "rclone is already installed."
    else
        apt-get update && apt-get install -y rclone || error "Failed to install rclone."
        success "rclone package installed successfully."
    fi

    if ! command -v jq &>/dev/null; then
        info "Installing jq..."
        apt-get install -y jq || error "Failed to install jq."
    fi
}

uninstall_rclone_package() {
    warn "This will UNINSTALL the rclone package and DELETE ALL remotes and cron jobs."
    read -p "Are you sure you want to completely uninstall rclone? (y/n) " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Uninstallation cancelled."
        return
    fi
    info "Removing all rclone-related cron jobs..."
    crontab -l 2>/dev/null | grep -v "/usr/bin/rclone" | crontab -

    info "Deleting all rclone configurations..."
    rm -rf "$HOME/.config/rclone"

    info "Purging rclone package..."
    apt-get remove --purge -y rclone
    success "rclone has been completely uninstalled from the system."
}


# === Remote-Specific Functions ===

select_remote() {
    info "Loading remotes from $CONFIG_FILE"
    [ ! -f "$CONFIG_FILE" ] && error "Configuration file not found: $CONFIG_FILE"

    local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE")
    [ "$num_remotes" -eq 0 ] && error "No remotes defined in 'rclone_remotes' array."

    echo -e "${YELLOW}Please select a remote to manage:${NC}"
    jq -r '.rclone_remotes[] | .remote_name' "$CONFIG_FILE" | nl
    
    local last_option=$((num_remotes + 1))
    echo "$last_option) Back to Main Menu"

    read -p "Enter number (1-$last_option): " choice
    if [ "$choice" -eq "$last_option" ]; then
        return 1 # Signal to go back
    fi

    if [ "$choice" -ge 1 ] && [ "$choice" -le "$num_remotes" ]; then
        local index=$((choice - 1))
        CLIENT_ID=$(jq -r ".rclone_remotes[$index].client_id" "$CONFIG_FILE")
        CLIENT_SECRET=$(jq -r ".rclone_remotes[$index].client_secret" "$CONFIG_FILE")
        REMOTE_NAME=$(jq -r ".rclone_remotes[$index].remote_name" "$CONFIG_FILE")
        LOG_FILE="$LOG_DIR/rclone_${REMOTE_NAME}.log"
        [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] && error "Selected remote is missing credentials."
        return 0 # Success
    else
        error "Invalid selection."
    fi
}
configure_remote() {
    info "Starting automated rclone configuration for '$REMOTE_NAME'"
    warn "A browser is required for Google authentication. Copy the link rclone provides."

    rclone config create "$REMOTE_NAME" drive \
        client_id="$CLIENT_ID" client_secret="$CLIENT_SECRET" \
        scope=drive team_drive="" service_account_file=""

    if rclone listremotes | grep -q "$REMOTE_NAME:"; then
        success "Configuration for '$REMOTE_NAME' created successfully."
    else
        error "Configuration failed. Check the browser authentication step."
    fi
}

verify_setup() {
    info "Verifying setup for remote '$REMOTE_NAME:'"
    ! rclone listremotes | grep -q "$REMOTE_NAME:" && \
        error "Remote not found. Run 'Configure or Re-Configure' first."
    
    echo -e "${CYAN}--- Root Directories ---${NC}"; rclone lsf "$REMOTE_NAME:" --dirs-only
    echo -e "${CYAN}--- Remotes (lsd) ---${NC}"; rclone lsd "$REMOTE_NAME:"
    echo -e "${CYAN}--- Files (lsl, first 10) ---${NC}"; rclone lsl "$REMOTE_NAME:" | head -n 10
}

check_sizes() {
    info "Checking local backup size at '$BACKUP_SOURCE'";
    [ -d "$BACKUP_SOURCE" ] && du -sh "$BACKUP_SOURCE" || warn "Directory not found."
    info "Checking total size of remote '$REMOTE_NAME:'";
    rclone size "$REMOTE_NAME:"
}

sync_to_drive() {
    warn "This makes the remote identical to the local source. Remote-only files will be DELETED."
    read -p "Sync '$BACKUP_SOURCE' to '$REMOTE_NAME:'? (y/n) " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$BACKUP_SOURCE"; rclone sync "$BACKUP_SOURCE" "$REMOTE_NAME:" --progress
        success "Sync completed."
    fi
}

restore_from_drive() {
    warn "This makes the local directory identical to the remote. Local-only files will be DELETED."
    read -p "Sync '$REMOTE_NAME:' to '$BACKUP_SOURCE'? (y/n) " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$BACKUP_SOURCE"; rclone sync -v "$REMOTE_NAME:" "$BACKUP_SOURCE" --progress
        success "Restore completed."
    fi
}

setup_cron() {
    info "Setting up daily cron job for '$REMOTE_NAME'..."
    local cron_cmd="/usr/bin/rclone copy $BACKUP_SOURCE \"$REMOTE_NAME:\" --log-file=$LOG_FILE"
    local cron_job="0 5 */1 * * $cron_cmd"
    
    (crontab -l 2>/dev/null | grep -vF "$cron_cmd"; echo "$cron_job") | crontab -
    
    if crontab -l | grep -qF "$cron_cmd"; then
        success "Cron job set successfully:"; crontab -l | grep -F "$cron_cmd"
    else
        error "Failed to set cron job."
    fi
}

delete_remote() {
    warn "This will remove the rclone remote '$REMOTE_NAME' and its associated cron job."
    read -p "Are you sure? (y/n) " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && info "Cancelled." && return
    info "Removing cron job for '$REMOTE_NAME'..."
    crontab -l 2>/dev/null | grep -vE "/usr/bin/rclone .*$REMOTE_NAME:" | crontab -
    info "Deleting remote '$REMOTE_NAME'..."; rclone config delete "$REMOTE_NAME"
    success "Remote and cron job removed. The rclone package is still installed."
}

# === Menu System ===

show_main_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo "                         rclone Management - Main Menu"
    echo -e "${CYAN}======================================================================${NC}"
    echo "  1) Install rclone Package"
    echo "  2) Manage a Website Remote"
    echo "  3) Uninstall rclone Package (Deletes Everything)"
    echo "  4) Exit"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
}

show_remote_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo "          rclone Management for: ${YELLOW}${REMOTE_NAME}${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo "  1) Configure or Re-Configure Remote"
    echo "  2) Verify Setup (List Files)"
    echo "  3) Check Folder Sizes"
    echo "  4) Sync from Server TO Google Drive"
    echo "  5) Sync FROM Google Drive to Server"
    echo "  6) Setup Daily Backup Cron Job"
    echo "  7) Delete This Remote & Its Cron Job"
    echo "  8) Back to Main Menu"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
}

manage_remote_loop() {
    while true; do
        select_remote || return 0 # Go back to main if select_remote returns 1
        
        while true; do
            show_remote_menu
            read -p "Select action for '$REMOTE_NAME' (1-8): " choice
            case $choice in
                1) configure_remote ;;
                2) verify_setup ;;
                3) check_sizes ;;
                4) sync_to_drive ;;
                5) restore_from_drive ;;
                6) setup_cron ;;
                7) delete_remote; break ;; # Break to re-select remote
                8) break ;; # Break to re-select remote
                *) warn "Invalid option." ;;
            esac
            press_enter
        done
    done
}

main() {
    check_root
    while true; do
        show_main_menu
        read -p "Select option (1-4): " choice
        case $choice in
            1) install_rclone_package ;;
            2) manage_remote_loop ;;
            3) uninstall_rclone_package ;;
            4) break ;;
            *) warn "Invalid option." ;;
        esac
        press_enter
    done
    info "Exiting."
}

main "$@"