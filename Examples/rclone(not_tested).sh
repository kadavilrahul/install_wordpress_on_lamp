#!/bin/bash
# Rclone Setup and Configuration Script
# Based on: https://www.youtube.com/watch?v=X_3gJ3Nbsgc

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use 'sudo bash' first."
    exit 1
fi

# Install rclone
echo "Installing rclone..."
apt update
apt install -y rclone

# Create a helper function for rclone configuration
configure_rclone() {
    echo "=== RCLONE CONFIGURATION ==="
    echo "1. Run 'rclone config'"
    echo "2. Select 'n' for new remote"
    echo "3. Name it 'server_silkroademart'"
    echo "4. Select Google Drive (option 13 or 18 depending on your rclone version)"
    echo "5. For client_id and client_secret, press Enter to use auto config"
    echo "6. Select '1' for full access to all files"
    echo "7. When browser opens, use the SECOND link if multiple appear"
    echo "8. Log in with your Google account and authorize rclone"
    echo "9. Select 'y' to confirm configuration is correct"
    echo "10. Select 'q' to quit config"
    echo ""
    echo "IMPORTANT: Run this configuration from a desktop session with Chrome installed"
    echo "to avoid port conflict errors."
    echo ""
    read -p "Press Enter to start configuration (or Ctrl+C to cancel)..."
    
    rclone config
}

# Verify rclone configuration
verify_rclone() {
    echo "=== VERIFYING RCLONE CONFIGURATION ==="
    echo "Testing connection to Google Drive..."
    
    echo "Listing directories:"
    rclone lsf server_silkroademart: --dirs-only
    
    echo "Listing directories with details:"
    rclone lsd server_silkroademart:
    
    echo "Listing files with details:"
    rclone lsl server_silkroademart:
    
    echo "Showing folder structure:"
    rclone tree server_silkroademart:
}

# Check storage sizes
check_sizes() {
    echo "=== CHECKING STORAGE SIZES ==="
    echo "Server storage:"
    du -sh /var/www/
    
    echo "Google Drive storage:"
    rclone size "server_silkroademart:"
}

# Setup backup directory
setup_backup_dir() {
    echo "=== SETTING UP BACKUP DIRECTORY ==="
    if [ ! -d "/website_backups" ]; then
        echo "Creating /website_backups directory..."
        mkdir -p /website_backups
        chmod 755 /website_backups
    else
        echo "/website_backups directory already exists."
    fi
}

# Transfer files to Google Drive
transfer_to_gdrive() {
    echo "=== TRANSFERRING FILES TO GOOGLE DRIVE ==="
    echo "This will sync /website_backups to Google Drive"
    read -p "Continue? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        rclone sync /website_backups "server_silkroademart:" --progress
        echo "Transfer complete."
    else
        echo "Transfer cancelled."
    fi
}

# Setup cron job
setup_cron() {
    echo "=== SETTING UP CRON JOB ==="
    echo "This will create a daily backup at 5:00 AM"
    read -p "Use 'sync' (overwrite) or 'copy' (preserve all versions)? (s/c): " sync_type
    
    if [ "$sync_type" = "s" ]; then
        cron_cmd="0 5 */1 * * /usr/bin/rclone sync /website_backups \"server_silkroademart:\" --log-file=/var/log/rclone.log"
    else
        cron_cmd="0 5 */1 * * /usr/bin/rclone copy /website_backups \"server_silkroademart:\" --log-file=/var/log/rclone.log"
    fi
    
    # Check if cron job already exists
    crontab -l > mycron 2>/dev/null || echo "" > mycron
    if grep -q "rclone.*server_silkroademart" mycron; then
        echo "Cron job already exists. Updating..."
        sed -i '/rclone.*server_silkroademart/d' mycron
    fi
    
    echo "$cron_cmd" >> mycron
    crontab mycron
    rm mycron
    
    echo "Cron job set up successfully."
}

# Restore from Google Drive
restore_from_gdrive() {
    echo "=== RESTORE FROM GOOGLE DRIVE ==="
    echo "Options:"
    echo "1. Sync entire Google Drive to /website_backups"
    echo "2. Copy specific file from Google Drive"
    read -p "Choose option (1/2): " restore_option
    
    if [ "$restore_option" = "1" ]; then
        rclone sync -v server_silkroademart: /website_backups --progress
    elif [ "$restore_option" = "2" ]; then
        echo "Available files:"
        rclone lsf server_silkroademart: --include "*.tar.gz"
        read -p "Enter file path (e.g., backup_silkroademart/file.tar.gz): " file_path
        rclone copy -v "server_silkroademart:$file_path" /website_backups --progress
    else
        echo "Invalid option."
    fi
}

# Uninstall rclone
uninstall_rclone() {
    echo "=== UNINSTALL RCLONE ==="
    read -p "Are you sure you want to uninstall rclone? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        apt remove -y rclone
        echo "Rclone uninstalled."
    else
        echo "Uninstall cancelled."
    fi
}

# Main menu
show_menu() {
    clear
    echo "=== RCLONE GOOGLE DRIVE BACKUP SCRIPT ==="
    echo "1. Install and configure rclone"
    echo "2. Verify rclone configuration"
    echo "3. Check storage sizes"
    echo "4. Setup backup directory"
    echo "5. Transfer files to Google Drive"
    echo "6. Setup cron job for automatic backups"
    echo "7. Restore from Google Drive"
    echo "8. Uninstall rclone"
    echo "0. Exit"
    echo ""
    read -p "Enter your choice: " choice
    
    case $choice in
        1) configure_rclone ;;
        2) verify_rclone ;;
        3) check_sizes ;;
        4) setup_backup_dir ;;
        5) transfer_to_gdrive ;;
        6) setup_cron ;;
        7) restore_from_gdrive ;;
        8) uninstall_rclone ;;
        0) exit 0 ;;
        *) echo "Invalid option. Press Enter to continue..."; read ;;
    esac
    
    read -p "Press Enter to return to menu..."
    show_menu
}

# Start the script
show_menu
