#!/bin/bash

#=============================================================================
# Fast WordPress Permission-Setting Script
#=============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Utility functions
info() { echo -e "${BLUE}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }

# Check for root
[[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)"

# Check for path argument
if [ -z "$1" ]; then
    error "Usage: $0 /path/to/wordpress"
fi

WP_PATH="$1"

if [ ! -d "$WP_PATH" ]; then
    error "Directory '$WP_PATH' not found."
fi

info "Starting permission fix for $WP_PATH..."

# Set ownership
info "Setting ownership to www-data:www-data..."
chown -R www-data:www-data "$WP_PATH" || error "Failed to set ownership."

# Set base permissions: 755 for directories, 644 for files
# 'X' sets execute bit only for directories
info "Setting base directory and file permissions..."
chmod -R u=rwX,go=rX "$WP_PATH" || error "Failed to set base permissions."

# Grant group write access to wp-content for uploads, etc.
if [ -d "$WP_PATH/wp-content" ]; then
    info "Setting wp-content permissions..."
    chmod -R g+w "$WP_PATH/wp-content" || error "Failed to set wp-content permissions."
fi

# Secure wp-config.php
if [ -f "$WP_PATH/wp-config.php" ]; then
    info "Securing wp-config.php..."
    chmod 640 "$WP_PATH/wp-config.php" || error "Failed to secure wp-config.php."
fi

success "Permissions for $WP_PATH have been set successfully."