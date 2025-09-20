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
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
DB_PORT=""
SELECTED_DOMAIN=""

# SSH Configuration
SSH_TIMEOUT=30
SSH_CONNECT_TIMEOUT=10

# Non-interactive mode flag
NON_INTERACTIVE=false



# Function to discover available domains
discover_domains() {
    local domains=()
    if [[ -d "$WWW_PATH" ]]; then
        for domain_dir in "$WWW_PATH"/*; do
            if [[ -d "$domain_dir" && -f "$domain_dir/config.json" ]]; then
                local domain_name=$(basename "$domain_dir")
                # Check if config.json has database section
                if jq -e '.database' "$domain_dir/config.json" >/dev/null 2>&1; then
                    domains+=("$domain_name")
                fi
            fi
        done
    fi
    echo "${domains[@]}"
}

# Function to display domain selection menu
select_domain() {
    local domains=($(discover_domains))
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "Error: No domains with valid config.json files found in $WWW_PATH"
        exit 1
    fi
    
    echo -e "${CYAN}Available domains:${NC}"
    for i in "${!domains[@]}"; do
        echo -e "${YELLOW}$((i+1)).${NC} ${domains[i]}"
    done
    echo
    
    while true; do
        read -p "$(echo -e "${CYAN}Select domain (1-${#domains[@]}): ${NC}")" choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le "${#domains[@]}" ]]; then
            SELECTED_DOMAIN="${domains[$((choice-1))]}"
            break
        else
            echo -e "${RED}Invalid selection. Please choose 1-${#domains[@]}.${NC}"
        fi
    done
    
    echo "Selected domain: $SELECTED_DOMAIN"
}

# Function to load database configuration from domain's config.json
load_database_config() {
    local config_file="$WWW_PATH/$SELECTED_DOMAIN/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file"
        return 1
    fi
    
    # Validate JSON and extract database configuration
    if ! jq empty "$config_file" 2>/dev/null; then
        echo "Error: Invalid JSON in config file: $config_file"
        return 1
    fi
    
    DB_NAME=$(jq -r '.database.name // empty' "$config_file")
    DB_USER=$(jq -r '.database.user // empty' "$config_file")
    DB_PASS=$(jq -r '.database.password // empty' "$config_file")
    DB_HOST=$(jq -r '.database.host // "localhost"' "$config_file")
    DB_PORT=$(jq -r '.database.port // "5432"' "$config_file")
    
    # Validate required fields
    if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
        echo "Error: Missing required database configuration in $config_file (name, user, password)"
        return 1
    fi
    
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo "Loaded database config for $SELECTED_DOMAIN"
        echo "Database: $DB_NAME"
        echo "User: $DB_USER"
        echo "Host: $DB_HOST:$DB_PORT"
    fi
    return 0
}

# PostgreSQL backup function
backup_postgres() {
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local sql_file="${site_path}/${SELECTED_DOMAIN}_postgres_db.sql"
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL backup for $SELECTED_DOMAIN..."
    
    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql || { echo "Failed to start PostgreSQL"; return 1; }
    fi
    
    # Create database and user if they don't exist (only if they don't exist)
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME" 2>/dev/null; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Database $DB_NAME does not exist, creating..."
        sudo -u postgres createdb "$DB_NAME" 2>/dev/null || [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: Could not create database"
    fi
    
    if ! sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null | grep -q 1; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "User $DB_USER does not exist, creating..."
        sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';" 2>/dev/null || [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: Could not create user"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>/dev/null || [[ "$NON_INTERACTIVE" != "true" ]] && echo "Warning: Could not grant privileges"
    fi
    
    # Perform backup - create SQL file in domain folder
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Creating PostgreSQL backup..."
    
    export PGHOST="$DB_HOST"
    export PGPORT="$DB_PORT" 
    export PGUSER="$DB_USER"
    export PGPASSWORD="$DB_PASS"
    
    pg_dump --no-owner --no-privileges --clean --if-exists "$DB_NAME" > "$sql_file" 2>/dev/null || {
        echo "Error: PostgreSQL backup failed for $SELECTED_DOMAIN"
        unset PGPASSWORD
        return 1
    }
    
    unset PGPASSWORD
    
    echo "✓ PostgreSQL backup: $sql_file"
    return 0
}

# Function to backup a specific domain without prompts
backup_domain_direct() {
    local domain="$1"
    SELECTED_DOMAIN="$domain"
    
    # Check if domain directory exists
    if [[ ! -d "$WWW_PATH/$SELECTED_DOMAIN" ]]; then
        echo "Error: Domain directory not found: $WWW_PATH/$SELECTED_DOMAIN"
        return 1
    fi
    
    # Check if config.json exists
    if [[ ! -f "$WWW_PATH/$SELECTED_DOMAIN/config.json" ]]; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Info: No config.json found for $SELECTED_DOMAIN, skipping PostgreSQL backup"
        return 0
    fi
    
    # Check if config has database section
    if ! jq -e '.database' "$WWW_PATH/$SELECTED_DOMAIN/config.json" >/dev/null 2>&1; then
        [[ "$NON_INTERACTIVE" != "true" ]] && echo "Info: No database configuration for $SELECTED_DOMAIN, skipping PostgreSQL backup"
        return 0
    fi
    
    [[ "$NON_INTERACTIVE" != "true" ]] && echo "Backing up PostgreSQL for $SELECTED_DOMAIN..."
    load_database_config
    backup_postgres
    return $?
}

# Function to show usage help
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --site <site_name>    Backup specific site's PostgreSQL database"
    echo "  --all                 Backup all sites' PostgreSQL databases"
    echo "  --first               Backup first site's PostgreSQL database only"
    echo "  --list                List available sites with PostgreSQL"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --site nilgiristores.in"
    echo "  $0 --all"
    echo "  $0 --first"
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
            backup_domain_direct "$2"
            exit $?
            ;;
        --all)
            NON_INTERACTIVE=true
            local domains=($(discover_domains))
            if [[ ${#domains[@]} -eq 0 ]]; then
                echo "No domains with PostgreSQL configuration found"
                exit 0
            fi
            local exit_code=0
            for domain in "${domains[@]}"; do
                backup_domain_direct "$domain" || exit_code=1
            done
            exit $exit_code
            ;;
        --first)
            NON_INTERACTIVE=true
            local domains=($(discover_domains))
            if [[ ${#domains[@]} -eq 0 ]]; then
                echo "No domains with PostgreSQL configuration found"
                exit 0
            fi
            backup_domain_direct "${domains[0]}"
            exit $?
            ;;
        --list)
            echo "Available sites with PostgreSQL configuration:"
            local domains=($(discover_domains))
            if [[ ${#domains[@]} -eq 0 ]]; then
                echo "  (none found)"
            else
                for domain in "${domains[@]}"; do
                    echo "  $domain"
                done
            fi
            exit 0
            ;;
        "")
            # Interactive mode
            echo "PostgreSQL Backup Tool"
            echo
            
            # Select domain
            select_domain
            
            # Load database configuration
            load_database_config
            
            # Confirm before proceeding
            echo
            read -p "Backup $SELECTED_DOMAIN? [Y/n]: " -n 1 -r
            echo
            if [[ ! -z "$REPLY" && ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Backup cancelled"
                exit 0
            fi
            
            # Execute backup
            backup_postgres
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"