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
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Variables to be populated from config
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
DB_PORT=""
SELECTED_DOMAIN=""

# Function to discover available domains
discover_domains() {
    local domains=()
    if [[ -d "$WWW_PATH" ]]; then
        for domain_dir in "$WWW_PATH"/*; do
            if [[ -d "$domain_dir" && -f "$domain_dir/config.json" ]]; then
                local domain_name=$(basename "$domain_dir")
                # Check if config.json has database section and SQL dump exists
                if jq -e '.database' "$domain_dir/config.json" >/dev/null 2>&1 && [[ -f "$domain_dir/${domain_name}_postgres_db.sql" ]]; then
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
        echo "Error: No domains with SQL backup files found"
        exit 1
    fi
    
    echo -e "${CYAN}Available domains with database backups:${NC}"
    for i in "${!domains[@]}"; do
        local domain="${domains[i]}"
        local sql_file="$WWW_PATH/$domain/${domain}_postgres_db.sql"
        local file_size=$(du -h "$sql_file" 2>/dev/null | cut -f1)
        local file_date=$(stat -c %y "$sql_file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo -e "${YELLOW}$((i+1)).${NC} ${domain} (${file_size:-?}, ${file_date:-unknown date})"
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

# PostgreSQL restore function
restore_postgresql() {
    local site_path="$WWW_PATH/$SELECTED_DOMAIN"
    local sql_file="${site_path}/${SELECTED_DOMAIN}_postgres_db.sql"
    
    if [[ ! -f "$sql_file" ]]; then
        echo "Error: SQL backup file not found: $sql_file"
        exit 1
    fi
    
    echo "Starting PostgreSQL restore for $SELECTED_DOMAIN..."
    echo "SQL file: $sql_file"
    
    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        echo "Starting PostgreSQL service..."
        sudo systemctl start postgresql || { echo "Failed to start PostgreSQL"; exit 1; }
    fi
    
    # Setup database and user
    echo "Setting up database and user..."
    sudo -u postgres psql <<EOF
-- Drop database if it exists
DROP DATABASE IF EXISTS $DB_NAME;

-- Drop user if it exists and recreate  
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    # Restore from SQL file
    echo "Restoring database from SQL file..."
    
    export PGHOST="$DB_HOST"
    export PGPORT="$DB_PORT"
    export PGUSER="$DB_USER"
    export PGPASSWORD="$DB_PASS"
    
    psql -d "$DB_NAME" < "$sql_file" || {
        echo "Database restoration failed"
        unset PGPASSWORD
        exit 1
    }
    
    unset PGPASSWORD
    
    echo "PostgreSQL restoration completed successfully!"
    
    # Clean up SQL file after successful restoration
    echo "Cleaning up SQL backup file..."
    rm "$sql_file" && echo "SQL backup file deleted: $sql_file" || echo "Warning: Could not delete SQL backup file: $sql_file"
}

# Main execution flow
main() {
    # Check if www path exists
    [ ! -d "$WWW_PATH" ] && { echo "Error: $WWW_PATH not found"; exit 1; }
    
    echo "PostgreSQL Restore Tool"
    echo
    
    # Select domain
    select_domain
    
    # Load database configuration
    load_database_config
    
    # Confirm before proceeding
    echo
    read -p "Restore $SELECTED_DOMAIN database? [Y/n]: " -n 1 -r
    echo
    if [[ ! -z "$REPLY" && ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        exit 0
    fi
    
    # Execute restore
    restore_postgresql
}

main "$@"