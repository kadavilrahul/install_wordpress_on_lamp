#!/bin/bash

WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

is_wordpress() {
    [ -f "$1/wp-config.php" ] || ([ -f "$1/wp-config-sample.php" ] && [ -d "$1/wp-includes" ])
}

backup_site() {
    local site_path="$1"
    local site_name="$2"
    local backup_name="${site_name}_backup_${TIMESTAMP}.tar.gz"
    
    if command -v wp >/dev/null && wp core is-installed --path="$site_path" --allow-root 2>/dev/null; then
        wp db export "$site_path/${site_name}_db.sql" --path="$site_path" --allow-root 2>/dev/null
    fi
    
    cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$backup_name" "$site_name" 2>/dev/null
    rm -f "$site_path/${site_name}_db.sql" 2>/dev/null
    echo "Backup created: $backup_name"
}

find_sites() {
    for dir in "$WWW_PATH"/*; do
        [ -d "$dir" ] || continue
        site_name=$(basename "$dir")
        [ "$site_name" = "html" ] && continue
        
        if is_wordpress "$dir"; then
            echo "$site_name"
        fi
    done
}

main() {
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    mkdir -p "$BACKUP_DIR"
    
    sites=($(find_sites))
    [ ${#sites[@]} -eq 0 ] && { echo "No WordPress sites found"; exit 1; }
    
    echo "WordPress sites:"
    for i in "${!sites[@]}"; do
        echo "$((i+1))) ${sites[i]}"
    done
    echo "$((${#sites[@]}+1))) All sites"
    
    read -p "Select option: " choice
    
    if [ "$choice" = "$((${#sites[@]}+1))" ]; then
        for site in "${sites[@]}"; do
            backup_site "$WWW_PATH/$site" "$site"
        done
    elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#sites[@]} ]; then
        selected_site="${sites[$((choice-1))]}"
        backup_site "$WWW_PATH/$selected_site" "$selected_site"
    else
        echo "Invalid selection"
        exit 1
    fi
    
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
    echo "Backup completed"
}

main