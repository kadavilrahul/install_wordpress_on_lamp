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

# Disk Space Monitoring and Cleanup
function disk_space_monitor() {
    clear
    echo "Disk Space Monitoring"
    echo "===================="
    echo "  1) Show disk usage summary - Display disk usage, memory, and inode information"
    echo "  2) Show largest directories - Find directories consuming most disk space"
    echo "  3) Show largest files - Find files consuming most disk space"
    echo "  4) Clean system logs - Remove old log files and truncate large logs"
    echo "  5) Clean package cache - Clear apt cache and remove unused packages"
    echo "  6) Clean temporary files - Remove old temporary and cache files"
    echo "  7) Full system cleanup - Perform all cleanup operations at once"
    echo "  0) Back to menu - Return to main miscellaneous menu"
    read -p "Select option: " choice
    
    case $choice in
        1) show_disk_usage ;;
        2) show_largest_directories ;;
        3) show_largest_files ;;
        4) clean_system_logs ;;
        5) clean_package_cache ;;
        6) clean_temp_files ;;
        7) full_system_cleanup ;;
        0) return ;;
        *)
            echo "Invalid option"
            sleep 1
            disk_space_monitor
            return
            ;;
    esac
    
    read -p "Press Enter to continue..."
    disk_space_monitor
}

function show_disk_usage() {
    echo "=== Disk Usage Summary ==="
    df -h
    echo
    echo "=== Memory Usage ==="
    free -h
    echo
    echo "=== Inode Usage ==="
    df -i
}

function show_largest_directories() {
    echo "=== Top 10 Largest Directories ==="
    read -p "Enter path to scan (default: /): " scan_path
    scan_path=${scan_path:-/}
    
    if [ ! -d "$scan_path" ]; then
        error "Directory $scan_path does not exist"
        return 1
    fi
    
    echo "Scanning $scan_path (this may take a while)..."
    du -h "$scan_path" 2>/dev/null | sort -hr | head -10
}

function show_largest_files() {
    echo "=== Top 10 Largest Files ==="
    read -p "Enter path to scan (default: /): " scan_path
    scan_path=${scan_path:-/}
    
    if [ ! -d "$scan_path" ]; then
        error "Directory $scan_path does not exist"
        return 1
    fi
    
    echo "Scanning $scan_path (this may take a while)..."
    find "$scan_path" -type f -exec du -h {} + 2>/dev/null | sort -hr | head -10
}

function clean_system_logs() {
    echo "=== Cleaning System Logs ==="
    
    # Show current log sizes
    echo "Current log directory sizes:"
    du -sh /var/log/* 2>/dev/null | sort -hr | head -10
    echo
    
    read -p "Proceed with log cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean journal logs older than 7 days
        journalctl --vacuum-time=7d
        
        # Clean old log files
        find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        
        # Truncate large log files
        for log in /var/log/syslog /var/log/auth.log /var/log/kern.log; do
            if [ -f "$log" ] && [ $(stat -c%s "$log") -gt 104857600 ]; then  # 100MB
                echo "Truncating large log file: $log"
                tail -n 1000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
            fi
        done
        
        success "System logs cleaned"
    else
        echo "Log cleanup cancelled"
    fi
}

function clean_package_cache() {
    echo "=== Cleaning Package Cache ==="
    
    # Show current cache sizes
    echo "Current package cache sizes:"
    if [ -d "/var/cache/apt" ]; then
        du -sh /var/cache/apt 2>/dev/null
    fi
    if [ -d "/var/lib/apt/lists" ]; then
        du -sh /var/lib/apt/lists 2>/dev/null
    fi
    echo
    
    read -p "Proceed with package cache cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean apt cache
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y
        
        success "Package cache cleaned"
    else
        echo "Package cache cleanup cancelled"
    fi
}

function clean_temp_files() {
    echo "=== Cleaning Temporary Files ==="
    
    # Show current temp sizes
    echo "Current temporary directory sizes:"
    du -sh /tmp /var/tmp 2>/dev/null
    echo
    
    read -p "Proceed with temporary files cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Clean /tmp (files older than 7 days)
        find /tmp -type f -mtime +7 -delete 2>/dev/null
        find /tmp -type d -empty -delete 2>/dev/null
        
        # Clean /var/tmp (files older than 30 days)
        find /var/tmp -type f -mtime +30 -delete 2>/dev/null
        find /var/tmp -type d -empty -delete 2>/dev/null
        
        # Clean user cache directories
        find /home -name ".cache" -type d -exec du -sh {} \; 2>/dev/null | head -5
        
        success "Temporary files cleaned"
    else
        echo "Temporary files cleanup cancelled"
    fi
}

function full_system_cleanup() {
    echo "=== Full System Cleanup ==="
    echo "This will perform all cleanup operations:"
    echo "- Clean system logs"
    echo "- Clean package cache"
    echo "- Clean temporary files"
    echo
    
    read -p "Proceed with full cleanup? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "Starting full system cleanup..."
        
        # Show initial disk usage
        echo "=== Initial Disk Usage ==="
        df -h /
        echo
        
        # Perform all cleanup operations
        echo "Cleaning system logs..."
        journalctl --vacuum-time=7d >/dev/null 2>&1
        find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        
        echo "Cleaning package cache..."
        apt-get clean >/dev/null 2>&1
        apt-get autoclean >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        
        echo "Cleaning temporary files..."
        find /tmp -type f -mtime +7 -delete 2>/dev/null
        find /var/tmp -type f -mtime +30 -delete 2>/dev/null
        
        # Show final disk usage
        echo "=== Final Disk Usage ==="
        df -h /
        
        success "Full system cleanup completed"
    else
        echo "Full cleanup cancelled"
    fi
}

# Main execution
main() {
    check_root
    disk_space_monitor
}

# Start script
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"