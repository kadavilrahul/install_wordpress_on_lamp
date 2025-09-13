#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$BASE_DIR/backup_restore/backup_wordpress.sh"
BACKUP_DIR="/website_backups"
RCLONE_LOG="/var/log/rclone.log"
CONFIG_FILE="$BASE_DIR/config.json"

[ $EUID -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -f "$BACKUP_SCRIPT" ] && { echo "Backup script not found"; exit 1; }
! command -v rclone >/dev/null && { echo "Rclone not installed"; exit 1; }

remotes=$(rclone listremotes 2>/dev/null)
[ -z "$remotes" ] && { echo "No rclone remotes configured"; exit 1; }
remote=$(echo "$remotes" | head -1 | sed 's/:$//')

sites=()
if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null; then
    for site_dir in /var/www/*; do
        [ -d "$site_dir" ] || continue
        site_name=$(basename "$site_dir")
        [ "$site_name" = "html" ] && continue
        backup_path=$(jq -r ".backup_locations[\"$site_name\"] // empty" "$CONFIG_FILE" 2>/dev/null)
        [ -n "$backup_path" ] && sites+=("$site_name:$backup_path")
    done
fi

mkdir -p "$BACKUP_DIR"

echo "Options:"
echo "1) Setup backup - First site only"
echo "2) Setup backup - All sites"
echo "3) Remove all backup cron jobs"
read -p "Select: " choice

case $choice in
    1) backup_cmd="bash $BACKUP_SCRIPT --first" ;;
    2) backup_cmd="bash $BACKUP_SCRIPT --all" ;;
    3) 
        echo "Current backup cron jobs:"
        crontab -l 2>/dev/null | grep -E "($BACKUP_SCRIPT|rclone.*$BACKUP_DIR|find $BACKUP_DIR)" || echo "None found"
        echo
        read -p "Remove all backup cron jobs? (y/N): " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            current_crons=$(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | grep -v "rclone.*$BACKUP_DIR" | grep -v "find $BACKUP_DIR")
            echo "$current_crons" | crontab - && echo "All backup cron jobs removed" || echo "Failed to remove cron jobs"
        else
            echo "Operation cancelled"
        fi
        exit 0
        ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

current_crons=$(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | grep -v "rclone.*$BACKUP_DIR" | grep -v "find $BACKUP_DIR")
new_crons="$current_crons"

[ -n "$new_crons" ] && new_crons="$new_crons"$'\n'
new_crons="${new_crons}00 01 * * * $backup_cmd"$'\n'

if [ ${#sites[@]} -gt 0 ]; then
    for site_info in "${sites[@]}"; do
        website=$(echo "$site_info" | cut -d: -f1)
        backup_path=$(echo "$site_info" | cut -d: -f2)
        new_crons="${new_crons}00 02 * * * /usr/bin/rclone copy $BACKUP_DIR ${remote}:${backup_path} --include=\"*${website}*\" --log-file=$RCLONE_LOG"$'\n'
    done
else
    new_crons="${new_crons}00 02 * * * /usr/bin/rclone copy $BACKUP_DIR ${remote}: --log-file=$RCLONE_LOG"$'\n'
fi

new_crons="${new_crons}00 03 * * * find $BACKUP_DIR -type f -exec rm -f {} \\;"

echo "$new_crons" | crontab - && echo "Cron jobs configured" || echo "Failed to configure cron"