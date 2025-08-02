#!/bin/bash

# WordPress Backup Transfer Script - Simplified and Fixed
# Addresses SSH transfer issues and supports both key and password authentication

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
BACKUP_DIR="/website_backups"
SSH_TIMEOUT=30

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die() { error "$1"; exit 1; }

# Function to check and install required packages
install_requirements() {
    info "Checking required packages..."
    
    local packages=()
    command -v ssh >/dev/null 2>&1 || packages+=("openssh-client")
    command -v rsync >/dev/null 2>&1 || packages+=("rsync")
    command -v nc >/dev/null 2>&1 || packages+=("netcat-openbsd")
    
    if [ ${#packages[@]} -gt 0 ]; then
        info "Installing required packages: ${packages[*]}"
        apt update -qq && apt install -y "${packages[@]}" || die "Failed to install required packages"
    fi
    
    success "All required packages are available"
}

# Function to test network connectivity
test_connectivity() {
    local host="$1"
    local port="$2"
    
    info "Testing connectivity to $host:$port..."
    
    # Test using netcat
    if nc -z -w5 "$host" "$port" 2>/dev/null; then
        success "Network connectivity test passed"
        return 0
    fi
    
    # Fallback to ping
    if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
        warn "Host is reachable but port $port may be closed"
        return 1
    fi
    
    die "Cannot reach host $host"
}

# Function to setup SSH keys
setup_ssh_keys() {
    local user="$1"
    local host="$2"
    local port="$3"
    
    info "Setting up SSH key authentication..."
    
    # Create .ssh directory if it doesn't exist
    [ -d ~/.ssh ] || { mkdir -p ~/.ssh; chmod 700 ~/.ssh; }
    
    # Generate SSH key if it doesn't exist
    if [ ! -f ~/.ssh/id_rsa ]; then
        info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "backup-$(hostname)-$(date +%Y%m%d)" -q
        chmod 600 ~/.ssh/id_rsa
        chmod 644 ~/.ssh/id_rsa.pub
    fi
    
    # Copy key to remote server
    info "Copying SSH key to remote server..."
    if ssh-copy-id -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$port" "$user@$host" 2>/dev/null; then
        success "SSH key copied successfully"
        
        # Test key authentication
        if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -p "$port" "$user@$host" exit 2>/dev/null; then
            success "SSH key authentication verified"
            return 0
        else
            warn "SSH key authentication test failed"
            return 1
        fi
    else
        warn "Failed to copy SSH key"
        return 1
    fi
}

# Function to test SSH authentication
test_ssh_auth() {
    local user="$1"
    local host="$2"
    local port="$3"
    
    info "Testing SSH authentication methods..."
    
    # Test key-based authentication first
    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -p "$port" "$user@$host" exit 2>/dev/null; then
        success "SSH key authentication works"
        echo "key"
        return 0
    fi
    
    # Test password authentication
    info "Key authentication failed, testing password authentication..."
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=1 -p "$port" "$user@$host" exit 2>/dev/null; then
        success "SSH password authentication works"
        echo "password"
        return 0
    fi
    
    warn "Both authentication methods failed"
    return 1
}

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local default="$2"
    local validation="$3"
    local value
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt (default: $default): " value
            value="${value:-$default}"
        else
            read -p "$prompt: " value
        fi
        
        case "$validation" in
            "ip")
                if [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    echo "$value"
                    return 0
                fi
                warn "Please enter a valid IP address"
                ;;
            "port")
                if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]; then
                    echo "$value"
                    return 0
                fi
                warn "Please enter a valid port number (1-65535)"
                ;;
            "nonempty")
                if [ -n "$value" ]; then
                    echo "$value"
                    return 0
                fi
                warn "This field cannot be empty"
                ;;
            *)
                echo "$value"
                return 0
                ;;
        esac
    done
}

# Function to list and select backup files
select_backup_files() {
    local backup_files
    readarray -t backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" -o -name "*.zip" \) 2>/dev/null | sort)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        die "No backup files found in $BACKUP_DIR"
    fi
    
    echo -e "${CYAN}Available backup files:${NC}"
    echo "----------------------------------------"
    for i in "${!backup_files[@]}"; do
        local filename=$(basename "${backup_files[$i]}")
        local filesize=$(du -sh "${backup_files[$i]}" 2>/dev/null | cut -f1)
        echo "  $((i+1))) $filename ($filesize)"
    done
    echo "  $((${#backup_files[@]}+1))) All files"
    echo "----------------------------------------"
    
    local choice
    while true; do
        read -p "Select files to transfer (1-$((${#backup_files[@]}+1))): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#backup_files[@]}+1)) ]; then
            if [ "$choice" -eq $((${#backup_files[@]}+1)) ]; then
                # All files selected
                printf '%s\n' "${backup_files[@]}"
            else
                # Single file selected
                echo "${backup_files[$((choice-1))]}"
            fi
            return 0
        fi
        
        warn "Please enter a valid selection"
    done
}

# Main transfer function
transfer_backups() {
    echo -e "${CYAN}WordPress Backup Transfer Tool${NC}"
    echo "======================================"
    
    # Check if backup directory exists
    [ -d "$BACKUP_DIR" ] || die "Backup directory $BACKUP_DIR does not exist"
    
    # Install requirements
    install_requirements
    
    # Get destination details
    echo -e "\n${CYAN}Destination Server Details:${NC}"
    local dest_host dest_user dest_port dest_dir
    dest_host=$(get_input "Destination IP address" "" "ip")
    dest_user=$(get_input "Destination username" "root" "nonempty")
    dest_port=$(get_input "SSH port" "22" "port")
    dest_dir=$(get_input "Destination backup directory" "/website_backups" "nonempty")
    
    # Test connectivity
    test_connectivity "$dest_host" "$dest_port"
    
    # Determine authentication method
    local auth_method
    auth_method=$(test_ssh_auth "$dest_user" "$dest_host" "$dest_port") || {
        warn "SSH authentication failed. Attempting to setup SSH keys..."
        if setup_ssh_keys "$dest_user" "$dest_host" "$dest_port"; then
            auth_method="key"
        else
            warn "SSH key setup failed. Will use password authentication."
            auth_method="password"
        fi
    }
    
    info "Using SSH $auth_method authentication"
    
    # Create destination directory
    info "Creating destination directory..."
    ssh -o StrictHostKeyChecking=no -p "$dest_port" "$dest_user@$dest_host" "mkdir -p '$dest_dir' && chmod 755 '$dest_dir'" || die "Failed to create destination directory"
    
    # Select files to transfer
    echo -e "\n${CYAN}File Selection:${NC}"
    local selected_files
    readarray -t selected_files < <(select_backup_files)
    
    # Transfer files
    echo -e "\n${CYAN}Starting Transfer:${NC}"
    local total_files=${#selected_files[@]}
    local transferred=0
    local failed=0
    
    for file in "${selected_files[@]}"; do
        local filename=$(basename "$file")
        info "Transferring $filename... ($((transferred+1))/$total_files)"
        
        if rsync -avz --progress --human-readable \
            -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT -p $dest_port" \
            "$file" "$dest_user@$dest_host:$dest_dir/"; then
            success "Transferred: $filename"
            ((transferred++))
        else
            error "Failed to transfer: $filename"
            ((failed++))
        fi
    done
    
    # Verify transfers
    echo -e "\n${CYAN}Verifying Transfer:${NC}"
    local verified=0
    for file in "${selected_files[@]}"; do
        local filename=$(basename "$file")
        local local_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        local remote_size=$(ssh -o StrictHostKeyChecking=no -p "$dest_port" "$dest_user@$dest_host" \
            "stat -c%s '$dest_dir/$filename' 2>/dev/null || stat -f%z '$dest_dir/$filename' 2>/dev/null" 2>/dev/null)
        
        if [ "$local_size" = "$remote_size" ] && [ -n "$remote_size" ]; then
            success "Verified: $filename"
            ((verified++))
        else
            warn "Verification failed: $filename (local: $local_size, remote: $remote_size)"
        fi
    done
    
    # Summary
    echo -e "\n${CYAN}Transfer Summary:${NC}"
    echo "======================================"
    echo "Total files: $total_files"
    echo "Transferred: $transferred"
    echo "Failed: $failed"
    echo "Verified: $verified"
    echo "Destination: $dest_user@$dest_host:$dest_dir"
    echo "Authentication: $auth_method"
    
    if [ "$transferred" -eq "$total_files" ] && [ "$verified" -eq "$total_files" ]; then
        success "All files transferred and verified successfully!"
    elif [ "$transferred" -eq "$total_files" ]; then
        warn "All files transferred but some verification failed"
    else
        error "Some files failed to transfer"
        exit 1
    fi
}

# Function to create a WordPress backup
create_wordpress_backup() {
    echo -e "${CYAN}WordPress Backup Creator${NC}"
    echo "======================================"
    
    # Find WordPress installations
    local wp_sites=()
    if [ -d "/var/www" ]; then
        while IFS= read -r -d '' site; do
            if [ -f "$site/wp-config.php" ]; then
                wp_sites+=("$site")
            fi
        done < <(find /var/www -maxdepth 2 -type d -print0 2>/dev/null)
    fi
    
    if [ ${#wp_sites[@]} -eq 0 ]; then
        die "No WordPress installations found"
    fi
    
    echo "Found WordPress sites:"
    for i in "${!wp_sites[@]}"; do
        echo "  $((i+1))) ${wp_sites[$i]}"
    done
    
    local choice
    while true; do
        read -p "Select site to backup (1-${#wp_sites[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#wp_sites[@]} ]; then
            break
        fi
        warn "Please enter a valid selection"
    done
    
    local selected_site="${wp_sites[$((choice-1))]}"
    local site_name=$(basename "$selected_site")
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create database backup
    info "Creating database backup..."
    if command -v wp >/dev/null 2>&1; then
        wp db export "$selected_site/${site_name}_db.sql" --path="$selected_site" --allow-root
    else
        warn "WP-CLI not found, skipping database backup"
    fi
    
    # Create file backup
    info "Creating file backup..."
    local backup_file="$BACKUP_DIR/${site_name}_backup_${timestamp}.tar.gz"
    tar -czf "$backup_file" -C "$(dirname "$selected_site")" "$(basename "$selected_site")" --exclude="*/cache/*" --exclude="*/logs/*"
    
    # Clean up database dump
    [ -f "$selected_site/${site_name}_db.sql" ] && rm -f "$selected_site/${site_name}_db.sql"
    
    success "Backup created: $backup_file"
    info "Size: $(du -sh "$backup_file" | cut -f1)"
}

# Main menu
main() {
    case "${1:-}" in
        "backup")
            create_wordpress_backup
            ;;
        "transfer")
            transfer_backups
            ;;
        "test")
            install_requirements
            success "SSH functionality test completed"
            ;;
        *)
            echo -e "${CYAN}WordPress Backup & Transfer Tool${NC}"
            echo "Usage: $0 [backup|transfer|test]"
            echo ""
            echo "Commands:"
            echo "  backup   - Create WordPress backup"
            echo "  transfer - Transfer backups to remote server"
            echo "  test     - Test SSH functionality"
            echo ""
            echo "Examples:"
            echo "  $0 backup"
            echo "  $0 transfer"
            ;;
    esac
}

# Run main function
main "$@"