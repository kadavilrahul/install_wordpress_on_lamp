#!/bin/bash

# WSL Completion Messages
# This file contains WSL-specific completion and instruction functions

# Source core WSL functions
source "$(dirname "${BASH_SOURCE[0]}")/wsl_functions.sh"

# Show WSL completion message for WordPress installation
show_wsl_completion_message() {
    local domain="$1"
    local wsl_ip="$2"
    
    echo -e "${CYAN}============================================================================="
    echo "                         🎉 WordPress Installation Complete! 🎉"
    echo -e "=============================================================================${NC}"
    echo -e "${GREEN}Your WordPress site is ready!${NC}"
    echo
    echo -e "${YELLOW}⚠️  WSL Environment Detected - Additional Setup Required:${NC}"
    echo
    echo -e "${CYAN}1. Add this line to Windows hosts file:${NC}"
    echo -e "${GREEN}   $wsl_ip $domain www.$domain${NC}"
    echo
    echo -e "${CYAN}2. Windows hosts file location:${NC}"
    echo -e "${YELLOW}   C:\\Windows\\System32\\drivers\\etc\\hosts${NC}"
    echo
    echo -e "${CYAN}3. Quick PowerShell command (run as Admin):${NC}"
    echo "   Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value \"\`n$wsl_ip $domain www.$domain\""
    echo
    echo -e "${CYAN}4. Access your WordPress site:${NC}"
    echo -e "${GREEN}   • Admin: https://$domain/wp-admin${NC}"
    echo -e "${GREEN}   • Site:  https://$domain${NC}"
    echo -e "${YELLOW}   (Accept security warning for self-signed certificate)${NC}"
    echo
    echo -e "${CYAN}5. Alternative access (no hosts file needed):${NC}"
    echo -e "${GREEN}   • https://localhost/wp/ ${YELLOW}(if symlink exists)${NC}"
    echo
    echo -e "${CYAN}Use the WSL Hosts Helper for more options:${NC}"
    echo -e "${YELLOW}   ./main.sh hosts${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
}

# Show Windows hosts file update instructions
update_windows_hosts() {
    local domain="$1"
    local wsl_ip="$2"
    
    info "WSL detected. Domain $domain should be accessed via IP: $wsl_ip"
    warn "To access your site, add this line to Windows hosts file:"
    echo -e "${YELLOW}$wsl_ip $domain www.$domain${NC}"
    echo -e "${CYAN}Windows hosts file location: C:\\Windows\\System32\\drivers\\etc\\hosts${NC}"
    echo -e "${CYAN}Run Notepad as Administrator to edit the hosts file${NC}"
    
    if confirm "Would you like to see instructions for updating Windows hosts file?"; then
        show_hosts_instructions "$domain" "$wsl_ip"
    fi
}

# Detailed hosts file instructions
show_hosts_instructions() {
    local domain="$1"
    local wsl_ip="$2"
    
    echo -e "${CYAN}============================================================================="
    echo "                     Windows Hosts File Update Instructions"
    echo -e "=============================================================================${NC}"
    echo -e "${YELLOW}1. Press Win+X and select 'Windows Terminal (Admin)' or 'PowerShell (Admin)'${NC}"
    echo -e "${YELLOW}2. Run one of these commands:${NC}"
    echo
    echo -e "${GREEN}   PowerShell method:${NC}"
    echo "   Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value \"\`n$wsl_ip $domain www.$domain\""
    echo
    echo -e "${GREEN}   Notepad method:${NC}"
    echo "   notepad C:\\Windows\\System32\\drivers\\etc\\hosts"
    echo "   Add this line at the bottom: $wsl_ip $domain www.$domain"
    echo
    echo -e "${YELLOW}3. Save the file and restart your browser${NC}"
    echo -e "${YELLOW}4. Access your site at: https://$domain${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
}