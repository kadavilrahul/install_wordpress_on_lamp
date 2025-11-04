#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$BASE_DIR/config.json"

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
        echo "Site: $site_name, Backup Path: $backup_path"
    done
fi

echo ""
echo "Total sites detected: ${#sites[@]}"
echo "Sites array: ${sites[@]}"