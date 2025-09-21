#!/bin/bash

# WSL SSL Functions
# This file contains WSL-specific SSL setup functions

# Source core WSL functions
source "$(dirname "${BASH_SOURCE[0]}")/wsl_functions.sh"

# WSL-specific SSL setup function
setup_wsl_ssl() {
    local domain="$1"
    local wsl_ip="$2"
    local web_root="$3"
    
    info "Setting up self-signed SSL certificate for WSL environment"
    
    # Create SSL directories
    mkdir -p /etc/ssl/private /etc/ssl/certs
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "/etc/ssl/private/$domain.key" \
        -out "/etc/ssl/certs/$domain.crt" \
        -subj "/C=US/ST=Local/L=WSL/O=Development/CN=$domain"
    
    # Create SSL virtual host
    cat > "/etc/apache2/sites-available/$domain-ssl.conf" << EOF
<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $web_root
    
    <Directory $web_root>
        AllowOverride All
        Require all granted
    </Directory>
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    
    ErrorLog \${APACHE_LOG_DIR}/error_${domain}_ssl.log
    CustomLog \${APACHE_LOG_DIR}/access_${domain}_ssl.log combined
</VirtualHost>

# Also add localhost SSL support
<VirtualHost *:443>
    ServerName localhost
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    
    ErrorLog \${APACHE_LOG_DIR}/error_localhost_ssl.log
    CustomLog \${APACHE_LOG_DIR}/access_localhost_ssl.log combined
</VirtualHost>
EOF
    
    # Enable SSL site
    a2ensite "$domain-ssl.conf"
    systemctl reload apache2
    
    success "Self-signed SSL certificate created for $domain"
    export HTTPS_URL="https://$domain"
}

# Show WSL-specific hosts file information
show_wsl_hosts_info() {
    local domain="$1"
    local wsl_ip="$2"
    
    echo -e "${CYAN}============================================================================="
    echo "                           WSL Configuration Required"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}Your WordPress site is ready, but you need to update Windows hosts file:${NC}"
    echo
    echo -e "${GREEN}Add this line to Windows hosts file:${NC}"
    echo -e "${YELLOW}$wsl_ip $domain www.$domain${NC}"
    echo
    echo -e "${CYAN}Windows hosts file location:${NC}"
    echo -e "${YELLOW}C:\\Windows\\System32\\drivers\\etc\\hosts${NC}"
    echo
    echo -e "${CYAN}Quick PowerShell command (run as Admin):${NC}"
    echo "Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value \"\`n$wsl_ip $domain www.$domain\""
    echo
    echo -e "${CYAN}Then access your site at:${NC}"
    echo -e "${GREEN}• HTTP:  http://$domain${NC}"
    echo -e "${GREEN}• HTTPS: https://$domain ${YELLOW}(accept security warning for self-signed cert)${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
}