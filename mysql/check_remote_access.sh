#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Utility functions
log() { echo "[$1] $2" | tee -a "/var/log/mysql_remote_check_$(date +%Y%m%d_%H%M%S).log"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }

# Header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                    MySQL Remote Access Checker"
    echo "============================================================================="
    echo -e "${NC}"
    echo
}

# Check if MySQL is running
check_mysql_service() {
    info "Checking MySQL service status..."
    if systemctl is-active --quiet mysql; then
        success "MySQL service is running"
        return 0
    elif systemctl is-active --quiet mariadb; then
        success "MariaDB service is running"
        return 0
    else
        error "MySQL/MariaDB service is not running"
        return 1
    fi
}

# Check MySQL listening ports
check_mysql_ports() {
    info "Checking MySQL listening ports..."
    local ports=$(netstat -tlnp 2>/dev/null | grep -E ':(3306|3307)' | awk '{print $4}')
    
    if [[ -n "$ports" ]]; then
        success "MySQL is listening on the following addresses:"
        echo "$ports" | while read -r port; do
            if [[ "$port" == "127.0.0.1:"* ]]; then
                warn "  $port (localhost only - not accessible remotely)"
            elif [[ "$port" == "0.0.0.0:"* ]]; then
                success "  $port (accessible from all interfaces)"
            else
                info "  $port"
            fi
        done
    else
        error "MySQL is not listening on standard ports (3306/3307)"
        return 1
    fi
}

# Check MySQL bind address configuration
check_bind_address() {
    info "Checking MySQL bind address configuration..."
    
    local config_files=("/etc/mysql/mysql.conf.d/mysqld.cnf" "/etc/mysql/my.cnf" "/etc/my.cnf")
    local found_config=false
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            found_config=true
            local bind_address=$(grep -E "^bind-address" "$config_file" 2>/dev/null | head -1)
            
            if [[ -n "$bind_address" ]]; then
                info "Found in $config_file: $bind_address"
                if echo "$bind_address" | grep -q "127.0.0.1"; then
                    warn "MySQL is configured to bind only to localhost (not accessible remotely)"
                elif echo "$bind_address" | grep -q "0.0.0.0"; then
                    success "MySQL is configured to bind to all interfaces (accessible remotely)"
                fi
            fi
        fi
    done
    
    if [[ "$found_config" == false ]]; then
        warn "Could not find MySQL configuration files"
    fi
}

# Check firewall status
check_firewall() {
    info "Checking firewall configuration..."
    
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null)
        if echo "$ufw_status" | grep -q "Status: active"; then
            info "UFW firewall is active"
            if echo "$ufw_status" | grep -q "3306"; then
                success "Port 3306 is allowed through UFW firewall"
            else
                warn "Port 3306 is NOT allowed through UFW firewall"
            fi
        else
            info "UFW firewall is inactive"
        fi
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L INPUT -n 2>/dev/null | grep -E ":3306|dpt:3306")
        if [[ -n "$iptables_rules" ]]; then
            success "Found iptables rules for port 3306:"
            echo "$iptables_rules"
        else
            warn "No iptables rules found for port 3306"
        fi
    fi
}

# Check MySQL users with remote access
check_remote_users() {
    info "Checking MySQL users with remote access permissions..."
    
    # Try to connect to MySQL and check for remote users
    local mysql_cmd=""
    if command -v mysql >/dev/null 2>&1; then
        mysql_cmd="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
        mysql_cmd="mariadb"
    else
        warn "MySQL/MariaDB client not found"
        return 1
    fi
    
    echo -n "Enter MySQL root password (or press Enter if no password): "
    read -s mysql_password
    echo
    
    local mysql_connect_cmd="$mysql_cmd -u root"
    if [[ -n "$mysql_password" ]]; then
        mysql_connect_cmd="$mysql_cmd -u root -p$mysql_password"
    fi
    
    local remote_users=$($mysql_connect_cmd -e "SELECT User, Host FROM mysql.user WHERE Host != 'localhost' AND Host != '127.0.0.1' AND Host != '::1';" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        if [[ -n "$remote_users" ]] && [[ $(echo "$remote_users" | wc -l) -gt 1 ]]; then
            success "Found MySQL users with remote access:"
            echo "$remote_users"
        else
            warn "No MySQL users found with remote access permissions"
            info "All users are restricted to localhost connections only"
        fi
    else
        error "Could not connect to MySQL to check user permissions"
        info "Please verify MySQL credentials and try again"
    fi
}

# Test remote connection
test_remote_connection() {
    info "Testing remote connection capability..."
    
    # Get server's external IP
    local external_ip=""
    if command -v curl >/dev/null 2>&1; then
        external_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    fi
    
    if [[ -n "$external_ip" ]]; then
        info "Server's external IP address: $external_ip"
        info "To test remote connection from another machine, use:"
        echo -e "${CYAN}mysql -h $external_ip -u <username> -p${NC}"
    else
        warn "Could not determine server's external IP address"
    fi
    
    # Check if we can connect from localhost using the external interface
    local local_ip=$(hostname -I | awk '{print $1}')
    if [[ -n "$local_ip" ]]; then
        info "Server's local network IP: $local_ip"
        info "To test from local network, use:"
        echo -e "${CYAN}mysql -h $local_ip -u <username> -p${NC}"
    fi
}

# Provide recommendations
show_recommendations() {
    echo
    echo -e "${YELLOW}Recommendations for enabling remote MySQL access:${NC}"
    echo "1. Configure bind address to 0.0.0.0 in MySQL configuration"
    echo "2. Create MySQL users with remote host permissions (e.g., user@'%' or user@'192.168.1.%')"
    echo "3. Open port 3306 in firewall (ufw allow 3306 or iptables rules)"
    echo "4. Restart MySQL service after configuration changes"
    echo "5. Test connection from remote machine"
    echo
    echo -e "${RED}Security Warning:${NC} Only allow remote access if absolutely necessary."
    echo "Consider using SSH tunneling for secure remote database access."
}

# Main function
main() {
    show_header
    
    # Perform all checks
    check_mysql_service || { error "Cannot proceed - MySQL service is not running"; exit 1; }
    echo
    check_mysql_ports
    echo
    check_bind_address
    echo
    check_firewall
    echo
    check_remote_users
    echo
    test_remote_connection
    echo
    show_recommendations
    
    echo
    info "MySQL remote access check completed"
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read
}

# Run main function if script is executed directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"