#!/bin/bash

WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --backup <backup_file>    Restore from specific backup file"
    echo "  --list                    List available backups"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --backup silkroademart.com_static_backup_2025-09-16_12-30-45.tar.gz"
    echo "  $0 --list"
    echo ""
    echo "If no arguments provided, interactive menu will be shown."
}

find_static_backups() {
    find "$BACKUP_DIR" -maxdepth 1 -name "*_static_backup_*.tar.gz" -type f 2>/dev/null | sort -r
}

extract_site_name() {
    local backup_file="$1"
    local filename=$(basename "$backup_file")
    echo "$filename" | sed 's/_static_backup_.*\.tar\.gz$//'
}

restore_site() {
    local backup_file="$1"
    local site_name=$(extract_site_name "$backup_file")
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Restoring static site: $site_name"
    echo "From backup: $(basename "$backup_file")"
    echo
    
    # Check if site directory exists
    local site_path="$WWW_PATH/$site_name"
    if [ -d "$site_path" ]; then
        echo "Warning: Site directory already exists: $site_path"
        read -p "Do you want to overwrite it? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Restore cancelled"
            return 0
        fi
        
        # Backup existing site
        local existing_backup="${site_name}_existing_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        echo "Creating backup of existing site: $existing_backup"
        cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$existing_backup" "$site_name" 2>/dev/null
        
        # Remove existing site
        rm -rf "$site_path"
    fi
    
    # Extract backup
    echo "Extracting backup..."
    cd "$WWW_PATH" && tar -xzf "$backup_file"
    
    if [ $? -eq 0 ]; then
        # Set proper permissions
        chown -R www-data:www-data "$site_path"
        find "$site_path" -type d -exec chmod 755 {} \;
        find "$site_path" -type f -exec chmod 644 {} \;
        
        echo "Restore completed successfully!"
        echo "Site restored to: $site_path"
        
        # Show site info
        local file_count=$(find "$site_path" -type f 2>/dev/null | wc -l)
        local dir_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
        echo "Files restored: $file_count"
        echo "Total size: ${dir_size:-unknown}"
        
        # Check for index file
        if [ -f "$site_path/index.html" ]; then
            echo "Index file: index.html found"
        elif [ -f "$site_path/index.php" ]; then
            echo "Index file: index.php found"
        else
            echo "Warning: No index.html or index.php found in root directory"
        fi
    else
        echo "Error: Failed to extract backup"
        return 1
    fi
}

interactive_mode() {
    readarray -t backup_files < <(find_static_backups)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo "No static website backups found in $BACKUP_DIR"
        exit 1
    fi
    
    echo "Available static website backups:"
    echo "=================================="
    
    for i in "${!backup_files[@]}"; do
        local backup_file="${backup_files[$i]}"
        local filename=$(basename "$backup_file")
        local site_name=$(extract_site_name "$backup_file")
        local file_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        local file_date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        echo "[$((i+1))] $filename"
        echo "     Site: $site_name"
        echo "     Size: ${file_size:-unknown}"
        echo "     Date: ${file_date:-unknown}"
        echo ""
    done
    
    read -p "Enter the number of the backup to restore (1-${#backup_files[@]}): " backup_number
    
    if ! [[ "$backup_number" =~ ^[0-9]+$ ]] || \
       [ "$backup_number" -lt 1 ] || \
       [ "$backup_number" -gt ${#backup_files[@]} ]; then
        echo "Invalid backup number selected"
        exit 1
    fi
    
    selected_backup="${backup_files[$((backup_number-1))]}"
    restore_site "$selected_backup"
}

main() {
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    [ ! -d "$BACKUP_DIR" ] && { echo "Error: Backup directory $BACKUP_DIR not found"; exit 1; }
    
    case "${1:-}" in
        --backup)
            [ -z "$2" ] && { echo "Error: Backup file name required"; exit 1; }
            
            # Check if it's a full path or just filename
            if [[ "$2" == *"/"* ]]; then
                backup_file="$2"
            else
                backup_file="$BACKUP_DIR/$2"
            fi
            
            restore_site "$backup_file"
            ;;
        --list)
            echo "Available static website backups:"
            readarray -t backup_files < <(find_static_backups)
            
            if [ ${#backup_files[@]} -eq 0 ]; then
                echo "No static website backups found"
                exit 0
            fi
            
            for backup_file in "${backup_files[@]}"; do
                local filename=$(basename "$backup_file")
                local site_name=$(extract_site_name "$backup_file")
                local file_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
                local file_date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
                echo "  $filename (Site: $site_name, Size: ${file_size:-?}, Date: ${file_date:-?})"
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
    
    echo "Restore completed"
}

main "$@"