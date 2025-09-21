#!/bin/bash

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# Utility functions
info() { echo -e "${BLUE}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; }

# Source core WSL functions
source "$(dirname "${BASH_SOURCE[0]}")/wsl_functions.sh"

# Get WSL IP
get_wsl_ip() {
    hostname -I | awk '{print $1}'
}

# Detect websites
detect_websites() {
    local sites=()
    if [[ -d "/var/www" ]]; then
        for site_dir in /var/www/*/; do
            if [[ -d "$site_dir" && "$site_dir" != "/var/www/html/" ]]; then
                local site_name=$(basename "$site_dir")
                sites+=("$site_name")
            fi
        done
    fi
    
    # Also check Apache virtual hosts
    if [[ -d "/etc/apache2/sites-available" ]]; then
        for conf_file in /etc/apache2/sites-available/*.conf; do
            if [[ -f "$conf_file" && "$conf_file" != "/etc/apache2/sites-available/000-default.conf" && "$conf_file" != "/etc/apache2/sites-available/default-ssl.conf" ]]; then
                local site_name=$(basename "$conf_file" .conf)
                if [[ ! " ${sites[@]} " =~ " ${site_name} " ]]; then
                    sites+=("$site_name")
                fi
            fi
        done
    fi
    
    echo "${sites[@]}"
}

# Show header
show_header() {
    clear
    echo -e "${CYAN}"
    echo "============================================================================="
    echo "                           WSL Hosts File Helper"
    echo "                    Generate Windows Hosts File Entries"
    echo "============================================================================="
    echo -e "${NC}"
}

# Generate hosts entries
generate_hosts_entries() {
    local wsl_ip=$(get_wsl_ip)
    local websites=($(detect_websites))
    
    echo -e "${CYAN}Current WSL IP Address: ${YELLOW}$wsl_ip${NC}"
    echo
    
    if [[ ${#websites[@]} -eq 0 ]]; then
        warn "No websites detected in /var/www/"
        echo
        echo -e "${YELLOW}Manual entry format:${NC}"
        echo "$wsl_ip your-domain.com www.your-domain.com"
        return
    fi
    
    echo -e "${GREEN}Detected websites:${NC}"
    for site in "${websites[@]}"; do
        echo "  • $site"
    done
    echo
    
    echo -e "${CYAN}============================================================================="
    echo "                    Copy these lines to Windows hosts file:"
    echo -e "=============================================================================${NC}"
    echo
    
    for site in "${websites[@]}"; do
        echo -e "${GREEN}$wsl_ip $site www.$site${NC}"
    done
    
    echo
    echo -e "${CYAN}=============================================================================${NC}"
}

# Show instructions
show_instructions() {
    echo -e "${YELLOW}How to update Windows hosts file:${NC}"
    echo
    echo -e "${CYAN}Method 1 - PowerShell (Recommended):${NC}"
    echo "1. Press Win+X and select 'Windows Terminal (Admin)'"
    echo "2. Run this command for each domain:"
    echo '   Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n172.x.x.x domain.com www.domain.com"'
    echo
    echo -e "${CYAN}Method 2 - Notepad:${NC}"
    echo "1. Right-click Notepad → 'Run as administrator'"
    echo '2. Open: C:\Windows\System32\drivers\etc\hosts'
    echo "3. Add the lines at the bottom"
    echo "4. Save the file"
    echo
    echo -e "${CYAN}Method 3 - Command Prompt:${NC}"
    echo "1. Open Command Prompt as Administrator"
    echo '2. echo 172.x.x.x domain.com www.domain.com >> C:\Windows\System32\drivers\etc\hosts'
    echo
    echo -e "${YELLOW}After updating:${NC}"
    echo "• Restart your browser"
    echo "• Flush DNS cache: ipconfig /flushdns"
    echo "• Access your sites at: https://domain.com"
    echo
}

# Check if domain resolves
check_domain_resolution() {
    local domain="$1"
    local wsl_ip="$2"
    
    info "Testing domain resolution for: $domain"
    
    if ping -c 1 "$domain" >/dev/null 2>&1; then
        local resolved_ip=$(ping -c 1 "$domain" | grep -oP '(?<=\()[0-9.]+(?=\))')
        if [[ "$resolved_ip" == "$wsl_ip" ]]; then
            success "$domain resolves to WSL IP: $resolved_ip"
        else
            warn "$domain resolves to: $resolved_ip (expected: $wsl_ip)"
            echo "This means the hosts file entry may not be active yet."
        fi
    else
        error "$domain does not resolve. Check your hosts file entry."
    fi
}

# Interactive domain tester
test_domains() {
    local wsl_ip=$(get_wsl_ip)
    local websites=($(detect_websites))
    
    if [[ ${#websites[@]} -eq 0 ]]; then
        warn "No websites detected. Enter a domain manually:"
        read -p "Domain to test: " domain
        if [[ -n "$domain" ]]; then
            check_domain_resolution "$domain" "$wsl_ip"
        fi
        return
    fi
    
    echo -e "${CYAN}Select domain to test:${NC}"
    for i in "${!websites[@]}"; do
        echo "$((i+1)). ${websites[i]}"
    done
    echo "0. Enter custom domain"
    echo
    
    read -p "Enter choice: " choice
    
    if [[ "$choice" == "0" ]]; then
        read -p "Enter domain: " domain
        if [[ -n "$domain" ]]; then
            check_domain_resolution "$domain" "$wsl_ip"
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#websites[@]}" ]]; then
        local selected_domain="${websites[$((choice-1))]}"
        check_domain_resolution "$selected_domain" "$wsl_ip"
    else
        error "Invalid choice"
    fi
}

# Main menu
main_menu() {
    while true; do
        show_header
        
        echo -e "${CYAN}Choose an action:${NC}"
        echo "1. Generate hosts file entries"
        echo "2. Show update instructions"
        echo "3. Test domain resolution"
        echo "4. Show current WSL IP"
        echo "0. Exit"
        echo
        
        read -p "Enter choice (0-4): " choice
        
        case $choice in
            1)
                generate_hosts_entries
                read -p "Press Enter to continue..."
                ;;
            2)
                show_instructions
                read -p "Press Enter to continue..."
                ;;
            3)
                test_domains
                read -p "Press Enter to continue..."
                ;;
            4)
                local wsl_ip=$(get_wsl_ip)
                info "Current WSL IP: $wsl_ip"
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                error "Invalid choice. Please select 0-4."
                sleep 1
                ;;
        esac
    done
}

# Check if we should run in WSL mode (allow override for testing)
if ! is_wsl_mode; then
    error "This script is designed for WSL environments. Use --mode wsl to force WSL mode."
    exit 1
fi

# Start the helper
main_menu