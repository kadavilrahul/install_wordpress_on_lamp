#!/bin/bash

#================================================================================
# rclone Manage Website Remote Script
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

    # Get the default remote name from the first entry
    local default_remote=$(jq -r '.rclone_remotes[0].remote_name // "server_backup"' "$CONFIG_FILE" 2>/dev/null)
    
    # If there's only one remote, auto-select it without prompting
    if [ "$num_remotes" -eq 1 ]; then
        info "Auto-selecting remote: $default_remote"
        CLIENT_ID=$(jq -r ".rclone_remotes[0].client_id" "$CONFIG_FILE")
        CLIENT_SECRET=$(jq -r ".rclone_remotes[0].client_secret" "$CONFIG_FILE")
        REMOTE_NAME=$(jq -r ".rclone_remotes[0].remote_name" "$CONFIG_FILE")
        LOG_FILE="$LOG_DIR/rclone_${REMOTE_NAME}.log"
        
        # Check for null/empty values
        if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" || -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
            error "Selected remote is missing credentials."
        fi
        return 0 # Success
    fi

    # Multiple remotes - show selection menu
    echo -e "${YELLOW}Please select name of remote. Default $default_remote:${NC}"
    jq -r '.rclone_remotes[] | .remote_name' "$CONFIG_FILE" | nl
    
    echo "0) Back to main menu"

    read -p "Enter number (1-$num_remotes, 0 to go back): " choice
    if [ "$choice" -eq 0 ]; then
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

browse_remote_folders() {
    local current_path=""
    local selected_path=""
    
    while true; do
        # Construct the full path for rclone
        local rclone_path="$REMOTE_NAME:${current_path:+$current_path/}"
        
        # Get combined list of files and directories
        local items=()
        echo "🔍 Loading folders from $rclone_path..."
        if ! mapfile -t items < <(rclone lsf "$rclone_path" 2>/dev/null); then
            error "❌ Failed to list contents of $rclone_path. Please check your remote connection."
        fi
        
        # Separate directories (ignore files for folder selection)
        local dirs=()
        for item in "${items[@]}"; do
            [[ "$item" == */ ]] && dirs+=("$item")
        done
        
        # Debug: Show what we found
        echo "📊 Found ${#items[@]} total items, ${#dirs[@]} directories"
        sleep 1

        clear
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "  📁 Browse Remote Folders: ${YELLOW}$rclone_path${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "${GREEN}📂 Current Location: ${YELLOW}${current_path:-"Root Directory"}${NC}"
        echo
        
        local i=1
        echo -e "${BLUE}📂 Available Folders:${NC}"
        if [ ${#dirs[@]} -eq 0 ]; then 
            echo "     (No folders found - you can create one or select this location)"
            max_folder_num=0
        else
            for dir in "${dirs[@]}"; do 
                echo "     $i) 📁 ${dir%/}"
                i=$((i+1))
            done
            max_folder_num=$((i-1))
        fi
        
        echo
        echo -e "${CYAN}📋 Available Actions:${NC}"
        [ -n "$current_path" ] && echo "     u) ⬆️  Go up one level (to parent folder)"
        echo "     s) ✅ SELECT this folder as destination"
        echo "     c) ➕ Create new folder here"
        echo "     q) ❌ Cancel and go back"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo -e "${YELLOW}💡 How to use:${NC}"
        if [ $max_folder_num -gt 0 ]; then
            echo "   📁 Enter a number (1-$max_folder_num) to open that folder"
        fi
        echo "   ✅ Enter 's' to use this location as destination"
        echo "   ➕ Enter 'c' to create a new folder here"
        [ -n "$current_path" ] && echo "   ⬆️  Enter 'u' to go back to parent folder"
        echo "   ❌ Enter 'q' to cancel"
        echo -e "${CYAN}----------------------------------------------------------------------${NC}"
        echo

        read -p "Choose your option: " choice

        case "$choice" in
            q) return 1 ;;
            u)
               if [ -n "$current_path" ]; then
                   current_path=$(dirname "$current_path")
                   [ "$current_path" == "." ] && current_path=""
               fi
               ;;
            s) 
               selected_path="$current_path"
               echo
               echo -e "${GREEN}✅ Selected Destination:${NC}"
               echo -e "   📁 ${YELLOW}$REMOTE_NAME:${selected_path:+$selected_path/}${NC}"
               echo
               read -p "Confirm this destination? (y/n): " confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   echo "$selected_path"
                   return 0
               fi
               ;;
            c)
               echo
               read -p "📝 Enter new folder name: " new_folder
               if [ -n "$new_folder" ]; then
                   local new_path="$REMOTE_NAME:${current_path:+$current_path/}$new_folder"
                   echo "Creating folder '$new_folder'..."
                   if rclone mkdir "$new_path" 2>/dev/null; then
                       success "✅ Created folder: $new_folder"
                       echo "📂 Navigating into the new folder..."
                       if [ -z "$current_path" ]; then
                           current_path="$new_folder"
                       else
                           current_path="$current_path/$new_folder"
                       fi
                   else
                       warn "❌ Failed to create folder: $new_folder"
                   fi
                   read -p "Press Enter to continue..."
               fi
               ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#dirs[@]} ]; then
                     local selected_dir_with_slash=${dirs[choice-1]}
                     local selected_dir=${selected_dir_with_slash%/}
                     
                     echo "📂 Navigating into folder: $selected_dir"
                     
                     if [ -z "$current_path" ]; then
                         current_path="$selected_dir"
                     else
                         current_path="$current_path/$selected_dir"
                     fi
                else
                    echo
                    warn "❌ Invalid selection. Please choose a valid option."
                    read -p "Press Enter to try again..."
                fi
                ;;
        esac
    done
}

copy_backups_to_remote() {
    info "Copy local backups to remote '$REMOTE_NAME:'"
    
    # Test if remote is accessible
    if ! rclone lsf "$REMOTE_NAME:" &>/dev/null; then
        error "Cannot access remote '$REMOTE_NAME:'. Please check configuration."
    fi
    
    # Check if backup directory exists
    if [ ! -d "$BACKUP_SOURCE" ]; then
        error "Backup directory not found: $BACKUP_SOURCE"
    fi
    
    # Get list of backup files
    local backup_files=()
    mapfile -t backup_files < <(find "$BACKUP_SOURCE" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.sql" -o -name "*.dump" \) 2>/dev/null | sort)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        warn "No backup files found in $BACKUP_SOURCE"
        return
    fi
    
    # Show available backup files
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "  Available Backup Files in: ${YELLOW}$BACKUP_SOURCE${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    
    local i=1
    for file in "${backup_files[@]}"; do
        local filename=$(basename "$file")
        local filesize=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  $i) $filename ($filesize)"
        i=$((i+1))
    done
    
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo "  $i) Select ALL backup files"
    echo "  q) Cancel"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    
    read -p "Enter file numbers (e.g. '1 3-5'), 'all', or 'q' to cancel: " selection
    if [[ "$selection" == "q" || -z "$selection" ]]; then 
        info "Cancelled."
        return
    fi
    
    local files_to_copy=()
    if [[ "$selection" == "all" || "$selection" == "$i" ]]; then
        files_to_copy=("${backup_files[@]}")
    else
        # Parse selection similar to restore function
        selection=$(echo "$selection" | sed -e 's/ ,/,/g' -e 's/, / /g' -e 's/,/ /g')
        for part in $selection; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local start=${BASH_REMATCH[1]}
                local end=${BASH_REMATCH[2]}
                for j in $(seq "$start" "$end"); do
                    if [ "$j" -ge 1 ] && [ "$j" -le "${#backup_files[@]}" ]; then
                        local file="${backup_files[j-1]}"
                        if ! printf '%s\n' "${files_to_copy[@]}" | grep -q -x "$file"; then
                            files_to_copy+=("$file")
                        fi
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                if [ "$part" -ge 1 ] && [ "$part" -le "${#backup_files[@]}" ]; then
                    local file="${backup_files[part-1]}"
                    if ! printf '%s\n' "${files_to_copy[@]}" | grep -q -x "$file"; then
                        files_to_copy+=("$file")
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#files_to_copy[@]} -eq 0 ]; then 
        warn "No valid files selected."
        return
    fi
    
    # Show selected files
    info "Selected files to copy:"
    for file in "${files_to_copy[@]}"; do 
        echo -e "  - ${CYAN}$(basename "$file")${NC}"
    done
    echo
    
    # Destination folder selection
    echo
    info "🌐 Choose destination folder on your remote Drive:"
    echo -e "${CYAN}======================================================================${NC}"
    echo "  1) Upload to Root Directory (server_backup:)"
    echo "  2) Upload to 'Backups' folder (server_backup:Backups/)"
    echo "  3) Create custom folder name"
    echo "  4) Advanced folder browser (navigate existing folders)"
    echo "  0) Cancel upload"
    echo -e "${CYAN}======================================================================${NC}"
    read -p "Select destination option (1-4, 0 to cancel): " dest_choice
    
    local dest_path=""
    local full_dest_path=""
    
    case $dest_choice in
        1)
            dest_path=""
            full_dest_path="$REMOTE_NAME:"
            info "✅ Selected: Root directory ($full_dest_path)"
            ;;
        2)
            dest_path="Backups"
            full_dest_path="$REMOTE_NAME:Backups/"
            info "✅ Selected: Backups folder ($full_dest_path)"
            echo "📁 Creating Backups folder if it doesn't exist..."
            rclone mkdir "$full_dest_path" 2>/dev/null || true
            ;;
        3)
            read -p "📝 Enter custom folder name: " custom_folder
            if [ -n "$custom_folder" ]; then
                dest_path="$custom_folder"
                full_dest_path="$REMOTE_NAME:$custom_folder/"
                info "✅ Selected: Custom folder ($full_dest_path)"
                echo "📁 Creating '$custom_folder' folder..."
                rclone mkdir "$full_dest_path" 2>/dev/null || warn "Failed to create folder"
            else
                warn "❌ No folder name provided, using root directory"
                dest_path=""
                full_dest_path="$REMOTE_NAME:"
            fi
            ;;
        4)
            info "🔍 Starting advanced folder browser..."
            echo
            if dest_path=$(browse_remote_folders); then
                full_dest_path="$REMOTE_NAME:${dest_path:+$dest_path/}"
            else
                info "❌ Folder browser cancelled."
                return
            fi
            ;;
        0)
            info "❌ Upload cancelled."
            return
            ;;
        *)
            warn "❌ Invalid option, using root directory"
            dest_path=""
            full_dest_path="$REMOTE_NAME:"
            ;;
    esac
    
    if [ -n "$full_dest_path" ]; then
        info "📁 Final destination: $full_dest_path"
        read -p "Proceed with upload? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then 
            info "Copy cancelled."
            return
        fi
        
        # Copy files
        local failed_files=()
        for file in "${files_to_copy[@]}"; do
            local filename=$(basename "$file")
            info "Copying: $filename"
            if ! rclone copy -v "$file" "$full_dest_path" --progress; then
                failed_files+=("$filename")
            fi
        done
        
        if [ ${#failed_files[@]} -eq 0 ]; then
            success "All files copied successfully to $full_dest_path"
        else
            warn "Some files failed to copy:"
            for file in "${failed_files[@]}"; do
                echo -e "  - ${RED}$file${NC}"
            done
        fi
    else
        info "Destination selection cancelled."
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
        [ -n "$current_path" ] && echo "  u) Up one level (..) - Go back to parent directory"
        [ ${#files[@]} -gt 0 ] && echo "  r) Restore files from this directory - Select and download files"
        echo "  q) Quit to menu - Exit browsing and return to main menu"
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
            r) 
                if [ ${#files[@]} -gt 0 ]; then
                    # File selection integrated into the current display
                    echo -e "\n${GREEN}Select files to restore (from the files shown above):${NC}"
                    read -p "Enter file numbers (e.g. '1 3-5'), 'all', or 'q' to cancel: " selection
                    
                    if [[ "$selection" == "q" || -z "$selection" ]]; then 
                        info "Cancelled."
                        continue
                    fi

                    local files_to_restore=()
                    if [[ "$selection" == "all" ]]; then
                        files_to_restore=("${files[@]}")
                    else
                        # Parse selection
                        selection=$(echo "$selection" | sed -e 's/ ,/,/g' -e 's/, / /g' -e 's/,/ /g')
                        for part in $selection; do
                            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                                local start=${BASH_REMATCH[1]}
                                local end=${BASH_REMATCH[2]}
                                for j in $(seq "$start" "$end"); do
                                    local file_index=$((j - file_start_index + 1))
                                    if [ "$file_index" -ge 1 ] && [ "$file_index" -le "${#files[@]}" ]; then
                                        local file="${files[file_index-1]}"
                                        if ! printf '%s\n' "${files_to_restore[@]}" | grep -q -x "$file"; then
                                            files_to_restore+=("$file")
                                        fi
                                    fi
                                done
                            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                                local file_index=$((part - file_start_index + 1))
                                if [ "$file_index" -ge 1 ] && [ "$file_index" -le "${#files[@]}" ]; then
                                    local file="${files[file_index-1]}"
                                    if ! printf '%s\n' "${files_to_restore[@]}" | grep -q -x "$file"; then
                                        files_to_restore+=("$file")
                                    fi
                                fi
                            fi
                        done
                    fi

                    if [ ${#files_to_restore[@]} -eq 0 ]; then 
                        warn "No valid files selected."
                        read -p "Press Enter to continue..." 
                        continue
                    fi

                    info "The following files will be restored to '$BACKUP_SOURCE':"
                    for file in "${files_to_restore[@]}"; do 
                        echo -e "  - ${CYAN}$file${NC}"
                    done
                    
                    read -p "Proceed? (y/n) " -n 1 -r; echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then 
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
                        read -p "Press Enter to continue..."
                        return # Exit restore function after successful restore
                    else
                        info "Restore cancelled."
                    fi
                fi
                ;;  
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
}

# === Menu System ===

show_remote_menu() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "          rclone Management for: ${YELLOW}${REMOTE_NAME}${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo "  1) Configure or Re-Configure Remote - Set up Google Drive authentication"
    echo "  2) Check Folder Sizes - View local and remote storage usage"
    echo "  3) Copy Backups to Remote - Upload local backups to Drive folder"
    echo "  4) Restore Backups from Drive (Browse) - Download backups from Drive to local"
    echo "  0) Back to Main Menu - Return to main rclone menu"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
}

manage_remote_loop() {
    while true; do
        select_remote || return 0 # Go back to main if select_remote returns 1
        
        while true; do
            show_remote_menu
            read -p "Select action for '$REMOTE_NAME' (0-4): " choice
            case $choice in
                1) configure_remote ;;
                2) check_sizes ;;
                3) copy_backups_to_remote ;;
                4) restore_with_browse ;;
                0) break ;; # Break to re-select remote
                *) warn "Invalid option." ;;
            esac
            press_enter
        done
    done
}

# Auto-load first remote without selection
auto_load_remote() {
    info "Loading default remote from $CONFIG_FILE"
    [ ! -f "$CONFIG_FILE" ] && error "Configuration file not found: $CONFIG_FILE"

    # Check if config file is valid JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        error "Invalid JSON in configuration file: $CONFIG_FILE"
    fi

    local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE" 2>/dev/null)
    [ "$num_remotes" -eq 0 ] && error "No remotes defined in 'rclone_remotes' array."

    # Use environment variable remote name if provided, otherwise use first remote
    local target_remote_name="${AUTO_REMOTE_NAME:-}"
    local remote_index=0
    
    if [ -n "$target_remote_name" ]; then
        # Find the index of the specified remote
        local found_index=$(jq --arg name "$target_remote_name" '.rclone_remotes | map(.remote_name) | index($name)' "$CONFIG_FILE" 2>/dev/null)
        if [ "$found_index" != "null" ] && [ -n "$found_index" ]; then
            remote_index=$found_index
        else
            warn "Remote '$target_remote_name' not found in config, using first remote"
        fi
    fi

    # Load the selected remote
    CLIENT_ID=$(jq -r ".rclone_remotes[$remote_index].client_id" "$CONFIG_FILE")
    CLIENT_SECRET=$(jq -r ".rclone_remotes[$remote_index].client_secret" "$CONFIG_FILE")
    REMOTE_NAME=$(jq -r ".rclone_remotes[$remote_index].remote_name" "$CONFIG_FILE")
    LOG_FILE="$LOG_DIR/rclone_${REMOTE_NAME}.log"
    
    # Check for null/empty values
    if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" || -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
        error "Selected remote is missing credentials."
    fi
    
    success "Using remote: $REMOTE_NAME"
}

# Main execution
main() {
    check_root
    
    # Check if running in auto mode via environment variables
    if [ -n "$AUTO_MODE" ] && [ -n "$AUTO_REMOTE_NAME" ]; then
        # Auto-load the specified remote
        auto_load_remote
        
        case "$AUTO_MODE" in
            "copy")
                copy_backups_to_remote
                ;;
            "restore")
                restore_with_browse
                ;;
            *)
                error "Invalid AUTO_MODE: $AUTO_MODE"
                ;;
        esac
        exit $?
    fi
    
    # Handle auto commands from command line arguments
    case "$1" in
        "auto_config")
            auto_load_remote
            configure_remote
            exit $?
            ;;
        "auto_sizes")
            auto_load_remote
            check_sizes
            exit $?
            ;;
        "auto_copy")
            auto_load_remote
            copy_backups_to_remote
            exit $?
            ;;
        "auto_restore")
            auto_load_remote
            restore_with_browse
            exit $?
            ;;
        *)
            echo -e "${CYAN}======================================================================${NC}"
            echo "                         rclone Manage Website Remote"
            echo -e "${CYAN}======================================================================${NC}"
            manage_remote_loop
            ;;
    esac
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"