#!/bin/bash

# Miscellaneous Tools - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; exit 1; }

# Check root
[[ $EUID -ne 0 ]] && err "Run as root: sudo $0"

# Install phpMyAdmin
install_phpmyadmin() {
    local web_dir="${1:-/var/www}"
    
    info "Installing phpMyAdmin..."
    
    export DEBIAN_FRONTEND=noninteractive
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    
    apt update -y
    apt install -y phpmyadmin
    
    # Create symlink
    ln -sf /usr/share/phpmyadmin "$web_dir/phpmyadmin"
    
    # Enable Apache config
    a2enconf phpmyadmin
    systemctl restart apache2
    
    ok "phpMyAdmin installed at: http://your-domain/phpmyadmin"
}

# Install system utilities
install_utilities() {
    info "Installing system utilities..."
    
    apt update -y
    apt install -y htop curl wget unzip git nano vim tree ncdu fail2ban ufw
    
    # Configure firewall
    ufw --force enable
    ufw allow ssh
    ufw allow 'Apache Full'
    
    # Configure fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    ok "System utilities installed"
}

# Install Node.js
install_nodejs() {
    local version="${1:-18}"
    
    info "Installing Node.js $version..."
    
    curl -fsSL https://deb.nodesource.com/setup_${version}.x | bash -
    apt install -y nodejs
    
    # Install common packages
    npm install -g pm2 yarn
    
    ok "Node.js $(node --version) installed"
}

# Install Docker
install_docker() {
    info "Installing Docker..."
    
    # Remove old versions
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install dependencies
    apt update -y
    apt install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    # Install Docker
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group
    usermod -aG docker $SUDO_USER 2>/dev/null || true
    
    ok "Docker installed"
}

# Install Composer
install_composer() {
    info "Installing Composer..."
    
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    
    ok "Composer installed"
}

# Configure swap
setup_swap() {
    local size="${1:-2G}"
    
    info "Setting up ${size} swap file..."
    
    # Check if swap already exists
    if swapon --show | grep -q "/swapfile"; then
        warn "Swap file already exists"
        return
    fi
    
    # Create swap file
    fallocate -l "$size" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make permanent
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # Configure swappiness
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    
    ok "Swap file created: $size"
}

# System cleanup
cleanup_system() {
    info "Cleaning up system..."
    
    # Clean package cache
    apt autoremove -y
    apt autoclean
    
    # Clean logs
    journalctl --vacuum-time=7d
    
    # Clean temp files
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    
    ok "System cleaned up"
}

# Show system info
show_info() {
    echo -e "${C}System Information${N}"
    echo "=================="
    
    # OS info
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    
    # Hardware info
    echo "CPU: $(nproc) cores"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Disk: $(df -h / | awk 'NR==2 {print $4 " free of " $2}')"
    
    # Services
    echo ""
    echo "Services:"
    systemctl is-active apache2 >/dev/null && echo "✓ Apache2" || echo "✗ Apache2"
    systemctl is-active mysql >/dev/null && echo "✓ MySQL" || echo "✗ MySQL"
    systemctl is-active docker >/dev/null && echo "✓ Docker" || echo "✗ Docker"
    
    # Network
    echo ""
    echo "Network:"
    echo "IP: $(hostname -I | awk '{print $1}')"
    echo "Hostname: $(hostname)"
}

# Menu
menu() {
    echo -e "${C}Miscellaneous Tools${N}"
    echo "1) Install phpMyAdmin"
    echo "2) Install System Utilities"
    echo "3) Install Node.js"
    echo "4) Install Docker"
    echo "5) Install Composer"
    echo "6) Setup Swap File"
    echo "7) System Cleanup"
    echo "8) Show System Info"
    echo "0) Exit"
    read -p "Select option: " choice
    
    case "$choice" in
        1) install_phpmyadmin ;;
        2) install_utilities ;;
        3) 
            read -p "Node.js version (default: 18): " version
            install_nodejs "${version:-18}"
            ;;
        4) install_docker ;;
        5) install_composer ;;
        6)
            read -p "Swap size (default: 2G): " size
            setup_swap "${size:-2G}"
            ;;
        7) cleanup_system ;;
        8) show_info ;;
        0) exit 0 ;;
        *) warn "Invalid option" && menu ;;
    esac
}

# Main
case "${1:-menu}" in
    phpmyadmin) install_phpmyadmin "$2" ;;
    utilities) install_utilities ;;
    nodejs) install_nodejs "$2" ;;
    docker) install_docker ;;
    composer) install_composer ;;
    swap) setup_swap "$2" ;;
    cleanup) cleanup_system ;;
    info) show_info ;;
    menu) menu ;;
    *) 
        echo "Miscellaneous Tools"
        echo "Usage: $0 [phpmyadmin|utilities|nodejs|docker|composer|swap|cleanup|info|menu]"
        ;;
esac