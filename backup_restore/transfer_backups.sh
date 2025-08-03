#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="/website_backups"

# Utility functions
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Simple backup transfer function
transfer_backups() {
    info "Starting backup transfer process..."
    
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Backup directory $BACKUP_DIR does not exist"
    fi
    
    # Show available backups
    echo "Available backup files:"
    echo "----------------------"
    ls -lah "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No .tar.gz files found"
    echo "----------------------"
    echo
    
    # Get destination details
    read -p "Enter destination IP address: " DEST_IP
    read -p "Enter destination username (default: root): " DEST_USER
    DEST_USER=${DEST_USER:-root}
    read -p "Enter SSH port (default: 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    read -p "Enter destination backup directory (default: /website_backups): " DEST_BACKUP_DIR
    DEST_BACKUP_DIR=${DEST_BACKUP_DIR:-/website_backups}
    
    # Clear any existing host keys for this IP to avoid conflicts
    info "Clearing any existing host keys for $DEST_IP..."
    ssh-keygen -R "$DEST_IP" 2>/dev/null || true
    
    # Create destination directory
    info "Creating destination directory..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "$DEST_USER@$DEST_IP" "mkdir -p $DEST_BACKUP_DIR" || error "Failed to create destination directory"
    
    # Transfer files
    info "Transferring backup files..."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$SSH_PORT" "$BACKUP_DIR"/*.tar.gz "$DEST_USER@$DEST_IP:$DEST_BACKUP_DIR/" || error "Transfer failed"
    
    success "Transfer completed successfully!"
    info "Files transferred to: $DEST_USER@$DEST_IP:$DEST_BACKUP_DIR/"
}

# Execute the transfer function
transfer_backups