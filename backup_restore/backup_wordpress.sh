#!/bin/bash

WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
NON_INTERACTIVE=false

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
    echo "  $0 --site nilgiristores.in"
    echo "  $0 --all"
    echo "  $0 --first"
    echo ""
    echo "If no arguments provided, interactive menu will be shown."
}

is_wordpress() {
    [ -f "$1/wp-config.php" ] || ([ -f "$1/wp-config-sample.php" ] && [ -d "$1/wp-includes" ])
}

backup_site() {
    local site_path="$1"
    local site_name="$2"
    local backup_name="${site_name}_backup_${TIMESTAMP}.tar.gz"
    
    if command -v wp >/dev/null && wp core is-installed --path="$site_path" --allow-root 2>/dev/null; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            wp db export "$site_path/${site_name}_mysql_db.sql" --path="$site_path" --allow-root >/dev/null 2>&1
        else
            wp db export "$site_path/${site_name}_mysql_db.sql" --path="$site_path" --allow-root 2>/dev/null
        fi
    fi
    
    cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$backup_name" "$site_name" 2>/dev/null
    rm -f "$site_path/${site_name}_mysql_db.sql" 2>/dev/null
    echo "✓ WordPress backup: $backup_name"
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

interactive_mode() {
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
}

main() {
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    mkdir -p "$BACKUP_DIR"
    
    sites=($(find_sites))
    [ ${#sites[@]} -eq 0 ] && { echo "No WordPress sites found"; exit 1; }
    
    case "${1:-}" in
        --site)
            [ -z "$2" ] && { echo "Error: Site name required"; exit 1; }
            NON_INTERACTIVE=true
            site_found=false
            for site in "${sites[@]}"; do
                if [ "$site" = "$2" ]; then
                    backup_site "$WWW_PATH/$site" "$site"
                    site_found=true
                    break
                fi
            done
            [ "$site_found" = false ] && { echo "Error: Site '$2' not found"; exit 1; }
            ;;
        --all)
            NON_INTERACTIVE=true
            for site in "${sites[@]}"; do
                backup_site "$WWW_PATH/$site" "$site"
            done
            ;;
        --first)
            NON_INTERACTIVE=true
            backup_site "$WWW_PATH/${sites[0]}" "${sites[0]}"
            ;;
        --list)
            echo "Available WordPress sites:"
            for site in "${sites[@]}"; do
                echo "  $site"
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
    
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Backup completed"
}

main "$@"