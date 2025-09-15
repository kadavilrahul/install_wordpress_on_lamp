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
        exit 1
    fi
    
    # Validate JSON and extract database configuration
    if ! jq empty "$config_file" 2>/dev/null; then
        echo "Error: Invalid JSON in config file: $config_file"
        exit 1
    fi
    
    DB_NAME=$(jq -r '.database.name // empty' "$config_file")
    DB_USER=$(jq -r '.database.user // empty' "$config_file")
    DB_PASS=$(jq -r '.database.password // empty' "$config_file")
    DB_HOST=$(jq -r '.database.host // "localhost"' "$config_file")
    DB_PORT=$(jq -r '.database.port // "5432"' "$config_file")
    
    # Validate required fields
    if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
        echo "Error: Missing required database configuration in $config_file (name, user, password)"
        exit 1
    fi
    
    echo "Loaded database config for $SELECTED_DOMAIN"
    echo "Database: $DB_NAME"
    echo "User: $DB_USER"
    echo "Host: $DB_HOST:$DB_PORT"
}

# PostgreSQL backup function
backup_postgres() {
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local sql_file="${site_path}/${SELECTED_DOMAIN}_db.sql"
    
    echo "Starting PostgreSQL backup for $SELECTED_DOMAIN..."
    
    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql || { echo "Failed to start PostgreSQL"; exit 1; }
    fi
    
    # Create database and user if they don't exist (only if they don't exist)
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo "Database $DB_NAME does not exist, creating..."
        sudo -u postgres createdb "$DB_NAME" || echo "Warning: Could not create database"
    fi
    
    if ! sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        echo "User $DB_USER does not exist, creating..."
        sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';" || echo "Warning: Could not create user"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" || echo "Warning: Could not grant privileges"
    fi
    
    # Perform backup - create SQL file in domain folder
    echo "Creating PostgreSQL backup..."
    
    export PGHOST="$DB_HOST"
    export PGPORT="$DB_PORT" 
    export PGUSER="$DB_USER"
    export PGPASSWORD="$DB_PASS"
    
    pg_dump --no-owner --no-privileges --clean --if-exists "$DB_NAME" > "$sql_file" 2>/dev/null || {
        echo "PostgreSQL backup failed"
        unset PGPASSWORD
        exit 1
    }
    
    unset PGPASSWORD
    
    echo "PostgreSQL backup created: $sql_file"
}

# Main execution flow
main() {
    # Check if www path exists
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    
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
}

main "$@"