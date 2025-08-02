#!/bin/bash

# Colors and globals
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
DB_NAME="your_db"
DB_USER="your_user"
DB_PASS="your_password"
BACKUP_RETENTION_DAYS=30

# SSH Configuration
SSH_TIMEOUT=30
SSH_CONNECT_TIMEOUT=10

# Utility functions
log() { echo "[$1] $2"; }
error() { log "ERROR" "$1"; echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓ $1${NC}"; }
info() { log "INFO" "$1"; echo -e "${BLUE}ℹ $1${NC}"; }
warn() { log "WARNING" "$1"; echo -e "${YELLOW}⚠ $1${NC}"; }
confirm() { read -p "$(echo -e "${CYAN}$1 [Y/n]: ${NC}")" -n 1 -r; echo; [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; }

# Function to log messages with timestamp
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ${1}"
    echo "${message}"
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${message}" >> "${LOG_FILE}"
    fi
}

# Function to handle errors
error_exit() {
    log_message "ERROR: ${1}"
    exit 1
}

# Function to setup SSH keys for passwordless authentication
setup_ssh_keys() {
    local dest_ip="$1"
    local dest_user="$2"
    local ssh_port="$3"
    
    info "Setting up SSH keys for passwordless authentication..."
    
    # Ensure .ssh directory exists with correct permissions
    if [ ! -d ~/.ssh ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "backup-transfer-$(hostname)" -q
        if [ $? -ne 0 ]; then
            warn "Failed to generate SSH key pair"
            return 1
        fi
    fi
    
    # Ensure correct permissions on SSH key
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
    
    # Copy public key to destination with better error handling
    info "Copying public key to destination server..."
    
    # First, try to create .ssh directory on remote server
    if ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o StrictHostKeyChecking=no -p ${ssh_port} ${dest_user}@${dest_ip} "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 2>/dev/null; then
        # Now try to copy the key
        if ssh-copy-id -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o StrictHostKeyChecking=no -p ${ssh_port} ${dest_user}@${dest_ip} 2>/dev/null; then
            success "SSH key setup completed successfully!"
            
            # Test the key-based connection
            if ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o BatchMode=yes -o StrictHostKeyChecking=no -p ${ssh_port} ${dest_user}@${dest_ip} exit 2>/dev/null; then
                success "SSH key authentication verified!"
                return 0
            else
                warn "SSH key was copied but authentication test failed"
                return 1
            fi
        else
            warn "Failed to copy SSH key to destination server"
            return 1
        fi
    else
        warn "Failed to create .ssh directory on destination server"
        return 1
    fi
}

# Enhanced connectivity test function
test_connectivity() {
    local dest_ip="$1"
    local ssh_port="$2"
    
    info "Testing network connectivity to ${dest_ip}:${ssh_port}..."
    
    # Test basic TCP connectivity with timeout
    if timeout 10 bash -c "exec 3<>/dev/tcp/${dest_ip}/${ssh_port} && exec 3<&- && exec 3>&-" 2>/dev/null; then
        success "Network connectivity test passed"
        return 0
    else
        # Try alternative connectivity test using nc if available
        if command -v nc >/dev/null 2>&1; then
            if nc -z -w5 "${dest_ip}" "${ssh_port}" 2>/dev/null; then
                success "Network connectivity test passed (via nc)"
                return 0
            fi
        fi
        
        # Try ping as last resort
        if ping -c 1 -W 5 "${dest_ip}" >/dev/null 2>&1; then
            warn "Host is reachable but SSH port ${ssh_port} may be closed or filtered"
        else
            error_exit "Host ${dest_ip} is not reachable. Please check IP address and network connectivity."
        fi
        
        error_exit "Cannot connect to ${dest_ip}:${ssh_port}. Please check IP address, port, and firewall settings."
    fi
}

# Enhanced SSH authentication test
test_ssh_auth() {
    local dest_ip="$1"
    local dest_user="$2"
    local ssh_port="$3"
    local auth_method="$4"
    
    case "$auth_method" in
        "key")
            info "Testing SSH key authentication..."
            if ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o BatchMode=yes -o StrictHostKeyChecking=no -p ${ssh_port} ${dest_user}@${dest_ip} exit 2>/dev/null; then
                success "SSH key authentication successful"
                return 0
            else
                warn "SSH key authentication failed"
                return 1
            fi
            ;;
        "password")
            info "Testing SSH password authentication..."
            # For password auth, we can't test without actually prompting for password
            # So we'll just try a connection and let it fail gracefully
            if ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=1 -p ${ssh_port} ${dest_user}@${dest_ip} exit 2>/dev/null; then
                success "SSH password authentication successful"
                return 0
            else
                warn "SSH password authentication may have failed"
                return 1
            fi
            ;;
        *)
            error_exit "Unknown authentication method: $auth_method"
            ;;
    esac
}

# Transfer backups function
transfer_backups() {
    info "Starting backup transfer process..."
    
    # Install required packages
    info "Checking required packages..."
    local packages_to_install=()
    
    if ! command -v rsync &> /dev/null; then
        packages_to_install+=("rsync")
    fi
    
    if ! command -v ssh &> /dev/null; then
        packages_to_install+=("openssh-client")
    fi
    
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        info "Installing required packages: ${packages_to_install[*]}"
        apt update -qq && apt install -y "${packages_to_install[@]}" || error_exit "Failed to install required packages"
    fi
    
    # Check if backup directory exists and has files
    if [ ! -d "$BACKUP_DIR" ]; then
        error_exit "Backup directory $BACKUP_DIR does not exist. Please create backups first."
    fi
    
    # Count available backup files
    local backup_count=0
    backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" -o -name "*.zip" \) 2>/dev/null | wc -l)
    
    if [ "$backup_count" -eq 0 ]; then
        error_exit "No backup files found in $BACKUP_DIR. Please create backups first."
    fi
    
    # Show available backups with better formatting
    echo -e "${CYAN}Available backup files (${backup_count} total):${NC}"
    echo "----------------------------------------"
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" -o -name "*.zip" \) -exec ls -lah {} \; 2>/dev/null | awk '{print $9, "(" $5 ")"}'
    echo "----------------------------------------"
    echo
    
    # Ask if the user is on the source/old server
    read -p "Are you on the source/old server? (yes/no): " ON_SOURCE_SERVER
    if [[ "$ON_SOURCE_SERVER" != "yes" && "$ON_SOURCE_SERVER" != "y" ]]; then
        error_exit "Please run this script on the source/old server."
    fi
    
    # Get destination details with validation
    while true; do
        read -p "Enter the destination IP address: " DEST_IP
        if [[ -n "$DEST_IP" && "$DEST_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            warn "Please enter a valid IP address (e.g., 192.168.1.100)"
        fi
    done
    
    # Prompt for destination username (default: root)
    read -p "Enter destination username (default: root): " DEST_USER
    DEST_USER=${DEST_USER:-root}
    
    # Prompt for destination port (default: 22) with validation
    while true; do
        read -p "Enter SSH port (default: 22): " SSH_PORT
        SSH_PORT=${SSH_PORT:-22}
        if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
            break
        else
            warn "Please enter a valid port number (1-65535)"
        fi
    done
    
    # Set the destination backup directory
    read -p "Enter destination backup directory (default: /website_backups): " DEST_BACKUP_DIR
    DEST_BACKUP_DIR=${DEST_BACKUP_DIR:-/website_backups}
    
    # Test basic connectivity first
    test_connectivity "$DEST_IP" "$SSH_PORT"
    
    # Test SSH connection with different methods
    info "Testing SSH connection to ${DEST_USER}@${DEST_IP}:${SSH_PORT}..."
    
    SSH_AUTH_METHOD=""
    
    # First try with key-based authentication
    if test_ssh_auth "$DEST_IP" "$DEST_USER" "$SSH_PORT" "key"; then
        SSH_AUTH_METHOD="key"
    else
        warn "SSH key authentication failed."
        
        # Ask if user wants to setup SSH keys
        read -p "Would you like to setup SSH keys for passwordless authentication? (y/n): " SETUP_KEYS
        if [[ "$SETUP_KEYS" =~ ^[Yy]$ ]]; then
            if setup_ssh_keys "$DEST_IP" "$DEST_USER" "$SSH_PORT"; then
                SSH_AUTH_METHOD="key"
            else
                SSH_AUTH_METHOD="password"
            fi
        else
            SSH_AUTH_METHOD="password"
        fi
    fi
    
    # Final authentication method confirmation
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        success "Using SSH key authentication"
    else
        info "Using SSH password authentication"
        warn "You will be prompted for password during transfer"
    fi
    
    # Create the backup directory on the destination server if it doesn't exist
    info "Creating backup directory on destination server..."
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "mkdir -p ${DEST_BACKUP_DIR} && chmod 755 ${DEST_BACKUP_DIR}" || error_exit "Failed to create backup directory on destination"
    else
        ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} "mkdir -p ${DEST_BACKUP_DIR} && chmod 755 ${DEST_BACKUP_DIR}" || error_exit "Failed to create backup directory on destination"
    fi
    
    # Ask which files to transfer
    echo -e "${CYAN}Transfer options:${NC}"
    echo "1) Transfer all backup files"
    echo "2) Transfer only WordPress backups (.tar.gz)"
    echo "3) Transfer only database backups (.dump)"
    echo "4) Select specific files"
    read -p "Select option (1-4): " TRANSFER_OPTION
    
    case $TRANSFER_OPTION in
        1)
            TRANSFER_PATTERN="*"
            info "Selected: Transfer all backup files"
            ;;
        2)
            TRANSFER_PATTERN="*.tar.gz"
            info "Selected: Transfer WordPress backups only"
            # Verify .tar.gz files exist
            if [ -z "$(find ${BACKUP_DIR} -maxdepth 1 -name "*.tar.gz" 2>/dev/null)" ]; then
                warn "No .tar.gz files found in backup directory"
                return
            fi
            ;;
        3)
            TRANSFER_PATTERN="*.dump"
            info "Selected: Transfer database backups only"
            # Verify .dump files exist
            if [ -z "$(find ${BACKUP_DIR} -maxdepth 1 -name "*.dump" 2>/dev/null)" ]; then
                warn "No .dump files found in backup directory"
                return
            fi
            ;;
        4)
            echo "Available files:"
            readarray -t available_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" -o -name "*.zip" \) 2>/dev/null | sort)
            
            if [ ${#available_files[@]} -eq 0 ]; then
                warn "No backup files found in $BACKUP_DIR"
                return
            fi
            
            for i in "${!available_files[@]}"; do
                filename=$(basename "${available_files[$i]}")
                filesize=$(du -sh "${available_files[$i]}" 2>/dev/null | cut -f1 || echo "unknown")
                echo "  $((i+1))) $filename ($filesize)"
            done
            
            read -p "Enter file numbers to transfer (space-separated, e.g., '1 3 5' or '1-3'): " FILE_NUMBERS
            
            if [[ -z "$FILE_NUMBERS" ]]; then
                warn "No files selected."
                return
            fi
            
            # Parse file numbers and build list of selected files
            selected_files=()
            
            # Clean up input and handle ranges
            FILE_NUMBERS=$(echo "$FILE_NUMBERS" | sed -e 's/,/ /g' -e 's/  */ /g')
            
            for num_part in $FILE_NUMBERS; do
                if [[ "$num_part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    # Handle range like "1-3"
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    for j in $(seq "$start" "$end"); do
                        if [ "$j" -ge 1 ] && [ "$j" -le "${#available_files[@]}" ]; then
                            selected_files+=("${available_files[$((j-1))]}")
                        fi
                    done
                elif [[ "$num_part" =~ ^[0-9]+$ ]]; then
                    # Handle single number
                    if [ "$num_part" -ge 1 ] && [ "$num_part" -le "${#available_files[@]}" ]; then
                        selected_files+=("${available_files[$((num_part-1))]}")
                    fi
                fi
            done
            
            if [ ${#selected_files[@]} -eq 0 ]; then
                warn "No valid file numbers selected."
                return
            fi
            
            info "Selected files for transfer:"
            for file in "${selected_files[@]}"; do
                echo "  - $(basename "$file")"
            done
            
            TRANSFER_PATTERN="SELECTIVE"
            ;;
        *)
            TRANSFER_PATTERN="*"
            warn "Invalid option. Transferring all files."
            ;;
    esac
    
    # Transfer the backup files with progress indication
    if [ "$TRANSFER_PATTERN" = "SELECTIVE" ]; then
        info "Transferring selected backup files..."
        
        transfer_failed=false
        total_files=${#selected_files[@]}
        current_file=0
        
        for file in "${selected_files[@]}"; do
            current_file=$((current_file + 1))
            filename=$(basename "$file")
            info "Transferring file $current_file/$total_files: $filename"
            
            # Use rsync with progress and compression
            if rsync -avz --progress --human-readable \
                -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -p ${SSH_PORT}" \
                "$file" ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/; then
                success "Transferred: $filename"
            else
                warn "Failed to transfer: $filename"
                transfer_failed=true
            fi
        done
        
        if [ "$transfer_failed" = true ]; then
            error_exit "Some files failed to transfer"
        fi
    elif [ -n "$TRANSFER_PATTERN" ]; then
        info "Transferring backup files (pattern: $TRANSFER_PATTERN)..."
        
        # Count files to transfer
        files_to_transfer=$(find ${BACKUP_DIR} -maxdepth 1 -name "${TRANSFER_PATTERN}" -type f 2>/dev/null | wc -l)
        info "Found $files_to_transfer files to transfer"
        
        if [ "$files_to_transfer" -eq 0 ]; then
            warn "No files match the pattern: $TRANSFER_PATTERN"
            return
        fi
        
        # Use rsync with better options
        if rsync -avz --progress --human-readable --stats \
            -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -p ${SSH_PORT}" \
            ${BACKUP_DIR}/${TRANSFER_PATTERN} ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/; then
            success "Transfer completed successfully"
        else
            error_exit "Failed to transfer backup files"
        fi
    else
        warn "No files selected for transfer."
        return
    fi
    
    # Enhanced verification
    info "Verifying transfer..."
    
    if [ "$TRANSFER_PATTERN" = "SELECTIVE" ]; then
        # For selective transfers, verify each transferred file exists and has correct size
        info "Verifying selective file transfer..."
        verification_failed=false
        
        for file in "${selected_files[@]}"; do
            filename=$(basename "$file")
            local_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            
            # Get remote file size
            remote_size=$(ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} \
                "stat -f%z ${DEST_BACKUP_DIR}/$filename 2>/dev/null || stat -c%s ${DEST_BACKUP_DIR}/$filename 2>/dev/null" 2>/dev/null)
            
            if [ "$local_size" = "$remote_size" ] && [ -n "$remote_size" ]; then
                success "Verified: $filename (size: $local_size bytes)"
            else
                warn "Verification failed for: $filename (local: $local_size, remote: $remote_size)"
                verification_failed=true
            fi
        done
        
        if [ "$verification_failed" = true ]; then
            warn "Some files failed verification on remote server"
        else
            success "All selected files verified successfully on remote server"
        fi
    else
        # For pattern-based transfers, verify file count and total size
        local_count=$(find ${BACKUP_DIR} -maxdepth 1 -name "${TRANSFER_PATTERN}" -type f 2>/dev/null | wc -l)
        remote_count=$(ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${DEST_USER}@${DEST_IP} \
            "find ${DEST_BACKUP_DIR} -maxdepth 1 -type f 2>/dev/null | wc -l" 2>/dev/null)
        
        info "Local files matching pattern: $local_count"
        info "Total remote files: $remote_count"
        
        if [ "$local_count" -gt 0 ] && [ "$remote_count" -ge "$local_count" ]; then
            success "Transfer verification passed"
        else
            warn "Transfer verification inconclusive - please check manually"
        fi
    fi
    
    success "Backup transfer completed successfully!"
    info "Files transferred to: ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/"
    
    # Show final summary
    echo -e "${CYAN}Transfer Summary:${NC}"
    echo "- Source: $BACKUP_DIR"
    echo "- Destination: ${DEST_USER}@${DEST_IP}:${DEST_BACKUP_DIR}/"
    echo "- Authentication: $SSH_AUTH_METHOD"
    echo "- Transfer pattern: $TRANSFER_PATTERN"
    
    if [ "$TRANSFER_PATTERN" = "SELECTIVE" ]; then
        echo "- Files transferred: ${#selected_files[@]}"
    else
        echo "- Files transferred: $files_to_transfer"
    fi
}

# Execute the transfer function
transfer_backups