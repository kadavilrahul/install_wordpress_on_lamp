#!/bin/bash

# MySQL Remote Access - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; exit 1; }

# Check MySQL
systemctl is-active --quiet mysql || err "MySQL not running"

# Get root password
get_root_pass() {
    if [ -f "config.json" ] && command -v jq >/dev/null; then
        jq -r '.mysql_root_password' config.json 2>/dev/null | grep -v null || echo "root123"
    else
        echo "root123"
    fi
}

ROOT_PASS=$(get_root_pass)

# Test connection
mysql -u root -p"$ROOT_PASS" -e "SELECT 1;" >/dev/null || err "Cannot connect to MySQL"

# Configure remote access
configure_remote() {
    local remote_user="${1:-remote_user}"
    local remote_pass="${2:-$(openssl rand -base64 12)}"
    local remote_host="${3:-%}"
    
    info "Configuring MySQL remote access..."
    
    # Update MySQL config
    local conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
    [ -f "$conf" ] || err "MySQL config not found"
    
    # Backup config
    cp "$conf" "${conf}.backup"
    
    # Enable remote connections
    sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$conf"
    sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address = 0.0.0.0/' "$conf"
    
    # Create remote user
    mysql -u root -p"$ROOT_PASS" <<EOF
CREATE USER IF NOT EXISTS '$remote_user'@'$remote_host' IDENTIFIED BY '$remote_pass';
GRANT ALL PRIVILEGES ON *.* TO '$remote_user'@'$remote_host' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    # Restart MySQL
    systemctl restart mysql
    
    # Configure firewall
    ufw allow 3306 2>/dev/null || true
    
    ok "Remote access configured"
    info "User: $remote_user | Pass: $remote_pass | Host: $remote_host"
    info "Connect: mysql -h $(hostname -I | awk '{print $1}') -u $remote_user -p"
}

# Remove remote access
remove_remote() {
    local remote_user="${1:-remote_user}"
    
    info "Removing remote access..."
    
    # Remove user
    mysql -u root -p"$ROOT_PASS" -e "DROP USER IF EXISTS '$remote_user'@'%';" 2>/dev/null || true
    mysql -u root -p"$ROOT_PASS" -e "FLUSH PRIVILEGES;"
    
    # Restore config
    local conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
    if [ -f "${conf}.backup" ]; then
        cp "${conf}.backup" "$conf"
        systemctl restart mysql
    fi
    
    # Remove firewall rule
    ufw delete allow 3306 2>/dev/null || true
    
    ok "Remote access removed"
}

# Show current config
show_status() {
    info "MySQL Remote Access Status"
    echo "=========================="
    
    # Check bind address
    local bind=$(grep "^bind-address" /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null | cut -d= -f2 | tr -d ' ')
    if [ "$bind" = "0.0.0.0" ]; then
        ok "Remote connections: ENABLED"
    else
        warn "Remote connections: DISABLED (bind-address: ${bind:-127.0.0.1})"
    fi
    
    # Check remote users
    local remote_users=$(mysql -u root -p"$ROOT_PASS" -e "SELECT User,Host FROM mysql.user WHERE Host != 'localhost';" 2>/dev/null | tail -n +2)
    if [ -n "$remote_users" ]; then
        ok "Remote users found:"
        echo "$remote_users"
    else
        warn "No remote users found"
    fi
    
    # Check firewall
    if ufw status 2>/dev/null | grep -q "3306"; then
        ok "Firewall: Port 3306 open"
    else
        warn "Firewall: Port 3306 not configured"
    fi
}

# Main
case "${1:-menu}" in
    enable)
        configure_remote "$2" "$3" "$4"
        ;;
    disable)
        remove_remote "$2"
        ;;
    status)
        show_status
        ;;
    *)
        echo "MySQL Remote Access Manager"
        echo "Usage: $0 [enable|disable|status]"
        echo ""
        echo "Examples:"
        echo "  $0 enable                    # Enable with defaults"
        echo "  $0 enable myuser mypass      # Custom user/pass"
        echo "  $0 disable                   # Disable remote access"
        echo "  $0 status                    # Show current status"
        ;;
esac