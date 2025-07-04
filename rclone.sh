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
    crontab -l 2>/dev/null | grep -v "/usr/bin/rclone" | crontab - || warn "Failed to remove cron jobs."

    info "Deleting all rclone configurations..."
    rm -rf "$HOME/.config/rclone" || warn "Failed to delete rclone configurations."

    info "Purging rclone package..."
    apt-get remove --purge -y rclone || error "Failed to uninstall rclone."

    success "rclone has been completely uninstalled from the system."
}

# === Remote-Specific Functions ===

select_remote() {
    info "Loading remotes from $CONFIG_FILE"
    [ ! -f "$CONFIG_FILE" ] && error "Configuration file not found: $CONFIG_FILE"

    # Check if config file is valid JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        error "Invalid JSON in configuration file: $CONFIG_FILE"
    fi

    local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE" 2>/dev/null)
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
        
        # Check for null/empty values
        if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" || -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
            error "Selected remote is missing credentials."
        fi
        return 0 # Success
    else
        error "Invalid selection."
    fi
}

configure_remote() {
    info "Starting automated rclone configuration for '$REMOTE_NAME'"
    warn "A browser is required for Google authentication. Copy the link rclone provides."

    # Check if remote already exists
    if rclone listremotes | grep -q "$REMOTE_NAME:"; then
        warn "Remote '$REMOTE_NAME' already exists. This will overwrite it."
        read -p "Continue? (y/n) " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Configuration cancelled."
            return
        fi
    fi

    rclone config create "$REMOTE_NAME" drive \
        client_id="$CLIENT_ID" client_secret="$CLIENT_SECRET" \
        scope=drive team_drive="" service_account_file=""

    if rclone listremotes | grep -q "$REMOTE_NAME:"; then
        success "Configuration for '$REMOTE_NAME' created successfully."
    else
        error "Configuration failed. Check the browser authentication step."
    fi
}

check_sizes() {
    info "Checking local backup size at '$BACKUP_SOURCE'"
    if [ -d "$BACKUP_SOURCE" ]; then
        du -sh "$BACKUP_SOURCE"
    else
        warn "Directory not found: $BACKUP_SOURCE"
    fi
    
    info "Checking total size of remote '$REMOTE_NAME:'"
    if ! rclone size "$REMOTE_NAME:" 2>/dev/null; then
        error "Failed to check remote size. Is the remote properly configured?"
    fi
}

restore_with_browse() {
    info "Interactive restore from '$REMOTE_NAME:'"
    
    # Test if remote is accessible
    if ! rclone lsf "$REMOTE_NAME:" &>/dev/null; then
        error "Cannot access remote '$REMOTE_NAME:'. Please check configuration."
    fi
    
    local current_path="" # Represents path within the remote, e.g., "dir1/subdir"

    while true; do
        # Construct the full path for rclone. Add a trailing slash if path is not empty.
        local rclone_path="$REMOTE_NAME:${current_path:+$current_path/}"
        
        # Get combined list of files and directories with error handling
        local items=()
        if ! mapfile -t items < <(rclone lsf "$rclone_path" 2>/dev/null); then
            error "Failed to list contents of $rclone_path"
        fi
        
        # Separate files and dirs
        local dirs=()
        local files=()
        for item in "${items[@]}"; do
            [[ "$item" == */ ]] && dirs+=("$item") || files+=("$item")
        done

        clear
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "  Browsing: ${YELLOW}$rclone_path${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        
        local i=1
        echo -e "${BLUE}--- Directories ---${NC}"
        if [ ${#dirs[@]} -eq 0 ]; then 
            echo "  (No directories)"
        else
            for dir in "${dirs[@]}"; do 
                echo "  $i) $dir"
                i=$((i+1))
            done
        fi

        echo -e "\n${BLUE}--- Files ---${NC}"
        local file_start_index=$i
        if [ ${#files[@]} -eq 0 ]; then 
            echo "  (No files)"
        else
            for file in "${files[@]}"; do 
                echo "  $i) $file"
                i=$((i+1))
            done
        fi
        
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        [ -n "$current_path" ] && echo "  u) Up one level (..)"
        [ ${#files[@]} -gt 0 ] && echo "  r) Restore files from this directory"
        echo "  q) Quit to menu"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"

        read -p "Select a dir number, or action [u,r,q]: " choice

        case "$choice" in
            q) return ;;
            u)
               if [ -n "$current_path" ]; then
                   current_path=$(dirname "$current_path")
                   # dirname of a single dir is ".", so reset to empty for root.
                   [ "$current_path" == "." ] && current_path=""
               fi
               ;;
            r) [ ${#files[@]} -gt 0 ] && break ;; # Break to file selection
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$file_start_index" ]; then
                     local selected_dir_with_slash=${dirs[choice-1]}
                     local selected_dir=${selected_dir_with_slash%/} # remove trailing slash
                     
                     if [ -z "$current_path" ]; then
                         current_path="$selected_dir"
                     else
                         current_path="$current_path/$selected_dir"
                     fi
                else
                    warn "Invalid selection."; press_enter
                fi
                ;;
        esac
    done

    # --- File Selection logic from here ---
    info "Select files to restore from '${YELLOW}$rclone_path${NC}'"

    local i=1
    for file in "${files[@]}"; do 
        echo "  $i) $file"
        i=$((i+1))
    done

    read -p "Enter file numbers (e.g. '1 3-5'), 'all', or 'q' to cancel: " selection
    if [[ "$selection" == "q" || -z "$selection" ]]; then 
        info "Cancelled."
        return
    fi

    local files_to_restore=()
    if [[ "$selection" == "all" ]]; then
        files_to_restore=("${files[@]}")
    else
        # Clean up selection input
        selection=$(echo "$selection" | sed -e 's/ ,/,/g' -e 's/, / /g' -e 's/,/ /g')
        for part in $selection; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local start=${BASH_REMATCH[1]}
                local end=${BASH_REMATCH[2]}
                for i in $(seq "$start" "$end"); do
                    if [ "$i" -ge 1 ] && [ "$i" -le "${#files[@]}" ]; then
                        local file="${files[i-1]}"
                        # Check if file not already in array
                        if ! printf '%s\n' "${files_to_restore[@]}" | grep -q -x "$file"; then
                            files_to_restore+=("$file")
                        fi
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                if [ "$part" -ge 1 ] && [ "$part" -le "${#files[@]}" ]; then
                    local file="${files[part-1]}"
                    # Check if file not already in array
                    if ! printf '%s\n' "${files_to_restore[@]}" | grep -q -x "$file"; then
                        files_to_restore+=("$file")
                    fi
                fi
            fi
        done
    fi

    if [ ${#files_to_restore[@]} -eq 0 ]; then 
        warn "No valid files selected."
        return
    fi

    info "The following files will be restored to '$BACKUP_SOURCE':"
    for file in "${files_to_restore[@]}"; do 
        echo -e "  - ${CYAN}$file${NC}"
    done
    
    read -p "Proceed? (y/n) " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then 
        info "Restore cancelled."
        return
    fi

    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_SOURCE" || error "Failed to create backup directory: $BACKUP_SOURCE"
    
    # Restore files
    local failed_files=()
    for file in "${files_to_restore[@]}"; do
        info "Restoring: $file"
        if ! rclone copy -v "$rclone_path$file" "$BACKUP_SOURCE" --progress; then
            failed_files+=("$file")
        fi
    done
    
    if [ ${#failed_files[@]} -eq 0 ]; then
        success "All files restored successfully."
    else
        warn "Some files failed to restore:"
        for file in "${failed_files[@]}"; do
            echo -e "  - ${RED}$file${NC}"
        done
    fi
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
    echo -e "          rclone Management for: ${YELLOW}${REMOTE_NAME}${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo "  1) Configure or Re-Configure Remote"
    echo "  2) Check Folder Sizes"
    echo "  3) Restore Backups from Drive (Browse)"
    echo "  4) Back to Main Menu"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
}

manage_remote_loop() {
    while true; do
        select_remote || return 0 # Go back to main if select_remote returns 1
        
        while true; do
            show_remote_menu
            read -p "Select action for '$REMOTE_NAME' (1-4): " choice
            case $choice in
                1) configure_remote ;;
                2) check_sizes ;;
                3) restore_with_browse ;;
                4) break ;; # Break to re-select remote
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