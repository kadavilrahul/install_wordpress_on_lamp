#!/bin/bash

# Troubleshooting Tools - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; }

# Check services
check_services() {
    echo -e "${C}Service Status${N}"
    echo "=============="
    
    local services=("apache2" "mysql" "ssh" "ufw")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            ok "$service: Running"
        else
            err "$service: Not running"
        fi
    done
}

# Check ports
check_ports() {
    echo -e "${C}Port Status${N}"
    echo "==========="
    
    local ports=("80:HTTP" "443:HTTPS" "22:SSH" "3306:MySQL")
    
    for port_info in "${ports[@]}"; do
        local port=$(echo "$port_info" | cut -d: -f1)
        local name=$(echo "$port_info" | cut -d: -f2)
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ok "$name (port $port): Open"
        else
            warn "$name (port $port): Closed"
        fi
    done
}

# Check disk space
check_disk() {
    echo -e "${C}Disk Usage${N}"
    echo "=========="
    
    df -h | grep -E '^/dev/' | while read line; do
        local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        
        if [ "$usage" -gt 90 ]; then
            err "$mount: ${usage}% full ($used used, $avail available)"
        elif [ "$usage" -gt 80 ]; then
            warn "$mount: ${usage}% full ($used used, $avail available)"
        else
            ok "$mount: ${usage}% full ($used used, $avail available)"
        fi
    done
}

# Check memory
check_memory() {
    echo -e "${C}Memory Usage${N}"
    echo "============"
    
    local mem_info=$(free -m)
    local total=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local free=$(echo "$mem_info" | awk 'NR==2{print $4}')
    local usage=$((used * 100 / total))
    
    if [ "$usage" -gt 90 ]; then
        err "Memory: ${usage}% used (${used}MB/${total}MB)"
    elif [ "$usage" -gt 80 ]; then
        warn "Memory: ${usage}% used (${used}MB/${total}MB)"
    else
        ok "Memory: ${usage}% used (${used}MB/${total}MB)"
    fi
    
    # Check swap
    local swap_total=$(echo "$mem_info" | awk 'NR==3{print $2}')
    if [ "$swap_total" -eq 0 ]; then
        warn "No swap configured"
    else
        local swap_used=$(echo "$mem_info" | awk 'NR==3{print $3}')
        ok "Swap: ${swap_used}MB/${swap_total}MB used"
    fi
}

# Check logs
check_logs() {
    echo -e "${C}Recent Errors${N}"
    echo "============="
    
    # Apache errors
    if [ -f /var/log/apache2/error.log ]; then
        local apache_errors=$(tail -20 /var/log/apache2/error.log | grep -i error | wc -l)
        if [ "$apache_errors" -gt 0 ]; then
            warn "Apache: $apache_errors recent errors"
            tail -5 /var/log/apache2/error.log | grep -i error || true
        else
            ok "Apache: No recent errors"
        fi
    fi
    
    # MySQL errors
    if [ -f /var/log/mysql/error.log ]; then
        local mysql_errors=$(tail -20 /var/log/mysql/error.log | grep -i error | wc -l)
        if [ "$mysql_errors" -gt 0 ]; then
            warn "MySQL: $mysql_errors recent errors"
            tail -5 /var/log/mysql/error.log | grep -i error || true
        else
            ok "MySQL: No recent errors"
        fi
    fi
    
    # System errors
    local sys_errors=$(journalctl --since "1 hour ago" --priority=err --no-pager -q | wc -l)
    if [ "$sys_errors" -gt 0 ]; then
        warn "System: $sys_errors recent errors"
        journalctl --since "1 hour ago" --priority=err --no-pager -q | tail -3 || true
    else
        ok "System: No recent errors"
    fi
}

# Test connectivity
test_connectivity() {
    echo -e "${C}Connectivity Test${N}"
    echo "================="
    
    # Internet
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        ok "Internet: Connected"
    else
        err "Internet: No connection"
    fi
    
    # DNS
    if nslookup google.com >/dev/null 2>&1; then
        ok "DNS: Working"
    else
        err "DNS: Not working"
    fi
    
    # Local services
    if curl -s http://localhost >/dev/null 2>&1; then
        ok "Apache: Responding"
    else
        err "Apache: Not responding"
    fi
    
    if mysql -u root -proot123 -e "SELECT 1;" >/dev/null 2>&1; then
        ok "MySQL: Connected"
    else
        err "MySQL: Connection failed"
    fi
}

# Fix permissions
fix_permissions() {
    local web_dir="${1:-/var/www}"
    
    info "Fixing permissions for $web_dir..."
    
    if [ ! -d "$web_dir" ]; then
        err "Directory not found: $web_dir"
        return 1
    fi
    
    # Set ownership
    chown -R www-data:www-data "$web_dir"
    
    # Set permissions
    find "$web_dir" -type d -exec chmod 755 {} \;
    find "$web_dir" -type f -exec chmod 644 {} \;
    
    # WordPress specific
    find "$web_dir" -name "wp-config.php" -exec chmod 600 {} \; 2>/dev/null || true
    
    ok "Permissions fixed"
}

# Restart services
restart_services() {
    info "Restarting services..."
    
    local services=("apache2" "mysql")
    
    for service in "${services[@]}"; do
        if systemctl restart "$service" 2>/dev/null; then
            ok "$service restarted"
        else
            err "$service restart failed"
        fi
    done
}

# Full system check
full_check() {
    echo -e "${C}Full System Check${N}"
    echo "================="
    echo
    
    check_services
    echo
    check_ports
    echo
    check_disk
    echo
    check_memory
    echo
    check_logs
    echo
    test_connectivity
}

# Menu
menu() {
    echo -e "${C}Troubleshooting Tools${N}"
    echo "1) Full System Check"
    echo "2) Check Services"
    echo "3) Check Ports"
    echo "4) Check Disk Usage"
    echo "5) Check Memory"
    echo "6) Check Logs"
    echo "7) Test Connectivity"
    echo "8) Fix Permissions"
    echo "9) Restart Services"
    echo "0) Exit"
    read -p "Select option: " choice
    
    case "$choice" in
        1) full_check ;;
        2) check_services ;;
        3) check_ports ;;
        4) check_disk ;;
        5) check_memory ;;
        6) check_logs ;;
        7) test_connectivity ;;
        8) 
            read -p "Web directory (default: /var/www): " dir
            fix_permissions "${dir:-/var/www}"
            ;;
        9) restart_services ;;
        0) exit 0 ;;
        *) warn "Invalid option" && menu ;;
    esac
}

# Main
case "${1:-menu}" in
    check) full_check ;;
    services) check_services ;;
    ports) check_ports ;;
    disk) check_disk ;;
    memory) check_memory ;;
    logs) check_logs ;;
    connectivity) test_connectivity ;;
    permissions) fix_permissions "$2" ;;
    restart) restart_services ;;
    menu) menu ;;
    *) 
        echo "Troubleshooting Tools"
        echo "Usage: $0 [check|services|ports|disk|memory|logs|connectivity|permissions|restart|menu]"
        ;;
esac