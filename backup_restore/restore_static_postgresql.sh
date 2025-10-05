#!/bin/bash

# Colors and globals
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"

# Non-interactive mode flag
NON_INTERACTIVE=false

# Function to find static site with PostgreSQL backups
find_static_postgres_backups() {
    find "$BACKUP_DIR" -maxdepth 1 -name "*_static_postgres_backup_*.tar.gz" -type f 2>/dev/null | sort -r
}

# Function to extract site name from backup filename
extract_site_name() {
    local backup_file="$1"
    local filename=$(basename "$backup_file")
    echo "$filename" | sed 's/_static_postgres_backup_.*\.tar\.gz$//'
}

# Function to restore PostgreSQL databases
restore_postgres_databases() {
    local site_name="$1"
    local site_path="$WWW_PATH/$site_name"
    local config_file="$site_path/config.json"
    local restored_count=0
    declare -A processed_databases
    
    if [[ ! -f "$config_file" ]]; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: No config.json found for $site_name, skipping PostgreSQL restore"
        return 0
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL restore for $site_name..."
    
    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql || {
            echo "Error: Failed to start PostgreSQL"
            return 1
        }
    fi
    
    # Check if the config has a single database or multiple databases
    if jq -e '.database.name' "$config_file" >/dev/null 2>&1; then
        # Single database configuration
        local db_name=$(jq -r '.database.name' "$config_file")
        local db_user=$(jq -r '.database.user' "$config_file")
        local db_pass=$(jq -r '.database.password' "$config_file")
        local db_host=$(jq -r '.database.host // "localhost"' "$config_file")
        local db_port=$(jq -r '.database.port // "5432"' "$config_file")
        
        if restore_single_database "$site_name" "$db_name" "$db_user" "$db_pass" "$db_host" "$db_port" "default"; then
            ((restored_count++))
            processed_databases["$db_name"]=1
        fi
    elif jq -e '.database | type == "object"' "$config_file" >/dev/null 2>&1; then
        # Multiple database configuration
        local db_keys=$(jq -r '.database | keys[]' "$config_file")
        while IFS= read -r key; do
            local db_name=$(jq -r ".database.$key.name // empty" "$config_file")
            local db_user=$(jq -r ".database.$key.user // empty" "$config_file")
            local db_pass=$(jq -r ".database.$key.password // empty" "$config_file")
            local db_host=$(jq -r ".database.$key.host // \"localhost\"" "$config_file")
            local db_port=$(jq -r ".database.$key.port // \"5432\"" "$config_file")
            
            # Skip if we've already processed this database
            if [[ -n "$db_name" && -n "$db_user" && -n "$db_pass" && -z "${processed_databases[$db_name]}" ]]; then
                if restore_single_database "$site_name" "$db_name" "$db_user" "$db_pass" "$db_host" "$db_port" "$key"; then
                    ((restored_count++))
                    processed_databases["$db_name"]=1
                fi
            fi
        done <<< "$db_keys"
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Restored $restored_count PostgreSQL databases"
    return 0
}

# Function to restore a single database
restore_single_database() {
    local site_name="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"
    local db_host="$5"
    local db_port="$6"
    local db_key="$7"
    local site_path="$WWW_PATH/$site_name"
    local sql_file="${site_path}/${site_name}_${db_key}_postgres.sql"
    
    # Check if SQL dump file exists
    if [[ ! -f "$sql_file" ]]; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: PostgreSQL dump file not found: $sql_file"
        return 1
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Restoring PostgreSQL database: $db_name from $sql_file"
    
    # Create database and user if they don't exist
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name" 2>/dev/null; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating database: $db_name"
        sudo -u postgres createdb "$db_name" || {
            echo "Error: Failed to create database $db_name"
            return 1
        }
    fi
    
    if ! sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" 2>/dev/null | grep -q 1; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating user: $db_user"
        sudo -u postgres psql -c "CREATE ROLE $db_user WITH LOGIN PASSWORD '$db_pass';" || {
            echo "Error: Failed to create user $db_user"
            return 1
        }
    fi
    
    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;" || {
        echo "Warning: Could not grant privileges to $db_user"
    }
    
    # Restore database from SQL file
    export PGHOST="$db_host"
    export PGPORT="$db_port" 
    export PGUSER="$db_user"
    export PGPASSWORD="$db_pass"
    
    psql "$db_name" < "$sql_file" >/dev/null 2>&1 || {
        echo "Error: Failed to restore database $db_name from $sql_file"
        unset PGPASSWORD
        return 1
    }
    
    unset PGPASSWORD
    
    echo "✓ PostgreSQL database restored: $db_name"
    return 0
}

# Function to restore static site files
restore_static_files() {
    local backup_file="$1"
    local site_name=$(extract_site_name "$backup_file")
    local site_path="$WWW_PATH/$site_name"
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Restoring static site: $site_name"
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "From backup: $(basename "$backup_file")"
    
    # Check if site directory exists
    if [ -d "$site_path" ]; then
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            echo "Warning: Site directory already exists: $site_path"
            read -p "Do you want to overwrite it? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Restore cancelled"
                return 0
            fi
        fi
        
        # Backup existing site
        local existing_backup="${site_name}_existing_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating backup of existing site: $existing_backup"
        cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$existing_backup" "$site_name" 2>/dev/null
        
        # Remove existing site
        rm -rf "$site_path"
    fi
    
    # Extract backup
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Extracting backup..."
    cd "$WWW_PATH" && tar -xzf "$backup_file"
    
    if [ $? -eq 0 ]; then
        # Set proper permissions
        chown -R www-data:www-data "$site_path"
        find "$site_path" -type d -exec chmod 755 {} \;
        find "$site_path" -type f -exec chmod 644 {} \;
        
        echo "✓ Static site files restored to: $site_path"
        
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
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
        fi
        return 0
    else
        echo "Error: Failed to extract backup"
        return 1
    fi
}

# Function to cleanup PostgreSQL dump files after restore
cleanup_postgres_dumps() {
    local site_name="$1"
    local site_path="$WWW_PATH/$site_name"
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Cleaning up PostgreSQL dump files..."
    
    # Remove PostgreSQL dump files from site directory
    find "$site_path" -name "${site_name}_*_postgres.sql" -delete 2>/dev/null
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "PostgreSQL dump files cleaned up"
}

# Function to display backup selection menu
select_backup() {
    readarray -t backup_files < <(find_static_postgres_backups)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo "No static site + PostgreSQL backups found in $BACKUP_DIR"
        exit 1
    fi
    
    echo -e "${CYAN}Available static site + PostgreSQL backups:${NC}"
    for i in "${!backup_files[@]}"; do
        local backup_file="${backup_files[i]}"
        local site_name=$(extract_site_name "$backup_file")
        local backup_date=$(basename "$backup_file" | sed 's/.*_static_postgres_backup_\([0-9-_]*\)\.tar\.gz$/\1/' | tr '_' ' ')
        local backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}$((i+1)).${NC} ${site_name} (${backup_date}, ${backup_size:-unknown size})"
    done
    echo
    
    while true; do
        read -p "$(echo -e "${CYAN}Select backup to restore (1-${#backup_files[@]}): ${NC}")" choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le "${#backup_files[@]}" ]]; then
            echo "${backup_files[$((choice-1))]}"
            break
        else
            echo -e "${RED}Invalid selection. Please choose 1-${#backup_files[@]}.${NC}"
        fi
    done
}

# Function to restore a specific backup without prompts
restore_backup_direct() {
    local backup_file="$1"
    local site_name=$(extract_site_name "$backup_file")
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Restoring static site + PostgreSQL for $site_name..."
    
    # Restore static site files
    restore_static_files "$backup_file"
    files_result=$?
    
    if [[ $files_result -eq 0 ]]; then
        # Restore PostgreSQL databases
        restore_postgres_databases "$site_name"
        postgres_result=$?
        
        # Cleanup PostgreSQL dump files
        cleanup_postgres_dumps "$site_name"
        
        # Return success if files were restored (PostgreSQL is optional)
        return 0
    else
        return 1
    fi
}

# Function to show usage help
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --backup <backup_file>    Restore from specific backup file"
    echo "  --list                    List available static + PostgreSQL backups"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --backup agnoagents.online_static_postgres_backup_2025-10-05_12-30-45.tar.gz"
    echo "  $0 --list"
    echo ""
    echo "If no arguments provided, interactive menu will be shown."
}

# Main execution flow
main() {
    # Check if backup directory exists
    [ ! -d "$BACKUP_DIR" ] && { echo "Error: Backup directory not found: $BACKUP_DIR"; exit 1; }
    
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --backup)
            if [[ -z "$2" ]]; then
                echo "Error: Backup filename required"
                show_usage
                exit 1
            fi
            NON_INTERACTIVE=true
            local backup_file="$2"
            # Handle relative and absolute paths
            if [[ ! "$backup_file" = /* ]]; then
                backup_file="$BACKUP_DIR/$backup_file"
            fi
            restore_backup_direct "$backup_file"
            exit $?
            ;;
        --list)
            echo "Available static site + PostgreSQL backups:"
            readarray -t backup_files < <(find_static_postgres_backups)
            if [[ ${#backup_files[@]} -eq 0 ]]; then
                echo "  (none found)"
            else
                for backup_file in "${backup_files[@]}"; do
                    local site_name=$(extract_site_name "$backup_file")
                    local backup_date=$(basename "$backup_file" | sed 's/.*_static_postgres_backup_\([0-9-_]*\)\.tar\.gz$/\1/' | tr '_' ' ')
                    local backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
                    echo "  $(basename "$backup_file") - $site_name (${backup_date}, ${backup_size:-unknown size})"
                done
            fi
            exit 0
            ;;
        "")
            # Interactive mode
            echo "Static Site + PostgreSQL Restore Tool"
            echo
            
            # Select backup
            backup_file=$(select_backup)
            site_name=$(extract_site_name "$backup_file")
            
            # Confirm before proceeding
            echo
            echo "Selected backup: $(basename "$backup_file")"
            echo "Site to restore: $site_name"
            echo
            read -p "Proceed with restore? [Y/n]: " -n 1 -r
            echo
            if [[ ! -z "$REPLY" && ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Restore cancelled"
                exit 0
            fi
            
            # Execute restore
            restore_static_files "$backup_file"
            files_result=$?
            
            if [[ $files_result -eq 0 ]]; then
                restore_postgres_databases "$site_name"
                postgres_result=$?
                
                cleanup_postgres_dumps "$site_name"
                
                echo
                echo "Restore Summary:"
                echo "✓ Static files restore: Completed successfully"
                
                if [[ $postgres_result -eq 0 ]]; then
                    echo "✓ PostgreSQL restore: Completed successfully"
                else
                    echo "✗ PostgreSQL restore: Failed or no databases to restore"
                fi
                
                echo "✓ Overall restore completed successfully!"
                echo "Site restored to: $WWW_PATH/$site_name"
            else
                echo
                echo "✗ Restore failed - could not extract static files"
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"