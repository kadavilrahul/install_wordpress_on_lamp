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
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_RETENTION_DAYS=7

# Variables to be populated from config
SELECTED_DOMAIN=""

# Non-interactive mode flag
NON_INTERACTIVE=false

# Function to check if site is WordPress
is_wordpress() {
    [ -f "$1/wp-config.php" ] || ([ -f "$1/wp-config-sample.php" ] && [ -d "$1/wp-includes" ])
}

# Function to check if site is static with PostgreSQL
is_static_with_postgres() {
    local dir="$1"
    local site_name="$2"
    
    # Skip html directory (default Apache directory)
    [ "$site_name" = "html" ] && return 1
    
    # Skip if it's a WordPress site
    is_wordpress "$dir" && return 1
    
    # Check if it has config.json with database section
    [ ! -f "$dir/config.json" ] && return 1
    
    # Check if config.json has database section
    if ! jq -e '.database' "$dir/config.json" >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if directory has web files
    if [ -f "$dir/index.html" ] || [ -f "$dir/index.php" ] || [ -n "$(find "$dir" -maxdepth 2 -name "*.html" -o -name "*.php" -o -name "*.css" -o -name "*.js" 2>/dev/null | head -1)" ]; then
        return 0
    fi
    
    return 1
}

# Function to discover available static sites with PostgreSQL
discover_static_postgres_sites() {
    local sites=()
    if [[ -d "$WWW_PATH" ]]; then
        for site_dir in "$WWW_PATH"/*; do
            if [[ -d "$site_dir" ]]; then
                local site_name=$(basename "$site_dir")
                if is_static_with_postgres "$site_dir" "$site_name"; then
                    sites+=("$site_name")
                fi
            fi
        done
    fi
    echo "${sites[@]}"
}

# Function to check if PostgreSQL databases exist for a site
check_postgres_databases() {
    local config_file="$WWW_PATH/$SELECTED_DOMAIN/config.json"
    local found_databases=()
    local unique_databases=()
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql || return 1
    fi
    
    # Check if the config has a single database or multiple databases
    if jq -e '.database.name' "$config_file" >/dev/null 2>&1; then
        # Single database configuration
        local db_name=$(jq -r '.database.name' "$config_file")
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name" 2>/dev/null; then
            found_databases+=("$db_name")
        fi
    elif jq -e '.database | type == "object"' "$config_file" >/dev/null 2>&1; then
        # Multiple database configuration
        local db_keys=$(jq -r '.database | keys[]' "$config_file")
        while IFS= read -r key; do
            local db_name=$(jq -r ".database.$key.name // empty" "$config_file")
            if [[ -n "$db_name" ]] && sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name" 2>/dev/null; then
                found_databases+=("$db_name")
            fi
        done <<< "$db_keys"
    fi
    
    # Remove duplicates from found_databases
    if [[ ${#found_databases[@]} -gt 0 ]]; then
        # Use associative array to remove duplicates
        declare -A seen
        for db in "${found_databases[@]}"; do
            if [[ -z "${seen[$db]}" ]]; then
                unique_databases+=("$db")
                seen[$db]=1
            fi
        done
        
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Found PostgreSQL databases: ${unique_databases[*]}"
        return 0
    else
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "No PostgreSQL databases found for $SELECTED_DOMAIN"
        return 1
    fi
}

# Function to backup PostgreSQL databases for a site
backup_postgres_databases() {
    local config_file="$WWW_PATH/$SELECTED_DOMAIN/config.json"
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local backup_count=0
    declare -A processed_databases
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL backup for $SELECTED_DOMAIN..."
    
    # Check if the config has a single database or multiple databases
    if jq -e '.database.name' "$config_file" >/dev/null 2>&1; then
        # Single database configuration
        local db_name=$(jq -r '.database.name' "$config_file")
        local db_user=$(jq -r '.database.user' "$config_file")
        local db_pass=$(jq -r '.database.password' "$config_file")
        local db_host=$(jq -r '.database.host // "localhost"' "$config_file")
        local db_port=$(jq -r '.database.port // "5432"' "$config_file")
        
        if backup_single_database "$db_name" "$db_user" "$db_pass" "$db_host" "$db_port" "default"; then
            ((backup_count++))
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
                if backup_single_database "$db_name" "$db_user" "$db_pass" "$db_host" "$db_port" "$key"; then
                    ((backup_count++))
                    processed_databases["$db_name"]=1
                fi
            fi
        done <<< "$db_keys"
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Backed up $backup_count PostgreSQL databases"
    return $([[ $backup_count -gt 0 ]] && echo 0 || echo 1)
}

# Function to backup a single database
backup_single_database() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_host="$4"
    local db_port="$5"
    local db_key="$6"
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local sql_file="${site_path}/${SELECTED_DOMAIN}_${db_key}_postgres.sql"
    
    # Check if database exists
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name" 2>/dev/null; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Database $db_name does not exist, skipping..."
        return 1
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating PostgreSQL backup for database: $db_name..."
    
    export PGHOST="$db_host"
    export PGPORT="$db_port" 
    export PGUSER="$db_user"
    export PGPASSWORD="$db_pass"
    
    pg_dump --no-owner --no-privileges --clean --if-exists "$db_name" > "$sql_file" 2>/dev/null || {
        echo "Error: PostgreSQL backup failed for database $db_name"
        unset PGPASSWORD
        return 1
    }
    
    unset PGPASSWORD
    
    echo "✓ PostgreSQL backup: $sql_file"
    return 0
}

# Function to backup static site files
backup_static_files() {
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local backup_name="${SELECTED_DOMAIN}_static_postgres_backup_${TIMESTAMP}.tar.gz"
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating static site backup for: $SELECTED_DOMAIN"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Create backup including PostgreSQL dumps
    cd "$WWW_PATH" && tar -czf "$BACKUP_DIR/$backup_name" "$SELECTED_DOMAIN" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✓ Static site backup created: $backup_name"
        
        # Show backup info
        local backup_size=$(du -h "$BACKUP_DIR/$backup_name" 2>/dev/null | cut -f1)
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Backup size: ${backup_size:-unknown}"
        return 0
    else
        echo "✗ Error: Failed to create backup for $SELECTED_DOMAIN"
        return 1
    fi
}

# Function to cleanup PostgreSQL dump files
cleanup_postgres_dumps() {
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local config_file="$site_path/config.json"
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Cleaning up PostgreSQL dump files..."
    
    # Remove PostgreSQL dump files from site directory
    find "$site_path" -name "${SELECTED_DOMAIN}_*_postgres.sql" -delete 2>/dev/null
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "PostgreSQL dump files cleaned up"
}

# Function to display site selection menu
select_site() {
    local sites=($(discover_static_postgres_sites))
    
    if [[ ${#sites[@]} -eq 0 ]]; then
        echo "Error: No static sites with PostgreSQL configuration found in $WWW_PATH"
        exit 1
    fi
    
    echo -e "${CYAN}Available static sites with PostgreSQL:${NC}"
    for i in "${!sites[@]}"; do
        local site="${sites[i]}"
        local site_path="$WWW_PATH/$site"
        local file_count=$(find "$site_path" -type f 2>/dev/null | wc -l)
        local dir_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}$((i+1)).${NC} ${site} (${file_count} files, ${dir_size:-unknown size})"
    done
    echo
    
    while true; do
        read -p "$(echo -e "${CYAN}Select site (1-${#sites[@]}): ${NC}")" choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le "${#sites[@]}" ]]; then
            SELECTED_DOMAIN="${sites[$((choice-1))]}"
            break
        else
            echo -e "${RED}Invalid selection. Please choose 1-${#sites[@]}.${NC}"
        fi
    done
    
    echo "Selected site: $SELECTED_DOMAIN"
}

# Function to backup a specific site without prompts
backup_site_direct() {
    local site="$1"
    SELECTED_DOMAIN="$site"
    
    # Check if site directory exists
    if [[ ! -d "$WWW_PATH/$SELECTED_DOMAIN" ]]; then
        echo "Error: Site directory not found: $WWW_PATH/$SELECTED_DOMAIN"
        return 1
    fi
    
    # Check if it's a static site with PostgreSQL
    if ! is_static_with_postgres "$WWW_PATH/$SELECTED_DOMAIN" "$SELECTED_DOMAIN"; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Info: $SELECTED_DOMAIN is not a static site with PostgreSQL configuration"
        return 1
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Backing up static site + PostgreSQL for $SELECTED_DOMAIN..."
    
    # Check if databases exist
    if ! check_postgres_databases; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: No PostgreSQL databases found for $SELECTED_DOMAIN"
    fi
    
    # Backup PostgreSQL databases
    backup_postgres_databases
    postgres_result=$?
    
    # Backup static site files (including PostgreSQL dumps)
    backup_static_files
    files_result=$?
    
    # Cleanup PostgreSQL dump files
    cleanup_postgres_dumps
    
    # Return success if either backup succeeded
    if [[ $postgres_result -eq 0 ]] || [[ $files_result -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to show usage help
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --site <site_name>    Backup specific static site + PostgreSQL"
    echo "  --all                 Backup all static sites + PostgreSQL"
    echo "  --first               Backup first static site + PostgreSQL only"
    echo "  --list                List available static sites with PostgreSQL"
    echo "  --check <site_name>   Check if PostgreSQL databases exist for site"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --site agnoagents.online"
    echo "  $0 --all"
    echo "  $0 --first"
    echo "  $0 --check agnoagents.online"
    echo ""
    echo "If no arguments provided, interactive menu will be shown."
}

# Main execution flow
main() {
    # Check if www path exists
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --site)
            if [[ -z "$2" ]]; then
                echo "Error: Site name required"
                show_usage
                exit 1
            fi
            NON_INTERACTIVE=true
            backup_site_direct "$2"
            exit $?
            ;;
        --all)
            NON_INTERACTIVE=true
            local sites=($(discover_static_postgres_sites))
            if [[ ${#sites[@]} -eq 0 ]]; then
                echo "No static sites with PostgreSQL configuration found"
                exit 0
            fi
            local exit_code=0
            for site in "${sites[@]}"; do
                backup_site_direct "$site" || exit_code=1
            done
            exit $exit_code
            ;;
        --first)
            NON_INTERACTIVE=true
            local sites=($(discover_static_postgres_sites))
            if [[ ${#sites[@]} -eq 0 ]]; then
                echo "No static sites with PostgreSQL configuration found"
                exit 0
            fi
            backup_site_direct "${sites[0]}"
            exit $?
            ;;
        --check)
            if [[ -z "$2" ]]; then
                echo "Error: Site name required"
                show_usage
                exit 1
            fi
            SELECTED_DOMAIN="$2"
            if [[ ! -d "$WWW_PATH/$SELECTED_DOMAIN" ]]; then
                echo "Error: Site directory not found: $WWW_PATH/$SELECTED_DOMAIN"
                exit 1
            fi
            if ! is_static_with_postgres "$WWW_PATH/$SELECTED_DOMAIN" "$SELECTED_DOMAIN"; then
                echo "Site $SELECTED_DOMAIN is not a static site with PostgreSQL configuration"
                exit 1
            fi
            check_postgres_databases
            exit $?
            ;;
        --list)
            echo "Available static sites with PostgreSQL configuration:"
            local sites=($(discover_static_postgres_sites))
            if [[ ${#sites[@]} -eq 0 ]]; then
                echo "  (none found)"
            else
                for site in "${sites[@]}"; do
                    local site_path="$WWW_PATH/$site"
                    local file_count=$(find "$site_path" -type f 2>/dev/null | wc -l)
                    local dir_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
                    echo "  $site (${file_count} files, ${dir_size:-unknown size})"
                done
            fi
            exit 0
            ;;
        "")
            # Interactive mode
            echo "Static Site + PostgreSQL Backup Tool"
            echo
            
            # Select site
            select_site
            
            # Check if databases exist
            echo
            echo "Checking PostgreSQL databases for $SELECTED_DOMAIN..."
            if ! check_postgres_databases; then
                echo "Warning: No PostgreSQL databases found for $SELECTED_DOMAIN"
                read -p "Continue with static files backup only? [Y/n]: " -n 1 -r
                echo
                if [[ ! -z "$REPLY" && ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Backup cancelled"
                    exit 0
                fi
            fi
            
            # Confirm before proceeding
            echo
            read -p "Backup $SELECTED_DOMAIN (static files + PostgreSQL)? [Y/n]: " -n 1 -r
            echo
            if [[ ! -z "$REPLY" && ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Backup cancelled"
                exit 0
            fi
            
            # Execute backup
            backup_postgres_databases
            postgres_result=$?
            
            backup_static_files
            files_result=$?
            
            cleanup_postgres_dumps
            
            echo
            echo "Backup Summary:"
            if [[ $postgres_result -eq 0 ]]; then
                echo "✓ PostgreSQL backup: Completed successfully"
            else
                echo "✗ PostgreSQL backup: Failed or no databases found"
            fi
            
            if [[ $files_result -eq 0 ]]; then
                echo "✓ Static files backup: Completed successfully"
            else
                echo "✗ Static files backup: Failed"
            fi
            
            if [[ $postgres_result -eq 0 ]] || [[ $files_result -eq 0 ]]; then
                echo "✓ Overall backup completed successfully!"
            else
                echo "✗ Backup failed"
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