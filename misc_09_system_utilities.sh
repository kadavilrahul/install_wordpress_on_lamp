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

# System utilities configuration
system_utilities() {
    echo "Configuring system utilities..."
    
    # Update package lists
    apt update -y
    
    # Install common utilities
    apt install -y htop curl wget unzip git nano vim
    
    success "System utilities configuration completed"
    read -p "Press Enter to continue..."
}

# Main execution
main() {
    check_root
    echo "System Utilities Configuration"
    echo "============================="
    system_utilities
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"