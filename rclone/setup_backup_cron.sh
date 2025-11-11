#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$BASE_DIR/backup_restore/backup_all_sites.sh"
BACKUP_DIR="/website_backups"
RCLONE_LOG="/var/log/rclone.log"
CONFIG_FILE="$BASE_DIR/config.json"

[ $EUID -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -f "$BACKUP_SCRIPT" ] && { echo "Error: Backup script not found at $BACKUP_SCRIPT"; exit 1; }

# Check if rclone is available (optional for local-only backups)
RCLONE_AVAILABLE=false
if command -v rclone >/dev/null 2>&1; then
    remotes=$(rclone listremotes 2>/dev/null)
    if [ -n "$remotes" ]; then
        RCLONE_AVAILABLE=true
        remote=$(echo "$remotes" | head -1 | sed 's/:$//')
    fi
fi

sites=()
if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null; then
    for site_dir in /var/www/*; do
        [ -d "$site_dir" ] || continue
        site_name=$(basename "$site_dir")
        [ "$site_name" = "html" ] && continue
        
        # Try to get backup path from config
        backup_path=$(jq -r ".backup_locations[\"$site_name\"] // empty" "$CONFIG_FILE" 2>/dev/null)
        
        # If no specific backup path, use default based on domain
        if [ -z "$backup_path" ]; then
            # For subdomains, use parent domain's backup location or create default
            if [[ "$site_name" == *"."* ]]; then
                parent_domain=$(echo "$site_name" | cut -d'.' -f2-)
                backup_path=$(jq -r ".backup_locations[\"$parent_domain\"] // \"backup_$site_name\"" "$CONFIG_FILE" 2>/dev/null)
            else
                backup_path="backup_$site_name"
            fi
        fi
        
        sites+=("$site_name:$backup_path")
    done
fi

mkdir -p "$BACKUP_DIR"

echo "====================================================================="
echo "                    Backup Cron Job Setup"
echo "====================================================================="
echo
if [ "$RCLONE_AVAILABLE" = true ]; then
    echo "Rclone Status: ✓ Configured (remote: $remote)"
else
    echo "Rclone Status: ✗ Not configured (local backups only)"
fi
echo
echo "Options:"
echo "1) Setup daily backup (3 AM) - All sites (WordPress + static)"
echo "2) View current backup cron jobs"
echo "3) Remove all backup cron jobs"
echo "4) Exit"
echo
read -p "Select option (1-4): " choice

case $choice in
    1) 
        backup_cmd="/bin/bash $BACKUP_SCRIPT --all"
        schedule="0 3 * * *"
        desc="Daily at 3:00 AM - All sites (WordPress + static)"
        ;;
    2)
        echo
        echo "Current backup-related cron jobs:"
        echo "---------------------------------"
        crontab -l 2>/dev/null | grep -E "(backup_all_sites|backup_wordpress_postgresql|backup_wordpress|backup_postgresql)" || echo "No backup cron jobs found"
        echo
        echo "Cron schedule format: MIN HOUR DAY MONTH WEEKDAY"
        echo "  0 3 * * *    = Daily at 3:00 AM"
        echo
        exit 0
        ;;
    3) 
        echo
        echo "Current backup cron jobs:"
        crontab -l 2>/dev/null | grep -E "(backup_all_sites|backup_wordpress_postgresql|backup_wordpress|backup_postgresql|rclone.*$BACKUP_DIR)" || echo "None found"
        echo
        read -p "Remove all backup cron jobs? (y/N): " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            current_crons=$(crontab -l 2>/dev/null | grep -v "backup_all_sites" | grep -v "backup_wordpress_postgresql" | grep -v "backup_wordpress.sh" | grep -v "backup_postgresql.sh" | grep -v "rclone.*$BACKUP_DIR")
            echo "$current_crons" | crontab - && echo "✓ All backup cron jobs removed" || echo "Failed to remove cron jobs"
        else
            echo "Operation cancelled"
        fi
        exit 0
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *) 
        echo "Invalid choice"
        exit 1 
        ;;
esac

# Remove existing cron jobs for this backup command and related rclone jobs
# For all sites backup, remove old backup_all_sites and all rclone jobs
current_crons=$(crontab -l 2>/dev/null | grep -v "backup_all_sites" | grep -v "backup_wordpress_postgresql" | grep -v "backup_wordpress.sh" | grep -v "backup_postgresql.sh" | grep -v "rclone.*$BACKUP_DIR")

# Start building new cron jobs
new_crons="$current_crons"
[ -n "$new_crons" ] && new_crons="$new_crons"$'\n'

# Add the backup command with proper logging
log_file="/var/log/backup_$(date +%Y%m%d).log"
new_crons="${new_crons}${schedule} $backup_cmd >> $log_file 2>&1"$'\n'

    # Add rclone upload if available
    if [ "$RCLONE_AVAILABLE" = true ]; then
        # Calculate upload time (1 hour after backup)
        backup_hour=$(echo "$schedule" | cut -d' ' -f2)
        upload_hour=$((backup_hour + 1))
        [ $upload_hour -ge 24 ] && upload_hour=$((upload_hour - 24))
        
        if [ ${#sites[@]} -gt 0 ]; then
            # Group sites by backup location to create one rclone job per backup path
            declare -A backup_locations_map
            for site_info in "${sites[@]}"; do
                website=$(echo "$site_info" | cut -d: -f1)
                backup_path=$(echo "$site_info" | cut -d: -f2)
                
                # Only process if it's the specific domain requested, or all domains if none specified
                if [[ -n "${domain:-}" && "$website" == "$domain" ]] || [[ -z "${domain:-}" ]]; then
                    # Check if this is a subdomain that shares backup location with parent
                    skip_subdomain=false
                    if [[ "$website" == *.*.* ]]; then
                        # Extract parent domain (e.g., keralabusinesshub.in from goldrate.keralabusinesshub.in)
                        parent_domain=$(echo "$website" | rev | cut -d'.' -f1,2 | rev)
                        # Check if parent domain exists with same backup path
                        for check_site in "${sites[@]}"; do
                            check_name=$(echo "$check_site" | cut -d: -f1)
                            check_path=$(echo "$check_site" | cut -d: -f2)
                            if [[ "$check_name" == "$parent_domain" ]] && [[ "$check_path" == "$backup_path" ]]; then
                                skip_subdomain=true
                                break
                            fi
                        done
                    fi
                    
                    # Add to map if not skipping (use parent domain pattern if subdomain shares path)
                    if [[ "$skip_subdomain" == false ]]; then
                        if [[ -z "${backup_locations_map[$backup_path]}" ]]; then
                            backup_locations_map[$backup_path]="$website"
                        fi
                    fi
                fi
            done
            
            # Create one rclone job per unique backup location
            for backup_path in "${!backup_locations_map[@]}"; do
                website="${backup_locations_map[$backup_path]}"
                new_crons="${new_crons}0 ${upload_hour} * * * /usr/bin/rclone copy $BACKUP_DIR ${remote}:${backup_path} --include=\"*${website}*\" --log-file=$RCLONE_LOG && find $BACKUP_DIR -name \"*${website}*\" -type f -exec rm -f {} \\;"$'\n'
            done
        else
            # Generic rclone upload for all backups
            new_crons="${new_crons}0 ${upload_hour} * * * /usr/bin/rclone copy $BACKUP_DIR ${remote}: --log-file=$RCLONE_LOG && find $BACKUP_DIR -type f -exec rm -f {} \\;"$'\n'
        fi
    fi

# Apply the new crontab
if echo "$new_crons" | crontab -; then
    echo
    echo "✓ Cron job configured successfully!"
    echo "  Schedule: $desc"
    echo "  Command: $backup_cmd"
    echo "  Log: $log_file"
    
    if [ "$RCLONE_AVAILABLE" = true ]; then
        echo "  Rclone upload: $([ $upload_hour -lt 10 ] && echo "0")${upload_hour}:00"
        echo "  Local cleanup: Immediately after successful remote upload"
    fi
else
    echo "Failed to configure cron jobs"
    exit 1
fi