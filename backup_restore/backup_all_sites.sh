#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --site <site_name>    Backup specific site (WordPress or static)"
    echo "  --all                 Backup all sites (WordPress + static)"
    echo "  --first               Backup first site only"
    echo "  --list                List all available websites"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --site example.com"
    echo "  $0 --all"
    echo "  $0 --first"
    echo ""
    echo "This script backs up all websites including WordPress and static sites."
}

backup_site() {
    local site_name="$1"
    local site_path="/var/www/$site_name"
    
    echo "Backing up site: $site_name"
    echo "----------------------------------------"
    
    # Check if it's a WordPress site
    if [ -f "$site_path/wp-config.php" ] || ([ -f "$site_path/wp-config-sample.php" ] && [ -d "$site_path/wp-includes" ]); then
        echo "Type: WordPress site"
        bash "$SCRIPT_DIR/backup_wordpress_postgresql.sh" --site "$site_name"
    # Check if it's a static site with PostgreSQL
    elif [ -f "$site_path/config.json" ] && command -v jq >/dev/null && jq -e '.database' "$site_path/config.json" >/dev/null 2>&1; then
        echo "Type: Static site with PostgreSQL"
        bash "$SCRIPT_DIR/backup_static_postgresql.sh" --site "$site_name"
    # Check if it's a static site
    elif [ -f "$site_path/index.html" ] || [ -f "$site_path/index.php" ] || [ -n "$(find "$site_path" -maxdepth 2 -name "*.html" -o -name "*.php" -o -name "*.css" -o -name "*.js" 2>/dev/null | head -1)" ]; then
        echo "Type: Static site"
        bash "$SCRIPT_DIR/backup_static_sites.sh" --site "$site_name"
    else
        echo "Type: Unknown (skipping)"
        return 1
    fi
    
    echo "----------------------------------------"
    echo
}

find_all_sites() {
    for dir in /var/www/*; do
        [ -d "$dir" ] || continue
        site_name=$(basename "$dir")
        [ "$site_name" = "html" ] && continue
        echo "$site_name"
    done
}

main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --site)
            [ -z "$2" ] && { echo "Error: Site name required"; exit 1; }
            if [ ! -d "/var/www/$2" ]; then
                echo "Error: Site '$2' not found in /var/www/"
                exit 1
            fi
            backup_site "$2"
            ;;
        --all|all)
            sites=($(find_all_sites))
            [ ${#sites[@]} -eq 0 ] && { echo "No websites found"; exit 1; }
            
            echo "Backing up all websites (${#sites[@]} total)"
            echo "========================================"
            echo
            
            for site in "${sites[@]}"; do
                backup_site "$site"
            done
            
            echo "All website backups completed"
            ;;
        --first)
            sites=($(find_all_sites))
            [ ${#sites[@]} -eq 0 ] && { echo "No websites found"; exit 1; }
            
            echo "Backing up first website: ${sites[0]}"
            backup_site "${sites[0]}"
            ;;
        --list|list)
            sites=($(find_all_sites))
            [ ${#sites[@]} -eq 0 ] && { echo "No websites found"; exit 0; }
            
            echo "Available websites:"
            for site in "${sites[@]}"; do
                site_path="/var/www/$site"
                if [ -f "$site_path/wp-config.php" ] || ([ -f "$site_path/wp-config-sample.php" ] && [ -d "$site_path/wp-includes" ]); then
                    echo "  $site (WordPress)"
                elif [ -f "$site_path/config.json" ] && command -v jq >/dev/null && jq -e '.database' "$site_path/config.json" >/dev/null 2>&1; then
                    echo "  $site (Static with PostgreSQL)"
                elif [ -f "$site_path/index.html" ] || [ -f "$site_path/index.php" ] || [ -n "$(find "$site_path" -maxdepth 2 -name "*.html" -o -name "*.php" -o -name "*.css" -o -name "*.js" 2>/dev/null | head -1)" ]; then
                    echo "  $site (Static)"
                else
                    echo "  $site (Unknown type)"
                fi
            done
            ;;
        "")
            # Default to --all when no arguments provided
            sites=($(find_all_sites))
            [ ${#sites[@]} -eq 0 ] && { echo "No websites found"; exit 1; }
            
            echo "Backing up all websites (${#sites[@]} total)"
            echo "========================================"
            echo
            
            for site in "${sites[@]}"; do
                backup_site "$site"
            done
            
            echo "All website backups completed"
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"