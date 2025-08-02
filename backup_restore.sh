#!/bin/bash

# WordPress Backup & Transfer - Minimal Version
set -e

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'

# Config
BACKUP_DIR="/website_backups"
WWW_PATH="/var/www"

# Utils
info() { echo -e "${B}[INFO]${N} $1"; }
ok() { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
err() { echo -e "${R}[ERROR]${N} $1" >&2; exit 1; }

# Install deps
install_deps() {
    local deps=()
    command -v ssh >/dev/null || deps+=("openssh-client")
    command -v rsync >/dev/null || deps+=("rsync")
    command -v nc >/dev/null || deps+=("netcat-openbsd")
    [ ${#deps[@]} -gt 0 ] && { info "Installing: ${deps[*]}"; apt update -qq && apt install -y "${deps[@]}"; }
}

# Test connection
test_conn() {
    info "Testing $1:$2..."
    nc -z -w5 "$1" "$2" || err "Cannot connect to $1:$2"
    ok "Connection test passed"
}

# Setup SSH keys
setup_keys() {
    local user="$1" host="$2" port="$3"
    info "Setting up SSH keys..."
    [ -d ~/.ssh ] || { mkdir -p ~/.ssh; chmod 700 ~/.ssh; }
    [ -f ~/.ssh/id_rsa ] || { ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q; chmod 600 ~/.ssh/id_rsa; }
    if ssh-copy-id -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$port" "$user@$host" 2>/dev/null; then
        ok "SSH keys configured"
        return 0
    fi
    warn "SSH key setup failed"
    return 1
}

# Test SSH auth
test_auth() {
    local user="$1" host="$2" port="$3"
    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -p "$port" "$user@$host" exit 2>/dev/null; then
        echo "key"
    else
        echo "password"
    fi
}

# Get input with validation
get_input() {
    local prompt="$1" default="$2" type="$3" value
    while true; do
        read -p "$prompt${default:+ (default: $default)}: " value
        value="${value:-$default}"
        case "$type" in
            ip) [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && { echo "$value"; return; } || warn "Invalid IP" ;;
            port) [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ] && { echo "$value"; return; } || warn "Invalid port" ;;
            *) [ -n "$value" ] && { echo "$value"; return; } || warn "Required field" ;;
        esac
    done
}

# List backups
list_backups() {
    local files
    readarray -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.dump" -o -name "*.sql" \) 2>/dev/null | sort)
    [ ${#files[@]} -eq 0 ] && err "No backup files found in $BACKUP_DIR"
    
    echo -e "${C}Available backups:${N}"
    for i in "${!files[@]}"; do
        local name=$(basename "${files[$i]}")
        local size=$(du -sh "${files[$i]}" | cut -f1)
        echo "  $((i+1))) $name ($size)"
    done
    echo "  $((${#files[@]}+1))) All files"
    
    while true; do
        read -p "Select files (1-$((${#files[@]}+1))): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#files[@]}+1)) ]; then
            if [ "$choice" -eq $((${#files[@]}+1)) ]; then
                printf '%s\n' "${files[@]}"
            else
                echo "${files[$((choice-1))]}"
            fi
            return
        fi
        warn "Invalid selection"
    done
}

# Create WordPress backup
backup_wp() {
    echo -e "${C}WordPress Backup${N}"
    local sites=()
    [ -d "$WWW_PATH" ] && while IFS= read -r -d '' site; do
        [ -f "$site/wp-config.php" ] && sites+=("$site")
    done < <(find "$WWW_PATH" -maxdepth 2 -type d -print0 2>/dev/null)
    
    [ ${#sites[@]} -eq 0 ] && err "No WordPress sites found"
    
    echo "WordPress sites:"
    for i in "${!sites[@]}"; do
        echo "  $((i+1))) ${sites[$i]}"
    done
    
    while true; do
        read -p "Select site (1-${#sites[@]}): " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#sites[@]} ] && break
        warn "Invalid selection"
    done
    
    local site="${sites[$((choice-1))]}"
    local name=$(basename "$site")
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup="$BACKUP_DIR/${name}_${timestamp}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    info "Creating backup..."
    
    # DB backup
    if command -v wp >/dev/null && wp core is-installed --path="$site" --allow-root 2>/dev/null; then
        wp db export "$site/${name}_db.sql" --path="$site" --allow-root
    fi
    
    # File backup
    tar -czf "$backup" -C "$(dirname "$site")" "$(basename "$site")" --exclude="*/cache/*" --exclude="*/logs/*"
    [ -f "$site/${name}_db.sql" ] && rm -f "$site/${name}_db.sql"
    
    ok "Backup created: $backup ($(du -sh "$backup" | cut -f1))"
}

# Transfer backups
transfer() {
    echo -e "${C}Backup Transfer${N}"
    [ -d "$BACKUP_DIR" ] || err "Backup directory not found"
    
    install_deps
    
    # Get destination
    local host user port dir
    host=$(get_input "Destination IP" "" "ip")
    user=$(get_input "Username" "root")
    port=$(get_input "SSH port" "22" "port")
    dir=$(get_input "Destination directory" "/website_backups")
    
    test_conn "$host" "$port"
    
    # Setup auth
    local auth=$(test_auth "$user" "$host" "$port")
    if [ "$auth" = "password" ]; then
        read -p "Setup SSH keys? (y/n): " setup
        [[ "$setup" =~ ^[Yy]$ ]] && setup_keys "$user" "$host" "$port" && auth="key"
    fi
    info "Using $auth authentication"
    
    # Create remote dir
    ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "mkdir -p '$dir'" || err "Failed to create remote directory"
    
    # Select files
    local files
    readarray -t files < <(list_backups)
    
    # Transfer
    info "Transferring ${#files[@]} file(s)..."
    local ok_count=0 fail_count=0
    
    for file in "${files[@]}"; do
        local name=$(basename "$file")
        info "Transferring $name..."
        if rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no -p $port" "$file" "$user@$host:$dir/"; then
            ok "Transferred: $name"
            ((ok_count++))
        else
            warn "Failed: $name"
            ((fail_count++))
        fi
    done
    
    # Verify
    info "Verifying transfers..."
    local verified=0
    for file in "${files[@]}"; do
        local name=$(basename "$file")
        local local_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        local remote_size=$(ssh -o StrictHostKeyChecking=no -p "$port" "$user@$host" "stat -c%s '$dir/$name' 2>/dev/null || stat -f%z '$dir/$name' 2>/dev/null" 2>/dev/null)
        [ "$local_size" = "$remote_size" ] && ((verified++)) || warn "Size mismatch: $name"
    done
    
    echo -e "\n${C}Summary:${N}"
    echo "Files: ${#files[@]} | Transferred: $ok_count | Failed: $fail_count | Verified: $verified"
    echo "Destination: $user@$host:$dir"
    
    [ "$ok_count" -eq "${#files[@]}" ] && [ "$verified" -eq "${#files[@]}" ] && ok "All transfers successful!" || warn "Some transfers had issues"
}

# Restore from backup
restore() {
    echo -e "${C}WordPress Restore${N}"
    [ -d "$BACKUP_DIR" ] || err "Backup directory not found"
    
    local files
    readarray -t files < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort)
    [ ${#files[@]} -eq 0 ] && err "No backup files found"
    
    echo "Available backups:"
    for i in "${!files[@]}"; do
        echo "  $((i+1))) $(basename "${files[$i]}")"
    done
    
    while true; do
        read -p "Select backup (1-${#files[@]}): " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ] && break
        warn "Invalid selection"
    done
    
    local backup="${files[$((choice-1))]}"
    read -p "Target site name: " target
    [ -z "$target" ] && err "Target name required"
    
    local target_dir="$WWW_PATH/$target"
    if [ -d "$target_dir" ]; then
        read -p "Directory exists. Overwrite? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || err "Restore cancelled"
        rm -rf "$target_dir"
    fi
    
    info "Extracting backup..."
    tar -xzf "$backup" -C "$WWW_PATH"
    
    # Import DB if WP-CLI available
    if command -v wp >/dev/null && [ -f "$target_dir/wp-config.php" ]; then
        local db_file=$(find "$target_dir" -name "*_db.sql" -o -name "*.sql" | head -1)
        if [ -n "$db_file" ]; then
            info "Importing database..."
            wp db import "$db_file" --path="$target_dir" --allow-root && rm -f "$db_file"
        fi
    fi
    
    # Fix permissions
    chown -R www-data:www-data "$target_dir" 2>/dev/null || true
    chmod 755 "$target_dir" 2>/dev/null || true
    
    ok "Restore completed: $target_dir"
}

# Menu
menu() {
    echo -e "${C}WordPress Backup & Transfer${N}"
    echo "1) Create WordPress Backup"
    echo "2) Restore WordPress Site"
    echo "3) Transfer Backups via SSH"
    echo "0) Exit"
    read -p "Select option: " choice
    
    case "$choice" in
        1) backup_wp ;;
        2) restore ;;
        3) transfer ;;
        0) exit 0 ;;
        *) warn "Invalid option" && menu ;;
    esac
}

# Main
case "${1:-menu}" in
    backup) backup_wp ;;
    restore) restore ;;
    transfer) transfer ;;
    menu) menu ;;
    *) echo "Usage: $0 [backup|restore|transfer|menu]" ;;
esac