#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.json"

# Get default remote from config
get_default_remote() {
    if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
        local default_remote=$(jq -r '.rclone_remotes[0].remote_name // "server_backup"' "$CONFIG_FILE" 2>/dev/null)
        echo "$default_remote"
    else
        echo "server_backup"
    fi
}

DEFAULT_REMOTE=$(get_default_remote)

# Fallback for different naming conventions  
if [ -z "$DEFAULT_REMOTE" ] || [ "$DEFAULT_REMOTE" = "null" ]; then
    # Check if serverbackup exists (underscore version may not be valid)
    if rclone listremotes 2>/dev/null | grep -q "serverbackup:"; then
        DEFAULT_REMOTE="serverbackup"
    else
        DEFAULT_REMOTE="server_backup"  
    fi
fi

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Execute script with error handling
execute_script() {
    local script_path="$1"
    local script_name="$2"
    
    # Make script_path absolute
    script_path="$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: $script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    info "Launching $script_name..."
    
    # Change to script directory and run, then return to original directory
    local original_dir="$(pwd)"
    cd "$SCRIPT_DIR"
    bash "$script_path"
    local exit_code=$?
    cd "$original_dir"
    
    if [ $exit_code -eq 0 ]; then
        success "$script_name completed successfully"
    else
        warn "$script_name exited with code $exit_code"
    fi
    
    read -p "Press Enter to continue..."
    return $exit_code
}

# Cloud Storage menu header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                        Cloud Storage (Rclone)"
    echo "                     Complete Cloud Management Suite"
    echo "============================================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}"
    echo -e "${YELLOW}Default remote: $DEFAULT_REMOTE${NC}"
    echo
}

# Consolidated Cloud Storage menu
show_menu() {
    show_header
    echo -e "${CYAN}============================================================================="
    echo "                        Cloud Storage (Rclone) Management"
    echo -e "=============================================================================${NC}"
    echo "1. Install Rclone Package        - Download and install rclone with dependencies"
    echo "2. Configure Remote Storage      - Set up Google Drive authentication for '$DEFAULT_REMOTE'"
    echo "3. Show Configured Remotes       - Display remotes and accessibility status"
    echo "4. Check Rclone Status           - View rclone setup and configuration details"
    echo "5. Check Folder Sizes            - View local and remote storage usage"
    echo "6. Copy Backups to Remote        - Upload local backups to Drive folder"
    echo "7. Restore Backups from Drive    - Download backups from Drive to local (Browse)"
    echo "8. Setup Backup Automation       - Configure automatic backup scheduling"
    echo "9. Uninstall Rclone              - Remove rclone and all configurations"
    echo "0. Back to Main Menu"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Import common variables and functions for remote operations
BACKUP_SOURCE="/website_backups"
LOG_DIR="/var/log"

# Load remote configuration automatically
load_default_remote() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Check if config file is valid JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        error "Invalid JSON in configuration file: $CONFIG_FILE"
        return 1
    fi

    local num_remotes=$(jq '.rclone_remotes | length' "$CONFIG_FILE" 2>/dev/null)
    if [ "$num_remotes" -eq 0 ]; then
        error "No remotes defined in 'rclone_remotes' array."
        return 1
    fi

    # Auto-select first remote
    CLIENT_ID=$(jq -r ".rclone_remotes[0].client_id" "$CONFIG_FILE")
    CLIENT_SECRET=$(jq -r ".rclone_remotes[0].client_secret" "$CONFIG_FILE")
    REMOTE_NAME=$(jq -r ".rclone_remotes[0].remote_name" "$CONFIG_FILE")
    RCLONE_LOG_FILE="$LOG_DIR/rclone_${REMOTE_NAME}.log"
    
    # Check for null/empty values
    if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" || -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
        error "Default remote is missing credentials."
        return 1
    fi
    
    success "Using remote: $REMOTE_NAME"
    return 0
}

# Configure remote function
configure_remote() {
    if ! load_default_remote; then
        return 1
    fi
    
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

# Check sizes function
check_sizes() {
    if ! load_default_remote; then
        return 1
    fi
    
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

# Auto-configure remote without prompting
auto_configure_remote() {
    info "Configuring remote '$DEFAULT_REMOTE' automatically..."
    configure_remote
    read -p "Press Enter to continue..."
}

# Auto-check sizes without prompting
auto_check_sizes() {
    info "Checking storage sizes for remote '$DEFAULT_REMOTE'..."
    check_sizes
    read -p "Press Enter to continue..."
}

# Auto-copy backups without prompting
auto_copy_backups() {
    info "Copying backups to remote '$DEFAULT_REMOTE'..."
    # Set environment variables for the script to use
    export AUTO_REMOTE_NAME="$DEFAULT_REMOTE"
    export AUTO_MODE="copy"
    bash "$SCRIPT_DIR/manage_remote.sh"
    read -p "Press Enter to continue..."
}

# Auto-restore backups without prompting
auto_restore_backups() {
    info "Restoring backups from remote '$DEFAULT_REMOTE'..."
    # Set environment variables for the script to use
    export AUTO_REMOTE_NAME="$DEFAULT_REMOTE"
    export AUTO_MODE="restore"
    bash "$SCRIPT_DIR/manage_remote.sh"
    read -p "Press Enter to continue..."
}

# Handle CLI arguments
handle_cli_command() {
    local command="$1"
    
    case $command in
        "install") execute_script "$SCRIPT_DIR/install_package.sh" "Install Rclone Package" ;;
        "config"|"configure") auto_configure_remote ;;
        "remotes"|"show") execute_script "$SCRIPT_DIR/show_remotes.sh" "Show Configured Remotes" ;;
        "status") execute_script "$SCRIPT_DIR/show_status.sh" "Check Rclone Status" ;;
        "sizes") auto_check_sizes ;;
        "copy") auto_copy_backups ;;
        "restore") auto_restore_backups ;;
        "cron"|"automation") execute_script "$SCRIPT_DIR/setup_backup_cron.sh" "Setup Backup Automation" ;;
        "uninstall") execute_script "$SCRIPT_DIR/uninstall_package.sh" "Uninstall Rclone" ;;
        *) 
            echo -e "${RED}Invalid command: $command${NC}"
            echo -e "${YELLOW}Available commands:${NC}"
            echo "  install    - Install rclone package"
            echo "  config     - Configure remote storage"
            echo "  remotes    - Show configured remotes"
            echo "  status     - Check rclone status"
            echo "  sizes      - Check folder sizes"
            echo "  copy       - Copy backups to remote"
            echo "  restore    - Restore backups from remote"
            echo "  cron       - Setup backup automation"
            echo "  uninstall  - Uninstall rclone"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    check_root
    
    if [ $# -gt 0 ]; then
        handle_cli_command "$1"
        exit $?
    fi
    
    while true; do
        show_menu
        echo -n "Enter option (0-9): "
        read choice
        
        case $choice in
            1) execute_script "$SCRIPT_DIR/install_package.sh" "Install Rclone Package" ;;
            2) auto_configure_remote ;;
            3) execute_script "$SCRIPT_DIR/show_remotes.sh" "Show Configured Remotes" ;;
            4) execute_script "$SCRIPT_DIR/show_status.sh" "Check Rclone Status" ;;
            5) auto_check_sizes ;;
            6) auto_copy_backups ;;
            7) auto_restore_backups ;;
            8) execute_script "$SCRIPT_DIR/setup_backup_cron.sh" "Setup Backup Automation" ;;
            9) execute_script "$SCRIPT_DIR/uninstall_package.sh" "Uninstall Rclone" ;;
            0) 
                echo -e "${GREEN}Returning to main menu...${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Invalid option. Please select 0-9.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"