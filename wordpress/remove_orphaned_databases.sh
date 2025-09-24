#!/bin/bash

# Colors and globals
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE="/var/log/wordpress_master_$(date +%Y%m%d_%H%M%S).log"

# Utility functions
log() { echo "[$1] $2" | tee -a "$LOG_FILE"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# System checks
check_root() { [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"; }

# Configuration management
load_config() {
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/../config.json" ]; then
        ADMIN_EMAIL=$(jq -r '.admin_email // ""' config.json)
        REDIS_MAX_MEMORY=$(jq -r '.redis_max_memory // "1"' config.json)
        DB_ROOT_PASSWORD=$(jq -r '.mysql_root_password // ""' config.json)
        

        
        # Try to get first domain from each section
        DOMAIN=$(jq -r '.main_domains[0] // ""' config.json)
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdomains[0] // ""' config.json)
        [ -z "$DOMAIN" ] && DOMAIN=$(jq -r '.subdirectory_domains[0] // ""' config.json)
        
        info "Configuration loaded from config.json"
        
        # Inform user about pre-setting MySQL password
        if [ -z "$DB_ROOT_PASSWORD" ]; then
            info "Tip: You can pre-set MySQL password in config.json to skip manual entry"
        fi
    else
        info "No config.json found - will create one with your settings"
    fi
}

# Check if PostgreSQL is installed and running
check_postgresql() {
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get PostgreSQL credentials
get_postgresql_auth() {
    if check_postgresql; then
        # Check if we can connect as postgres user without password
        if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
            PG_AUTH_METHOD="sudo"
            return 0
        else
            echo -e "${CYAN}PostgreSQL Authentication Required:${NC}"
            read -sp "Enter PostgreSQL password for postgres user: " PG_PASSWORD; echo
            export PGPASSWORD="$PG_PASSWORD"
            PG_AUTH_METHOD="password"
        fi
    fi
    return 1
}

# Execute PostgreSQL command
pg_execute() {
    local query="$1"
    if [ "$PG_AUTH_METHOD" = "sudo" ]; then
        sudo -u postgres psql -t -c "$query" 2>/dev/null
    else
        PGPASSWORD="$PG_PASSWORD" psql -U postgres -h localhost -t -c "$query" 2>/dev/null
    fi
}

# Execute PostgreSQL command for specific database
pg_execute_db() {
    local db="$1"
    local query="$2"
    if [ "$PG_AUTH_METHOD" = "sudo" ]; then
        sudo -u postgres psql -d "$db" -t -c "$query" 2>/dev/null
    else
        PGPASSWORD="$PG_PASSWORD" psql -U postgres -h localhost -d "$db" -t -c "$query" 2>/dev/null
    fi
}

# Remove orphaned/redundant databases
remove_orphaned_databases() {
    echo -e "${YELLOW}Scanning for orphaned databases...${NC}"
    
    local has_mysql=false
    local has_postgresql=false
    local all_mysql_dbs=()
    local all_pg_dbs=()
    
    # Check and get MySQL databases
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        if [ -z "$DB_ROOT_PASSWORD" ]; then
            echo -e "${CYAN}MySQL Authentication Required:${NC}"
            read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
        fi
        
        # Test MySQL connection
        if mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            has_mysql=true
            MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
            # Get all MySQL databases (excluding system databases)
            all_mysql_dbs=($(mysql $MYSQL_AUTH -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys|phpmyadmin)$"))
        else
            warn "MySQL not accessible - will skip MySQL databases"
        fi
    fi
    
    # Check and get PostgreSQL databases
    if check_postgresql; then
        has_postgresql=true
        get_postgresql_auth
        # Get all PostgreSQL databases (excluding system databases)
        all_pg_dbs=($(pg_execute "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');" | grep -v "^$"))
    fi
    
    if [ "$has_mysql" = false ] && [ "$has_postgresql" = false ]; then
        error "No database servers (MySQL or PostgreSQL) are accessible"
    fi
    
    # Get all existing websites
    local existing_sites=()
    if [ -d "/var/www" ]; then
        for dir in /var/www/*/; do
            if [ -d "$dir" ]; then
                domain=$(basename "$dir")
                [ "$domain" = "html" ] && continue
                existing_sites+=("$domain")
                
                # Check for subdirectory WordPress installations
                for subdir in "$dir"*/; do
                    if [ -d "$subdir" ] && [ -f "$subdir/wp-config.php" ]; then
                        subdir_name=$(basename "$subdir")
                        existing_sites+=("$domain/$subdir_name")
                    fi
                done
            fi
        done
    fi
    
    # Find orphaned databases
    local orphaned_mysql_dbs=()
    local orphaned_mysql_users=()
    local orphaned_pg_dbs=()
    local orphaned_pg_users=()
    
    # Process MySQL databases
    for db in "${all_mysql_dbs[@]}"; do
        local is_orphaned=true
        
        # Check if database belongs to any existing website
        for site in "${existing_sites[@]}"; do
            # Convert site name to expected database name format
            local expected_db=$(echo "$site" | sed 's/\./_/g' | sed 's/-/_/g' | sed 's/\//_/g')
            
            if [[ "$db" == "$expected_db" ]]; then
                is_orphaned=false
                break
            fi
        done
        
        # Also check if database is referenced in any wp-config.php"
        if [ "$is_orphaned" = true ]; then
            for dir in /var/www/*/; do
                if [ -f "$dir/wp-config.php" ]; then
                    local config_db=$(grep "DB_NAME" "$dir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                    if [[ "$db" == "$config_db" ]]; then
                        is_orphaned=false
                        break
                    fi
                fi
                
                # Check subdirectories
                for subdir in "$dir"*/; do
                    if [ -f "$subdir/wp-config.php" ]; then
                        local config_db=$(grep "DB_NAME" "$subdir/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
                        if [[ "$db" == "$config_db" ]]; then
                            is_orphaned=false
                            break 2
                        fi
                    fi
                done
            done
        fi
        
        if [ "$is_orphaned" = true ]; then
            orphaned_mysql_dbs+=("$db")
            # Find associated user by checking common naming patterns
            local user_found=""
            local potential_user1="${db}_user"
            local base_name=$(echo "$db" | sed 's/_db$//')
            local potential_user2="${base_name}_user"

            if [ "$has_mysql" = true ] && mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user1';" 2>/dev/null | grep -q "^${potential_user1}$"; then
                user_found="$potential_user1"
            elif [ "$has_mysql" = true ] && [ "$base_name" != "$db" ] && mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user2';" 2>/dev/null | grep -q "^${potential_user2}$"; then
                user_found="$potential_user2"
            fi
            orphaned_mysql_users+=("$user_found")
        fi
    done
    
    # Process PostgreSQL databases
    for db in "${all_pg_dbs[@]}"; do
        local is_orphaned=true
        
        # Check if database belongs to any existing website
        for site in "${existing_sites[@]}"; do
            # Convert site name to expected database name format
            local expected_db=$(echo "$site" | sed 's/\./_/g' | sed 's/-/_/g' | sed 's/\//_/g')
            
            if [[ "$db" == "$expected_db" ]] || [[ "$db" == "${expected_db}_db" ]]; then
                is_orphaned=false
                break
            fi
        done
        
        # Also check if database is referenced in any config.json files
        if [ "$is_orphaned" = true ]; then
            for dir in /var/www/*/; do
                # Check for PostgreSQL config in config.json files
                for config_file in "$dir/generator/config.json" "$dir/config.json"; do
                    if [ -f "$config_file" ]; then
                        local config_db=$(jq -r '.database // ""' "$config_file" 2>/dev/null)
                        if [[ "$db" == "$config_db" ]]; then
                            is_orphaned=false
                            break 2
                        fi
                    fi
                done
            done
        fi
        
        if [ "$is_orphaned" = true ]; then
            orphaned_pg_dbs+=("$db")
            # Find associated PostgreSQL user
            local user_found=""
            local potential_user1="${db}_user"
            local base_name=$(echo "$db" | sed 's/_db$//')
            local potential_user2="${base_name}_user"
            
            if [ "$has_postgresql" = true ]; then
                # Check if user exists in PostgreSQL
                if pg_execute "SELECT usename FROM pg_user WHERE usename='$potential_user1';" | grep -q "^${potential_user1}$"; then
                    user_found="$potential_user1"
                elif [ "$base_name" != "$db" ] && pg_execute "SELECT usename FROM pg_user WHERE usename='$potential_user2';" | grep -q "^${potential_user2}$"; then
                    user_found="$potential_user2"
                fi
            fi
            orphaned_pg_users+=("$user_found")
        fi
    done
    
    # Combine all orphaned databases
    local all_orphaned_dbs=()
    local all_orphaned_users=()
    local all_orphaned_types=()
    
    # Add MySQL databases
    for i in "${!orphaned_mysql_dbs[@]}"; do
        all_orphaned_dbs+=("${orphaned_mysql_dbs[i]}")
        all_orphaned_users+=("${orphaned_mysql_users[i]}")
        all_orphaned_types+=("MySQL")
    done
    
    # Add PostgreSQL databases
    for i in "${!orphaned_pg_dbs[@]}"; do
        all_orphaned_dbs+=("${orphaned_pg_dbs[i]}")
        all_orphaned_users+=("${orphaned_pg_users[i]}")
        all_orphaned_types+=("PostgreSQL")
    done
    
    if [ ${#all_orphaned_dbs[@]} -eq 0 ]; then
        success "No orphaned databases found"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${RED}Found ${#all_orphaned_dbs[@]} orphaned database(s):${NC}"
    echo
    for i in "${!all_orphaned_dbs[@]}"; do
        echo -e "  $((i+1))) ${YELLOW}${all_orphaned_dbs[i]}${NC} (${all_orphaned_types[i]})"
        if [ -n "${all_orphaned_users[i]}" ]; then
            echo -e "      User: ${all_orphaned_users[i]}"
        fi
        
        # Show database size
        if [ "${all_orphaned_types[i]}" = "MySQL" ] && [ "$has_mysql" = true ]; then
            local db_size=$(mysql $MYSQL_AUTH -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.tables WHERE table_schema = '${all_orphaned_dbs[i]}';" 2>/dev/null | tail -n 1)
            if [ -n "$db_size" ] && [ "$db_size" != "NULL" ]; then
                echo -e "      Size: ${db_size} MB"
            fi
        elif [ "${all_orphaned_types[i]}" = "PostgreSQL" ] && [ "$has_postgresql" = true ]; then
            local db_size=$(pg_execute "SELECT pg_size_pretty(pg_database_size('${all_orphaned_dbs[i]}'));" | tr -d ' ')
            if [ -n "$db_size" ]; then
                echo -e "      Size: ${db_size}"
            fi
        fi
    done
    
    echo
    echo -e "  $((${#all_orphaned_dbs[@]}+1))) ${RED}Remove ALL orphaned databases${NC}"
    echo -e "  $((${#all_orphaned_dbs[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#all_orphaned_dbs[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#all_orphaned_dbs[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL orphaned databases and users!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; return; }
        
        for i in "${!all_orphaned_dbs[@]}"; do
            remove_single_database "${all_orphaned_dbs[i]}" "${all_orphaned_users[i]}" "${all_orphaned_types[i]}"
        done
        success "All orphaned databases removed"
        read -p "Press Enter to continue..."
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#all_orphaned_dbs[@]} ]; then
            read -p "Press Enter to continue..."
            warn "Invalid selection"
            return
        fi
        
        local selected_db="${all_orphaned_dbs[$((choice-1))]}"
        local selected_user="${all_orphaned_users[$((choice-1))]}"
        local selected_type="${all_orphaned_types[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Database: ${YELLOW}$selected_db${NC} (${selected_type})"
        if [ -n "$selected_user" ]; then
            echo -e "  User: ${YELLOW}$selected_user${NC}"
        fi
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; return; }
        
        remove_single_database "$selected_db" "$selected_user" "$selected_type"
        read -p "Press Enter to continue..."
    fi
}

# Remove single database and user
remove_single_database() {
    local db_name="$1"
    local db_user="$2"
    local db_type="${3:-MySQL}"  # Default to MySQL if not specified
    
    info "Removing $db_type database: $db_name"
    
    if [ "$db_type" = "PostgreSQL" ] && [ "$has_postgresql" = true ]; then
        if pg_execute "DROP DATABASE IF EXISTS \"$db_name\";"; then
            success "PostgreSQL database $db_name dropped"
        else
            warn "Failed to drop PostgreSQL database $db_name"
        fi
        
        if [ -n "$db_user" ]; then
            info "Removing PostgreSQL user: $db_user"
            if pg_execute "DROP USER IF EXISTS \"$db_user\";"; then
                success "PostgreSQL user $db_user dropped"
            else
                warn "Failed to drop PostgreSQL user $db_user"
            fi
        fi
    elif [ "$db_type" = "MySQL" ] && [ "$has_mysql" = true ]; then
        if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
            success "MySQL database $db_name dropped"
        else
            warn "Failed to drop MySQL database $db_name"
        fi

        if [ -n "$db_user" ]; then
            info "Removing MySQL user: $db_user"
            if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
                success "MySQL user $db_user dropped"
            else
                warn "Failed to drop MySQL user $db_user"
            fi
        fi
        
        mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi
    
    success "Database cleanup completed"
}

# Main execution
main() {
    check_root
    load_config
    remove_orphaned_databases
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"