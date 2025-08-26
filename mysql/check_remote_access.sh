#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Utility functions
log() { echo "[$1] $2" >> "/var/log/mysql_remote_check_$(date +%Y%m%d_%H%M%S).log"; }
error() { log "ERROR" "$1"; echo -e "${RED}✗ $1${NC}" >&2; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}• $1${NC}"; }
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
    info "Checking ports..."
    local ports=$(netstat -tlnp 2>/dev/null | grep -E ':(3306|3307)' | awk '{print $4}')
    
    if [[ -n "$ports" ]]; then
        echo "$ports" | while read -r port; do
            if [[ "$port" == "127.0.0.1:"* ]]; then
                warn "$port (localhost only)"
            elif [[ "$port" == "0.0.0.0:"* ]]; then
                success "$port (all interfaces)"
            else
                info "$port"
            fi
        done
    else
        error "MySQL not listening on ports 3306/3307"
        return 1
    fi
}

# Check MySQL bind address configuration
check_bind_address() {
    info "Checking bind address..."
    
    local config_files=("/etc/mysql/mysql.conf.d/mysqld.cnf" "/etc/mysql/my.cnf" "/etc/my.cnf")
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            local bind_address=$(grep -E "^bind-address" "$config_file" 2>/dev/null | head -1)
            
            if [[ -n "$bind_address" ]]; then
                if echo "$bind_address" | grep -q "127.0.0.1"; then
                    warn "bind-address = 127.0.0.1 (localhost only)"
                elif echo "$bind_address" | grep -q "0.0.0.0"; then
                    success "bind-address = 0.0.0.0 (all interfaces)"
                fi
                return
            fi
        fi
    done
    
    warn "No bind-address configuration found"
}

# Check firewall status
check_firewall() {
    info "Checking firewall..."
    
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null)
        if echo "$ufw_status" | grep -q "Status: active"; then
            if echo "$ufw_status" | grep -q "3306"; then
                success "UFW: Port 3306 allowed"
            else
                warn "UFW: Port 3306 blocked"
            fi
        else
            info "UFW: Inactive"
        fi
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L INPUT -n 2>/dev/null | grep -E ":3306|dpt:3306")
        if [[ -n "$iptables_rules" ]]; then
            success "iptables: Port 3306 rules found"
        else
            warn "iptables: No port 3306 rules"
        fi
    fi
}

# Check MySQL users with remote access
check_remote_users() {
    info "Checking remote users..."
    
    local mysql_cmd=""
    if command -v mysql >/dev/null 2>&1; then
        mysql_cmd="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
        mysql_cmd="mariadb"
    else
        warn "MySQL client not found"
        return 1
    fi
    
    echo -n "MySQL root password (Enter for none): "
    read -s mysql_password
    echo
    
    local mysql_connect_cmd="$mysql_cmd -u root"
    if [[ -n "$mysql_password" ]]; then
        mysql_connect_cmd="$mysql_cmd -u root -p$mysql_password"
    fi
    
    local remote_users=$($mysql_connect_cmd -e "SELECT User, Host FROM mysql.user WHERE Host != 'localhost' AND Host != '127.0.0.1' AND Host != '::1';" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        if [[ -n "$remote_users" ]] && [[ $(echo "$remote_users" | wc -l) -gt 1 ]]; then
            success "Remote users found:"
            echo "$remote_users"
        else
            warn "No remote users configured"
        fi
    else
        error "Cannot connect to MySQL - check credentials"
    fi
}

# Test remote connection
test_remote_connection() {
    info "Testing remote connection capability..."
    
    # Get server's external IPv4 address only
    local external_ip=""
    if command -v curl >/dev/null 2>&1; then
        external_ip=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null)
    fi
    
    if [[ -n "$external_ip" ]] && [[ "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        success "External IP: $external_ip"
        echo -e "${CYAN}mysql -h $external_ip -u username -p${NC}"
    else
        warn "Could not get external IP"
    fi
    
    # Get local IPv4 address only
    local local_ip=$(hostname -I | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | head -1)
    if [[ -n "$local_ip" ]]; then
        success "Local IP: $local_ip" 
        echo -e "${CYAN}mysql -h $local_ip -u username -p${NC}"
    fi
}

# Provide recommendations
show_recommendations() {
    echo
    echo -e "${YELLOW}Quick Setup:${NC}"
    echo "1. Set bind-address = 0.0.0.0 in MySQL config"
    echo "2. Create user@'%' for remote access"
    echo "3. Open firewall: ufw allow 3306"
    echo "4. Restart MySQL service"
    echo
    echo -e "${RED}Security:${NC} Use SSH tunneling when possible"
}

# Main function
main() {
    show_header
    
    # Perform all checks
    check_mysql_service || { error "MySQL service not running"; exit 1; }
    check_mysql_ports
    check_bind_address  
    check_firewall
    check_remote_users
    test_remote_connection
    show_recommendations
    
    echo
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read
}

# Run main function if script is executed directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"