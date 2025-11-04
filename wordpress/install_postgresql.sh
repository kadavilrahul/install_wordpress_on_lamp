#!/bin/bash

# PostgreSQL Installation Script with Extensions
# Handles PostgreSQL service installation and PHP extensions
# Database creation is handled by restore scripts based on config.json
# Author: System Administrator
# Version: 2.0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_VERSION="16"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display the header
show_header() {
    echo ""
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "🐘 PostgreSQL Installation with Extensions"
    print_message "$BLUE" "=========================================="
    echo ""
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "$RED" "❌ This script must be run as root or with sudo"
        exit 1
    fi
}

# Function to check system requirements
check_system() {
    print_message "$BLUE" "🔍 Checking system requirements..."
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        print_message "$GREEN" "✅ Operating System: $OS $VER"
    else
        print_message "$RED" "❌ Cannot identify operating system"
        exit 1
    fi
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_message "$YELLOW" "⚠️  This script is designed for Ubuntu/Debian systems"
        read -p "Continue anyway? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check available memory
    available_mem=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_mem" -lt 512 ]; then
        print_message "$YELLOW" "⚠️  Low memory available: ${available_mem}MB"
        print_message "$YELLOW" "   PostgreSQL requires at least 512MB free memory"
    else
        print_message "$GREEN" "✅ Available memory: ${available_mem}MB"
    fi
    
    # Check disk space
    available_space=$(df / | awk 'NR==2{print $4}')
    if [ "$available_space" -lt 1048576 ]; then # Less than 1GB
        print_message "$YELLOW" "⚠️  Low disk space available"
        print_message "$YELLOW" "   PostgreSQL requires at least 1GB free space"
    else
        space_gb=$((available_space / 1048576))
        print_message "$GREEN" "✅ Available disk space: ${space_gb}GB"
    fi
}

# Function to check if PostgreSQL is already installed
check_existing_installation() {
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        print_message "$YELLOW" "⚠️  PostgreSQL is already installed and running"
        
        # Get version
        pg_version=$(sudo -u postgres psql -t -c "SELECT version();" 2>/dev/null | head -1)
        if [ ! -z "$pg_version" ]; then
            print_message "$BLUE" "   Version: $pg_version"
        fi
        
        echo ""
        echo "What would you like to do?"
        echo "1. Skip installation and configure new database"
        echo "2. Reinstall PostgreSQL (will remove existing data)"
        echo "3. Exit"
        echo ""
        read -r -p "Select option [1-3]: " existing_choice
        
        case $existing_choice in
            1)
                return 1  # Skip installation, proceed to configuration
                ;;
            2)
                uninstall_postgresql
                return 0  # Proceed with installation
                ;;
            3)
                print_message "$BLUE" "Exiting..."
                exit 0
                ;;
            *)
                print_message "$RED" "❌ Invalid choice"
                exit 1
                ;;
        esac
    fi
    return 0  # Proceed with installation
}

# Function to uninstall PostgreSQL
uninstall_postgresql() {
    print_message "$RED" "🔥 Uninstalling existing PostgreSQL..."
    
    # Stop service
    systemctl stop postgresql 2>/dev/null
    systemctl disable postgresql 2>/dev/null
    
    # Remove packages
    apt-get purge -y postgresql* 2>/dev/null
    apt-get autoremove -y
    
    # Remove directories
    rm -rf /var/lib/postgresql/
    rm -rf /etc/postgresql/
    rm -rf /var/log/postgresql/
    
    print_message "$GREEN" "✅ Previous PostgreSQL installation removed"
}

# Function to install PostgreSQL
install_postgresql() {
    print_message "$BLUE" "📦 Installing PostgreSQL and extensions..."
    
    # Update package list
    apt-get update
    
    # Install PostgreSQL with contrib (includes extensions)
    apt-get install -y postgresql postgresql-contrib
    
    if [ $? -ne 0 ]; then
        print_message "$RED" "❌ Failed to install PostgreSQL"
        exit 1
    fi
    
    # Install additional useful packages
    apt-get install -y postgresql-client postgresql-common
    
    print_message "$GREEN" "✅ PostgreSQL packages installed"
    
    # Start and enable service
    systemctl start postgresql
    systemctl enable postgresql
    
    # Wait for service to start
    sleep 3
    
    # Verify service is running
    if ! systemctl is-active --quiet postgresql; then
        print_message "$RED" "❌ PostgreSQL service failed to start"
        exit 1
    fi
    
    print_message "$GREEN" "✅ PostgreSQL service started and enabled"
}



# Function to install PHP PostgreSQL extensions
install_php_extensions() {
    print_message "$BLUE" "🔌 Installing PHP PostgreSQL Extensions..."
    echo ""
    
    # Detect PHP version
    if command -v php >/dev/null 2>&1; then
        php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        print_message "$GREEN" "✅ PHP version detected: $php_version"
    else
        print_message "$YELLOW" "⚠️  PHP not detected, will install default extensions"
        php_version=""
    fi
    
    # Update package list
    apt-get update >/dev/null 2>&1
    
    # Install PHP PostgreSQL extensions based on version
    if [ ! -z "$php_version" ]; then
        # Try to install version-specific package
        package_name="php${php_version}-pgsql"
        print_message "$BLUE" "Installing $package_name..."
        
        if apt-get install -y $package_name >/dev/null 2>&1; then
            print_message "$GREEN" "✅ $package_name installed successfully"
        else
            # Fallback to generic package
            print_message "$YELLOW" "⚠️  Version-specific package not found, trying generic php-pgsql"
            apt-get install -y php-pgsql >/dev/null 2>&1
        fi
    else
        # Install generic PHP PostgreSQL package
        apt-get install -y php-pgsql >/dev/null 2>&1
    fi
    
    # Also install PDO PostgreSQL driver
    if [ ! -z "$php_version" ]; then
        pdo_package="php${php_version}-pdo-pgsql"
        if apt-get install -y $pdo_package >/dev/null 2>&1; then
            print_message "$GREEN" "✅ PDO PostgreSQL driver installed"
        fi
    fi
    
    # Install PostgreSQL client tools if not present
    if ! command -v psql >/dev/null 2>&1; then
        print_message "$BLUE" "Installing PostgreSQL client tools..."
        apt-get install -y postgresql-client >/dev/null 2>&1
        print_message "$GREEN" "✅ PostgreSQL client tools installed"
    fi
    
    # Restart web server if running
    if systemctl is-active --quiet apache2; then
        print_message "$BLUE" "Restarting Apache..."
        systemctl restart apache2
        print_message "$GREEN" "✅ Apache restarted"
    elif systemctl is-active --quiet nginx; then
        print_message "$BLUE" "Restarting Nginx..."
        systemctl restart nginx
        systemctl restart php*-fpm >/dev/null 2>&1
        print_message "$GREEN" "✅ Nginx and PHP-FPM restarted"
    fi
    
    # Verify installation
    echo ""
    print_message "$BLUE" "🧪 Verifying PHP PostgreSQL extension installation..."
    
    if php -m 2>/dev/null | grep -q pgsql; then
        print_message "$GREEN" "✅ PHP PostgreSQL extension is installed and loaded"
        
        # Show installed modules
        echo ""
        print_message "$BLUE" "Installed PostgreSQL PHP modules:"
        php -m 2>/dev/null | grep -i pg | while read module; do
            echo "  - $module"
        done
    else
        print_message "$YELLOW" "⚠️  PHP PostgreSQL extension may not be loaded"
        print_message "$YELLOW" "   You may need to restart your web server manually"
    fi
    
    echo ""
    print_message "$GREEN" "=========================================="
    print_message "$GREEN" "🎉 PHP PostgreSQL Extensions Installation Complete!"
    print_message "$GREEN" "=========================================="
    echo ""
    print_message "$BLUE" "Your PHP applications can now connect to PostgreSQL databases."
    print_message "$BLUE" "Use pg_connect() or PDO to establish connections."
    echo ""
}

# Function to install common extensions in template1 database
install_extensions() {
    print_message "$BLUE" "🔌 Installing PostgreSQL extensions in template database..."
    echo ""
    
    # Array of extensions to install
    declare -a extensions=(
        "pg_trgm:Trigram similarity search"
        "uuid-ossp:UUID generation functions"
        "pgcrypto:Cryptographic functions"
        "hstore:Key-value storage"
        "citext:Case-insensitive text"
        "pg_stat_statements:Query performance monitoring"
    )
    
    # Install each extension in template1 so all new databases have them
    for ext_info in "${extensions[@]}"; do
        IFS=':' read -r ext_name ext_desc <<< "$ext_info"
        
        echo -n "Installing $ext_name ($ext_desc)... "
        
        # Special handling for pg_stat_statements (requires shared_preload_libraries)
        if [ "$ext_name" = "pg_stat_statements" ]; then
            # Check if already in config
            if ! grep -q "shared_preload_libraries.*pg_stat_statements" /etc/postgresql/*/main/postgresql.conf 2>/dev/null; then
                # Add to postgresql.conf
                pg_version=$(ls /etc/postgresql/ | head -1)
                echo "shared_preload_libraries = 'pg_stat_statements'" >> /etc/postgresql/$pg_version/main/postgresql.conf
                systemctl restart postgresql
                sleep 2
            fi
        fi
        
        # Try to install extension in template1 database
        result=$(sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS \"$ext_name\";" 2>&1)
        
        if echo "$result" | grep -q "ERROR"; then
            print_message "$YELLOW" "⚠️  Failed"
            echo "     $result"
        else
            print_message "$GREEN" "✅"
        fi
    done
    
    echo ""
    print_message "$GREEN" "✅ Extension installation completed in template database"
    print_message "$BLUE" "   All new databases will have these extensions available"
}

# Function to configure PostgreSQL for optimal performance
configure_postgresql() {
    print_message "$BLUE" "⚙️  Configuring PostgreSQL for optimal performance..."
    
    # Get PostgreSQL version
    pg_version=$(ls /etc/postgresql/ | head -1)
    config_file="/etc/postgresql/$pg_version/main/postgresql.conf"
    
    if [ ! -f "$config_file" ]; then
        print_message "$YELLOW" "⚠️  Configuration file not found: $config_file"
        return
    fi
    
    # Backup original configuration
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Calculate optimal settings based on system resources
    total_mem=$(free -m | awk 'NR==2{print $2}')
    shared_buffers=$((total_mem / 4))  # 25% of RAM
    effective_cache=$((total_mem * 3 / 4))  # 75% of RAM
    
    # Apply performance settings
    cat >> "$config_file" << EOF

# Performance Tuning - Added by install_postgresql.sh
shared_buffers = ${shared_buffers}MB
effective_cache_size = ${effective_cache}MB
maintenance_work_mem = $((total_mem / 16))MB
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
work_mem = $((total_mem / 100))MB
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4

# Logging
log_statement = 'all'
log_duration = on
log_line_prefix = '%m [%p] %q%u@%d '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0

# Connection Settings
max_connections = 200
EOF
    
    print_message "$GREEN" "✅ Performance settings applied"
    
    # Configure authentication (pg_hba.conf) for local connections
    hba_file="/etc/postgresql/$pg_version/main/pg_hba.conf"
    if [ -f "$hba_file" ]; then
        # Backup original
        cp "$hba_file" "${hba_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Ensure local connections can use md5 authentication
        if ! grep -q "^host.*all.*all.*127.0.0.1/32.*md5" "$hba_file"; then
            echo "# Allow local connections with password authentication" >> "$hba_file"
            echo "host    all             all             127.0.0.1/32            md5" >> "$hba_file"
            echo "host    all             all             ::1/128                 md5" >> "$hba_file"
            print_message "$GREEN" "✅ Authentication rules updated for local connections"
        fi
    fi
    
    # Restart PostgreSQL to apply changes
    systemctl restart postgresql
    sleep 3
    
    if systemctl is-active --quiet postgresql; then
        print_message "$GREEN" "✅ PostgreSQL restarted with new configuration"
    else
        print_message "$RED" "❌ PostgreSQL failed to restart"
        print_message "$YELLOW" "   Restoring original configuration..."
        mv "${config_file}.backup."* "$config_file"
        if [ -f "${hba_file}.backup."* ]; then
            mv "${hba_file}.backup."* "$hba_file"
        fi
        systemctl restart postgresql
    fi
}

# Function to test PostgreSQL service
test_service() {
    print_message "$BLUE" "🧪 Testing PostgreSQL service..."
    
    # Check if service is running
    if systemctl is-active --quiet postgresql; then
        print_message "$GREEN" "✅ PostgreSQL service is running"
        
        # Get and display service info
        echo ""
        print_message "$BLUE" "📊 PostgreSQL Information:"
        
        # PostgreSQL version
        pg_version=$(sudo -u postgres psql -t -c "SELECT version();" 2>/dev/null | head -1)
        echo "  PostgreSQL: $(echo $pg_version | cut -d' ' -f1-3)"
        
        # List databases
        echo "  Existing Databases:"
        databases=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1');" 2>/dev/null)
        if [ -z "$databases" ]; then
            echo "    (none)"
        else
            for db in $databases; do
                echo "    - $db"
            done
        fi
        
        # Check installed extensions in template1
        echo "  Available Extensions (template1):"
        extensions=$(sudo -u postgres psql -d template1 -t -c "SELECT extname FROM pg_extension WHERE extname != 'plpgsql';" 2>/dev/null)
        if [ -z "$extensions" ]; then
            echo "    (none)"
        else
            for ext in $extensions; do
                echo "    - $ext"
            done
        fi
    else
        print_message "$RED" "❌ PostgreSQL service is not running"
        print_message "$YELLOW" "   Try: systemctl start postgresql"
    fi
}

# Function to display final summary
show_summary() {
    echo ""
    print_message "$GREEN" "=========================================="
    print_message "$GREEN" "🎉 PostgreSQL Installation Complete!"
    print_message "$GREEN" "=========================================="
    echo ""
    
    print_message "$BLUE" "📋 Installation Summary:"
    echo ""
    echo "PostgreSQL Service:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Status: $(systemctl is-active postgresql)"
    echo ""
    
    # Get PostgreSQL version
    pg_version=$(sudo -u postgres psql -t -c "SELECT version();" 2>/dev/null | head -1)
    echo "Version: $(echo $pg_version | cut -d' ' -f1-3)"
    echo ""
    
    print_message "$BLUE" "🔧 Database Creation:"
    echo "Databases will be created automatically when restoring sites"
    echo "using restore_postgresql.sh based on each domain's config.json"
    echo ""
    
    print_message "$BLUE" "📝 PHP Connection Example:"
    echo 'After database creation via restore script:'
    echo '  $conn = pg_connect("host=localhost dbname=your_db user=your_user password=your_pass");'
    echo ""
    echo "Python Connection Example:"
    echo '  import psycopg2'
    echo '  conn = psycopg2.connect(host="localhost", database="your_db", user="your_user", password="your_pass")'
    echo ""
    
    print_message "$YELLOW" "⚠️  Important Notes:"
    echo "  1. PostgreSQL service is now installed and running"
    echo "  2. PHP PostgreSQL extensions are installed"
    echo "  3. Common extensions are available in template database"
    echo "  4. Use restore_postgresql.sh to create databases from config.json"
    echo "  5. Each domain should have its own database configuration"
    echo ""
    
    print_message "$BLUE" "📚 Useful Commands:"
    echo "  List all databases:      sudo -u postgres psql -l"
    echo "  Check service status:    systemctl status postgresql"
    echo "  View logs:              journalctl -u postgresql -n 50"
    echo "  Restart service:        systemctl restart postgresql"
    echo "  Connect as postgres:    sudo -u postgres psql"
    echo ""
}

# Main installation menu
show_menu() {
    echo ""
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "PostgreSQL Service Installation Menu"
    print_message "$BLUE" "=========================================="
    echo ""
    echo "1. Complete Installation (PostgreSQL + PHP Extensions + Optimizations)"
    echo "2. Install PostgreSQL Service Only"
    echo "3. Install PHP PostgreSQL Extensions Only"
    echo "4. Install PostgreSQL Extensions in Template Database"
    echo "5. Configure Performance Settings"
    echo "6. Test PostgreSQL Service"
    echo "7. Uninstall PostgreSQL"
    echo "0. Exit"
    echo ""
    read -r -p "Select option [0-7]: " choice
    
    case $choice in
        1)
            # Complete installation
            check_system
            if check_existing_installation; then
                install_postgresql
            fi
            install_extensions
            install_php_extensions
            configure_postgresql
            test_service
            show_summary
            ;;
        2)
            # Install PostgreSQL only
            check_system
            if check_existing_installation; then
                install_postgresql
            fi
            print_message "$GREEN" "✅ PostgreSQL service installed successfully"
            ;;
        3)
            # Install PHP PostgreSQL extensions
            install_php_extensions
            ;;
        4)
            # Install PostgreSQL extensions in template
            install_extensions
            ;;
        5)
            # Configure performance
            configure_postgresql
            ;;
        6)
            # Test service
            test_service
            ;;
        7)
            # Uninstall
            uninstall_postgresql
            ;;
        0)
            print_message "$BLUE" "Goodbye!"
            exit 0
            ;;
        *)
            print_message "$RED" "❌ Invalid option"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    # Check if running as root
    check_root
    
    # Show header
    show_header
    
    # Check for command line arguments
    if [ $# -eq 0 ]; then
        # Interactive mode - show full menu
        show_menu
    else
        # Handle command line arguments
        case "$1" in
            --install-php-extensions|--php-ext)
                # Direct installation of PHP extensions without menu
                install_php_extensions
                ;;
            --install-all)
                check_system
                if check_existing_installation; then
                    install_postgresql
                fi
                install_extensions
                install_php_extensions
                configure_postgresql
                test_service
                show_summary
                ;;
            --install-only)
                check_system
                if check_existing_installation; then
                    install_postgresql
                fi
                print_message "$GREEN" "✅ PostgreSQL service installed"
                ;;
            --install-extensions)
                install_extensions
                ;;
            --configure)
                configure_postgresql
                ;;
            --test)
                test_service
                ;;
            --uninstall)
                uninstall_postgresql
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --install-all                        Complete installation (PostgreSQL + PHP ext + config)"
                echo "  --install-only                       Install PostgreSQL service only"
                echo "  --install-php-extensions             Install PHP PostgreSQL extensions"
                echo "  --install-extensions                 Install PostgreSQL extensions in template DB"
                echo "  --configure                          Configure PostgreSQL performance settings"
                echo "  --test                               Test PostgreSQL service"
                echo "  --uninstall                          Uninstall PostgreSQL"
                echo "  --help                               Show this help message"
                echo ""
                echo "Interactive mode: Run without arguments for menu"
                echo ""
                echo "Note: Database creation is handled by restore_postgresql.sh"
                echo "      based on each domain's config.json file"
                ;;
            *)
                print_message "$RED" "❌ Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"