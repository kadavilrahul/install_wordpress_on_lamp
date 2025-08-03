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

# Remove orphaned/redundant databases
remove_orphaned_databases() {
    echo -e "${YELLOW}Scanning for orphaned databases...${NC}"
    
    # Get MySQL credentials
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        echo -e "${CYAN}MySQL Authentication Required:${NC}"
        read -sp "Enter MySQL root password: " DB_ROOT_PASSWORD; echo
    fi
    
    # Test MySQL connection
    if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        error "Invalid MySQL password or MySQL not accessible"
    fi
    MYSQL_AUTH="-u root -p$DB_ROOT_PASSWORD"
    
    # Get all databases (excluding system databases)
    local all_dbs=($(mysql $MYSQL_AUTH -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys|phpmyadmin)$"))
    
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
    local orphaned_dbs=()
    local orphaned_users=()
    
    for db in "${all_dbs[@]}"; do
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
            orphaned_dbs+=("$db")
            # Find associated user (common pattern: dbname_user)
            # Find associated user by checking common naming patterns
            local user_found=""
            local potential_user1="${db}_user"
            local base_name=$(echo "$db" | sed 's/_db$//')
            local potential_user2="${base_name}_user"

            if mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user1';" 2>/dev/null | grep -q "^${potential_user1}$"; then
                user_found="$potential_user1"
            elif [ "$base_name" != "$db" ] && mysql $MYSQL_AUTH -e "SELECT User FROM mysql.user WHERE User='$potential_user2';" 2>/dev/null | grep -q "^${potential_user2}$"; then
                user_found="$potential_user2"
            fi
            orphaned_users+=("$user_found")
        fi
    done
    
    if [ ${#orphaned_dbs[@]} -eq 0 ]; then
        success "No orphaned databases found"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${RED}Found ${#orphaned_dbs[@]} orphaned database(s):${NC}"
    echo
    for i in "${!orphaned_dbs[@]}"; do
        echo -e "  $((i+1))) ${YELLOW}${orphaned_dbs[i]}${NC}"
        if [ -n "${orphaned_users[i]}" ]; then
            echo -e "      User: ${orphaned_users[i]}"
        fi
        
        # Show database size
        local db_size=$(mysql $MYSQL_AUTH -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.tables WHERE table_schema = '${orphaned_dbs[i]}';" 2>/dev/null | tail -n 1)
        if [ -n "$db_size" ] && [ "$db_size" != "NULL" ]; then
            echo -e "      Size: ${db_size} MB"
        fi
    done
    
    echo
    echo -e "  $((${#orphaned_dbs[@]}+1))) ${RED}Remove ALL orphaned databases${NC}"
    echo -e "  $((${#orphaned_dbs[@]}+2))) ${CYAN}Back to main menu${NC}"
    echo
    
    read -p "$(echo -e "${CYAN}Select option: ${NC}")" choice
    [ "$choice" = "$((${#orphaned_dbs[@]}+2))" ] && return
    
    if [ "$choice" = "$((${#orphaned_dbs[@]}+1))" ]; then
        echo -e "${RED}WARNING: This will remove ALL orphaned databases and users!${NC}"
        read -p "Type 'DELETE ALL' to confirm: " confirm
        [ "$confirm" != "DELETE ALL" ] && { warn "Cancelled"; return; }
        
        for i in "${!orphaned_dbs[@]}"; do
            remove_single_database "${orphaned_dbs[i]}" "${orphaned_users[i]}"
        done
        read -p "Press Enter to continue..."
        success "All orphaned databases removed"
    else
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#orphaned_dbs[@]} ]; then
            read -p "Press Enter to continue..."
            warn "Invalid selection"
            return
        fi
        
        local selected_db="${orphaned_dbs[$((choice-1))]}"
        local selected_user="${orphaned_users[$((choice-1))]}"
        
        echo -e "${RED}WARNING: This will permanently delete:${NC}"
        echo -e "  Database: ${YELLOW}$selected_db${NC}"
        if [ -n "$selected_user" ]; then
            echo -e "  User: ${YELLOW}$selected_user${NC}"
        fi
        echo
        read -p "Type 'DELETE' to confirm removal: " confirm
        [ "$confirm" != "DELETE" ] && { warn "Cancelled"; return; }
        
        read -p "Press Enter to continue..."
        remove_single_database "$selected_db" "$selected_user"
    fi
}

# Remove single database and user
remove_single_database() {
    local db_name="$1"
    local db_user="$2"
    
    info "Removing database: $db_name"
    
    if mysql $MYSQL_AUTH -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
        success "Database $db_name dropped"
    else
        warn "Failed to drop database $db_name"
    fi

    if [ -n "$db_user" ]; then
        info "Removing user: $db_user"
        if mysql $MYSQL_AUTH -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null; then
            success "User $db_user dropped"
        else
            warn "Failed to drop user $db_user"
        fi
    fi
    
    mysql $MYSQL_AUTH -e "FLUSH PRIVILEGES;" 2>/dev/null || true
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