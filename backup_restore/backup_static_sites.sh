#!/bin/bash

WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --site <site_name>    Backup specific site"
    echo "  --all                 Backup all sites"
    echo "  --first               Backup first site only"
    echo "  --list                List available sites"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --site silkroademart.com"
    echo "  $0 --all"
    echo "  $0 --first"
    echo ""
    echo "If no arguments provided, interactive menu will be shown."
}

is_wordpress() {
    [ -f "$1/wp-config.php" ] || ([ -f "$1/wp-config-sample.php" ] && [ -d "$1/wp-includes" ])
}

is_static_site() {
    local dir="$1"
    local site_name="$2"
    
    # Skip html directory (default Apache directory)
    [ "$site_name" = "html" ] && return 1
    
    # Skip if it's a WordPress site
    is_wordpress "$dir" && return 1
    
    # Check if directory has web files
    if [ -f "$dir/index.html" ] || [ -f "$dir/index.php" ] || [ -n "$(find "$dir" -maxdepth 2 -name "*.html" -o -name "*.php" -o -name "*.css" -o -name "*.js" 2>/dev/null | head -1)" ]; then
        return 0
    fi
    
    return 1
}

backup_site() {
    local site_path="$1"
    local site_name="$2"
    local backup_name="${site_name}_static_backup_${TIMESTAMP}.tar.gz"
    
    echo "Backing up static site: $site_name"
    
    # Create backup
    cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$backup_name" "$site_name" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Backup created: $backup_name"
        
        # Show backup info
        local backup_size=$(du -h "$BACKUP_DIR/$backup_name" 2>/dev/null | cut -f1)
        echo "Backup size: ${backup_size:-unknown}"
    else
        echo "Error: Failed to create backup for $site_name"
        return 1
    fi
}

find_static_sites() {
    for dir in "$WWW_PATH"/*; do
        [ -d "$dir" ] || continue
        site_name=$(basename "$dir")
        
        if is_static_site "$dir" "$site_name"; then
            echo "$site_name"
        fi
    done
}

interactive_mode() {
    sites=($(find_static_sites))
    [ ${#sites[@]} -eq 0 ] && { echo "No static websites found"; exit 1; }
    
    echo "Static websites found:"
    for i in "${!sites[@]}"; do
        local site="${sites[i]}"
        local site_path="$WWW_PATH/$site"
        local file_count=$(find "$site_path" -type f 2>/dev/null | wc -l)
        local dir_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
        echo "$((i+1))) ${site} (${file_count} files, ${dir_size:-unknown size})"
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
}

main() {
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    mkdir -p "$BACKUP_DIR"
    
    sites=($(find_static_sites))
    [ ${#sites[@]} -eq 0 ] && { echo "No static websites found"; exit 1; }
    
    case "${1:-}" in
        --site)
            [ -z "$2" ] && { echo "Error: Site name required"; exit 1; }
            site_found=false
            for site in "${sites[@]}"; do
                if [ "$site" = "$2" ]; then
                    backup_site "$WWW_PATH/$site" "$site"
                    site_found=true
                    break
                fi
            done
            [ "$site_found" = false ] && { echo "Error: Static site '$2' not found"; exit 1; }
            ;;
        --all)
            for site in "${sites[@]}"; do
                backup_site "$WWW_PATH/$site" "$site"
            done
            ;;
        --first)
            backup_site "$WWW_PATH/${sites[0]}" "${sites[0]}"
            ;;
        --list)
            echo "Available static websites:"
            for site in "${sites[@]}"; do
                local site_path="$WWW_PATH/$site"
                local file_count=$(find "$site_path" -type f 2>/dev/null | wc -l)
                local dir_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
                echo "  $site (${file_count} files, ${dir_size:-unknown size})"
            done
            exit 0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            interactive_mode
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
    
    # Clean old backups (keep last 7 days)
    find "$BACKUP_DIR" -name "*_static_backup_*.tar.gz" -mtime +7 -delete 2>/dev/null
    echo "Backup completed"
}

main "$@"