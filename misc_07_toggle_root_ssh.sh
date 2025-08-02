#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root (use sudo)"
        exit 1
    fi
}

# SSH Security Management
function toggle_root_ssh() {
    echo "SSH Root Access Management"
    echo "=========================="
    echo "  1) Disable root SSH login - Prevent root user from accessing server via SSH"
    echo "  2) Enable root SSH login - Allow root user to access server via SSH (less secure)"
    echo "  3) Show current status - Display current SSH root login configuration"
    echo "  0) Back to menu - Return to main miscellaneous menu"
    read -p "Choose (0-3): " choice
    
    case $choice in
        1)
            # Disable root SSH
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            systemctl restart sshd
            success "Root SSH login disabled"
            ;;
        2)
            # Enable root SSH
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
            systemctl restart sshd
            warning "Root SSH login enabled - this is less secure!"
            ;;
        3)
            # Show current status
            echo "Current SSH configuration:"
            grep -E "^#*PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin not explicitly set (default: prohibit-password)"
            ;;
        0)
            return
            ;;
        *)
            echo "Invalid option"
            sleep 1
            toggle_root_ssh
            return
            ;;
    esac
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    toggle_root_ssh
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"