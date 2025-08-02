#!/bin/bash

# rclone Google Drive Backup - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

# Config
BACKUP_SOURCE="/website_backups"
RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; exit 1; }

# Check root
[[ $EUID -ne 0 ]] && err "Run as root: sudo $0"

# Install rclone
install_rclone() {
    info "Installing rclone..."
    
    if command -v rclone >/dev/null; then
        ok "rclone already installed"
        return
    fi
    
    curl -s https://rclone.org/install.sh | bash
    command -v rclone >/dev/null || err "rclone installation failed"
    
    ok "rclone installed"
}

# Configure Google Drive
setup_gdrive() {
    local remote_name="${1:-gdrive}"
    
    info "Setting up Google Drive remote: $remote_name"
    
    # Check if remote exists
    if rclone listremotes | grep -q "^${remote_name}:"; then
        warn "Remote '$remote_name' already exists"
        read -p "Reconfigure? (y/n): " reconfigure
        [[ "$reconfigure" =~ ^[Yy]$ ]] || return
    fi
    
    info "Starting rclone configuration..."
    info "Follow these steps:"
    echo "1. Choose 'n' for new remote"
    echo "2. Enter name: $remote_name"
    echo "3. Choose Google Drive (usually option 15)"
    echo "4. Leave client_id blank (press Enter)"
    echo "5. Leave client_secret blank (press Enter)"
    echo "6. Choose scope: 1 (full access)"
    echo "7. Leave root_folder_id blank (press Enter)"
    echo "8. Leave service_account_file blank (press Enter)"
    echo "9. Choose 'n' for advanced config"
    echo "10. Choose 'y' for auto config (opens browser)"
    echo "11. Choose 'y' to confirm"
    echo "12. Choose 'q' to quit"
    
    rclone config
    
    # Test connection
    if rclone lsd "${remote_name}:" >/dev/null 2>&1; then
        ok "Google Drive configured successfully"
    else
        err "Google Drive configuration failed"
    fi
}

# List remotes
list_remotes() {
    info "Configured remotes:"
    if rclone listremotes | grep -q ":"; then
        rclone listremotes
    else
        warn "No remotes configured"
    fi
}

# Sync to Google Drive
sync_to_gdrive() {
    local remote_name="${1:-gdrive}"
    local remote_path="${2:-backups}"
    
    [ -d "$BACKUP_SOURCE" ] || err "Backup source not found: $BACKUP_SOURCE"
    
    # Check if remote exists
    rclone listremotes | grep -q "^${remote_name}:" || err "Remote '$remote_name' not found"
    
    info "Syncing $BACKUP_SOURCE to $remote_name:$remote_path"
    
    # Create remote directory
    rclone mkdir "${remote_name}:${remote_path}" 2>/dev/null || true
    
    # Sync files
    rclone sync "$BACKUP_SOURCE" "${remote_name}:${remote_path}" \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --stats 30s \
        --exclude "*.tmp" \
        --exclude "*.log"
    
    ok "Sync completed"
    
    # Show stats
    local file_count=$(rclone lsf "${remote_name}:${remote_path}" | wc -l)
    local total_size=$(rclone size "${remote_name}:${remote_path}" 2>/dev/null | grep "Total size" | awk '{print $3, $4}' || echo "unknown")
    info "Files synced: $file_count | Total size: $total_size"
}

# Download from Google Drive
download_from_gdrive() {
    local remote_name="${1:-gdrive}"
    local remote_path="${2:-backups}"
    local local_path="${3:-/tmp/gdrive_download}"
    
    # Check if remote exists
    rclone listremotes | grep -q "^${remote_name}:" || err "Remote '$remote_name' not found"
    
    info "Downloading from $remote_name:$remote_path to $local_path"
    
    mkdir -p "$local_path"
    
    rclone copy "${remote_name}:${remote_path}" "$local_path" \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --stats 30s
    
    ok "Download completed to: $local_path"
}

# List remote files
list_files() {
    local remote_name="${1:-gdrive}"
    local remote_path="${2:-backups}"
    
    rclone listremotes | grep -q "^${remote_name}:" || err "Remote '$remote_name' not found"
    
    info "Files in $remote_name:$remote_path:"
    rclone lsl "${remote_name}:${remote_path}" 2>/dev/null || warn "No files found or path doesn't exist"
}

# Setup cron job
setup_cron() {
    local remote_name="${1:-gdrive}"
    local schedule="${2:-0 2 * * *}"  # Daily at 2 AM
    
    info "Setting up cron job for automatic sync..."
    
    local script_path=$(realpath "$0")
    local cron_command="$schedule $script_path sync $remote_name >/dev/null 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "$script_path"; echo "$cron_command") | crontab -
    
    ok "Cron job added: $schedule"
    info "View with: crontab -l"
}

# Menu
menu() {
    echo -e "${C}rclone Google Drive Manager${N}"
    echo "1) Install rclone"
    echo "2) Setup Google Drive"
    echo "3) List remotes"
    echo "4) Sync to Google Drive"
    echo "5) Download from Google Drive"
    echo "6) List remote files"
    echo "7) Setup auto-sync (cron)"
    echo "0) Exit"
    read -p "Select option: " choice
    
    case "$choice" in
        1) install_rclone ;;
        2) 
            read -p "Remote name (default: gdrive): " name
            setup_gdrive "${name:-gdrive}"
            ;;
        3) list_remotes ;;
        4)
            read -p "Remote name (default: gdrive): " name
            read -p "Remote path (default: backups): " path
            sync_to_gdrive "${name:-gdrive}" "${path:-backups}"
            ;;
        5)
            read -p "Remote name (default: gdrive): " name
            read -p "Remote path (default: backups): " rpath
            read -p "Local path (default: /tmp/gdrive_download): " lpath
            download_from_gdrive "${name:-gdrive}" "${rpath:-backups}" "${lpath:-/tmp/gdrive_download}"
            ;;
        6)
            read -p "Remote name (default: gdrive): " name
            read -p "Remote path (default: backups): " path
            list_files "${name:-gdrive}" "${path:-backups}"
            ;;
        7)
            read -p "Remote name (default: gdrive): " name
            read -p "Cron schedule (default: 0 2 * * *): " schedule
            setup_cron "${name:-gdrive}" "${schedule:-0 2 * * *}"
            ;;
        0) exit 0 ;;
        *) warn "Invalid option" && menu ;;
    esac
}

# Main
case "${1:-menu}" in
    install) install_rclone ;;
    setup) setup_gdrive "$2" ;;
    sync) sync_to_gdrive "$2" "$3" ;;
    download) download_from_gdrive "$2" "$3" "$4" ;;
    list) list_files "$2" "$3" ;;
    cron) setup_cron "$2" "$3" ;;
    menu) menu ;;
    *) 
        echo "rclone Google Drive Manager"
        echo "Usage: $0 [install|setup|sync|download|list|cron|menu]"
        ;;
esac