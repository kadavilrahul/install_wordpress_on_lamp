#!/bin/bash

# WSL Core Functions
# This file contains core WSL detection and utility functions

# WSL detection function
detect_wsl() {
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        return 0
    fi
    return 1
}

# Get WSL IP address
get_wsl_ip() {
    hostname -I | awk '{print $1}'
}

# Check if we're running in WSL mode (either forced or auto-detected)
is_wsl_mode() {
    if [[ "$ENVIRONMENT_MODE" == "wsl" ]]; then
        return 0
    elif [[ "$ENVIRONMENT_MODE" == "server" ]]; then
        return 1
    else
        # Auto-detect if not explicitly set
        detect_wsl
    fi
}

# Set environment mode based on user choice or auto-detection
set_environment_mode() {
    local mode="$1"
    
    case "$mode" in
        "wsl"|"server"|"auto")
            export ENVIRONMENT_MODE="$mode"
            ;;
        *)
            # Default to auto-detection
            export ENVIRONMENT_MODE="auto"
            ;;
    esac
}

# Get current environment mode
get_environment_mode() {
    echo "${ENVIRONMENT_MODE:-auto}"
}

# Show environment status
show_environment_status() {
    local current_mode=$(get_environment_mode)
    local is_wsl_detected=""
    
    if detect_wsl; then
        is_wsl_detected="Yes"
    else
        is_wsl_detected="No"
    fi
    
    echo -e "${CYAN}Environment Status:${NC}"
    echo -e "${YELLOW}  Mode: $current_mode${NC}"
    echo -e "${YELLOW}  WSL Detected: $is_wsl_detected${NC}"
    
    if is_wsl_mode; then
        local wsl_ip=$(get_wsl_ip)
        echo -e "${YELLOW}  WSL IP: $wsl_ip${NC}"
    fi
}