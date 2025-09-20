#!/bin/bash

# PostgreSQL Installation Script with Extensions
# Similar to the one in /var/www/nilgiristores.in/generator
# Author: System Administrator
# Version: 1.0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_DB_NAME="wordpress_db"
DEFAULT_DB_USER="wordpress_user"
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
        read -p "Select option [1-3]: " existing_choice
        
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

# Function to get database configuration from user
get_database_config() {
    echo ""
    print_message "$BLUE" "📋 Database Configuration"
    echo ""
    
    # Database name
    read -p "Enter database name (default: $DEFAULT_DB_NAME): " db_name
    if [ -z "$db_name" ]; then
        db_name="$DEFAULT_DB_NAME"
    fi
    
    # Validate database name
    if [[ ! "$db_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_message "$RED" "❌ Invalid database name. Use only letters, numbers, and underscores."
        exit 1
    fi
    
    # Database user
    read -p "Enter database user (default: $DEFAULT_DB_USER): " db_user
    if [ -z "$db_user" ]; then
        db_user="$DEFAULT_DB_USER"
    fi
    
    # Validate username
    if [[ ! "$db_user" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_message "$RED" "❌ Invalid username. Use only letters, numbers, and underscores."
        exit 1
    fi
    
    # Database password
    while true; do
        read -s -p "Enter database password: " db_pass
        echo
        if [ -z "$db_pass" ]; then
            print_message "$RED" "❌ Password cannot be empty"
            continue
        fi
        
        read -s -p "Confirm database password: " db_pass_confirm
        echo
        
        if [ "$db_pass" != "$db_pass_confirm" ]; then
            print_message "$RED" "❌ Passwords do not match. Please try again."
            continue
        fi
        
        # Check password strength
        if [ ${#db_pass} -lt 8 ]; then
            print_message "$YELLOW" "⚠️  Password is less than 8 characters"
            read -p "Use this weak password anyway? [y/N]: " use_weak
            if [[ ! "$use_weak" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        break
    done
    
    echo ""
    print_message "$BLUE" "Configuration Summary:"
    echo "  Database: $db_name"
    echo "  User: $db_user"
    echo "  Password: [HIDDEN]"
    echo ""
    
    read -p "Proceed with this configuration? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_message "$RED" "❌ Configuration cancelled"
        exit 1
    fi
}

# Function to create database and user
create_database() {
    print_message "$BLUE" "🔧 Creating database and user..."
    
    # Check if database already exists
    db_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" 2>/dev/null)
    if [ "$db_exists" = "1" ]; then
        print_message "$YELLOW" "⚠️  Database '$db_name' already exists"
        read -p "Drop and recreate? [y/N]: " drop_db
        if [[ "$drop_db" =~ ^[Yy]$ ]]; then
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS $db_name;" 2>/dev/null
            print_message "$GREEN" "✅ Existing database dropped"
        else
            print_message "$BLUE" "Using existing database"
        fi
    fi
    
    # Check if user already exists
    user_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_user WHERE usename='$db_user'" 2>/dev/null)
    if [ "$user_exists" = "1" ]; then
        print_message "$YELLOW" "⚠️  User '$db_user' already exists"
        read -p "Drop and recreate? [y/N]: " drop_user
        if [[ "$drop_user" =~ ^[Yy]$ ]]; then
            sudo -u postgres psql -c "DROP USER IF EXISTS $db_user;" 2>/dev/null
            print_message "$GREEN" "✅ Existing user dropped"
        else
            # Update password for existing user
            sudo -u postgres psql -c "ALTER USER $db_user WITH PASSWORD '$db_pass';" 2>/dev/null
            print_message "$GREEN" "✅ Password updated for existing user"
        fi
    fi
    
    # Create database if it doesn't exist
    if [ "$db_exists" != "1" ] || [[ "$drop_db" =~ ^[Yy]$ ]]; then
        sudo -u postgres psql -c "CREATE DATABASE $db_name;" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✅ Database '$db_name' created"
        else
            print_message "$RED" "❌ Failed to create database"
            exit 1
        fi
    fi
    
    # Create user if it doesn't exist
    if [ "$user_exists" != "1" ] || [[ "$drop_user" =~ ^[Yy]$ ]]; then
        sudo -u postgres psql -c "CREATE USER $db_user WITH PASSWORD '$db_pass';" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✅ User '$db_user' created"
        else
            print_message "$RED" "❌ Failed to create user"
            exit 1
        fi
    fi
    
    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;" 2>/dev/null
    sudo -u postgres psql -d "$db_name" -c "GRANT ALL ON SCHEMA public TO $db_user;" 2>/dev/null
    sudo -u postgres psql -d "$db_name" -c "GRANT CREATE ON SCHEMA public TO $db_user;" 2>/dev/null
    
    print_message "$GREEN" "✅ Privileges granted to user '$db_user'"
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

# Function to install extensions
install_extensions() {
    print_message "$BLUE" "🔌 Installing PostgreSQL extensions..."
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
    
    # Install each extension
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
        
        # Try to install extension
        result=$(sudo -u postgres psql -d "$db_name" -c "CREATE EXTENSION IF NOT EXISTS \"$ext_name\";" 2>&1)
        
        if echo "$result" | grep -q "ERROR"; then
            print_message "$YELLOW" "⚠️  Failed"
            echo "     $result"
        else
            print_message "$GREEN" "✅"
        fi
    done
    
    echo ""
    print_message "$GREEN" "✅ Extension installation completed"
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
effective_cache_size = ${effective_cache}GB
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
    
    # Configure authentication (pg_hba.conf)
    hba_file="/etc/postgresql/$pg_version/main/pg_hba.conf"
    if [ -f "$hba_file" ]; then
        # Backup original
        cp "$hba_file" "${hba_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add entry for our database/user if not exists
        if ! grep -q "$db_name.*$db_user" "$hba_file"; then
            echo "host    $db_name    $db_user    127.0.0.1/32    md5" >> "$hba_file"
            echo "host    $db_name    $db_user    ::1/128         md5" >> "$hba_file"
            print_message "$GREEN" "✅ Authentication rules added"
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
        mv "${hba_file}.backup."* "$hba_file"
        systemctl restart postgresql
    fi
}

# Function to test database connection
test_connection() {
    print_message "$BLUE" "🧪 Testing database connection..."
    
    # Test with psql
    PGPASSWORD="$db_pass" psql -h localhost -U "$db_user" -d "$db_name" -c "SELECT version();" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "✅ Connection test successful"
        
        # Get and display database info
        echo ""
        print_message "$BLUE" "📊 Database Information:"
        
        # PostgreSQL version
        pg_version=$(sudo -u postgres psql -t -c "SELECT version();" 2>/dev/null | head -1)
        echo "  PostgreSQL: $(echo $pg_version | cut -d' ' -f1-3)"
        
        # Database size
        db_size=$(sudo -u postgres psql -d "$db_name" -t -c "SELECT pg_size_pretty(pg_database_size('$db_name'));" 2>/dev/null | tr -d ' ')
        echo "  Database Size: $db_size"
        
        # List installed extensions
        echo "  Installed Extensions:"
        extensions=$(sudo -u postgres psql -d "$db_name" -t -c "SELECT extname FROM pg_extension WHERE extname != 'plpgsql';" 2>/dev/null)
        for ext in $extensions; do
            echo "    - $ext"
        done
    else
        print_message "$RED" "❌ Connection test failed"
        print_message "$YELLOW" "   Please check your credentials and PostgreSQL configuration"
    fi
}

# Function to create backup script
create_backup_script() {
    print_message "$BLUE" "📝 Creating backup script..."
    
    backup_script="/usr/local/bin/backup_postgresql_${db_name}.sh"
    
    cat > "$backup_script" << EOF
#!/bin/bash
# PostgreSQL Backup Script for $db_name
# Generated by install_postgresql.sh

BACKUP_DIR="/var/backups/postgresql"
DB_NAME="$db_name"
DB_USER="$db_user"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\${BACKUP_DIR}/\${DB_NAME}_\${TIMESTAMP}.sql.gz"

# Create backup directory if it doesn't exist
mkdir -p "\$BACKUP_DIR"

# Perform backup
export PGPASSWORD="$db_pass"
pg_dump -h localhost -U "\$DB_USER" -d "\$DB_NAME" | gzip > "\$BACKUP_FILE"

if [ \$? -eq 0 ]; then
    echo "✅ Backup successful: \$BACKUP_FILE"
    
    # Keep only last 7 days of backups
    find "\$BACKUP_DIR" -name "\${DB_NAME}_*.sql.gz" -mtime +7 -delete
else
    echo "❌ Backup failed"
    exit 1
fi
EOF
    
    chmod +x "$backup_script"
    print_message "$GREEN" "✅ Backup script created: $backup_script"
    
    # Add to crontab for daily backups
    read -p "Add daily automatic backup to crontab? [Y/n]: " add_cron
    if [[ ! "$add_cron" =~ ^[Nn]$ ]]; then
        # Add to root's crontab
        (crontab -l 2>/dev/null; echo "0 2 * * * $backup_script") | crontab -
        print_message "$GREEN" "✅ Daily backup scheduled at 2:00 AM"
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
    echo "Database Connection Details:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  Database: $db_name"
    echo "  Username: $db_user"
    echo "  Password: [saved securely]"
    echo ""
    echo "Connection String:"
    echo "  postgresql://$db_user:****@localhost:5432/$db_name"
    echo ""
    echo "PHP Connection Example:"
    echo '  $conn = pg_connect("host=localhost dbname='$db_name' user='$db_user' password=****");'
    echo ""
    echo "Python Connection Example:"
    echo '  import psycopg2'
    echo '  conn = psycopg2.connect(host="localhost", database="'$db_name'", user="'$db_user'", password="****")'
    echo ""
    
    if [ -f "$backup_script" ]; then
        echo "Backup Script: $backup_script"
        echo "  Run manually: sudo $backup_script"
        echo ""
    fi
    
    print_message "$YELLOW" "⚠️  Important Security Notes:"
    echo "  1. Store database credentials securely"
    echo "  2. Regularly update PostgreSQL for security patches"
    echo "  3. Configure firewall to restrict database access"
    echo "  4. Enable SSL for remote connections"
    echo "  5. Regularly backup your database"
    echo ""
    
    print_message "$BLUE" "📚 Useful Commands:"
    echo "  Connect to database:     sudo -u postgres psql -d $db_name"
    echo "  List all databases:      sudo -u postgres psql -l"
    echo "  Check service status:    systemctl status postgresql"
    echo "  View logs:              journalctl -u postgresql -n 50"
    echo "  Backup database:        $backup_script"
    echo ""
    
    # Save credentials to file
    cred_file="/root/.postgresql_${db_name}_credentials"
    cat > "$cred_file" << EOF
# PostgreSQL Credentials for $db_name
# Generated: $(date)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$db_name
DB_USER=$db_user
DB_PASS=$db_pass
EOF
    chmod 600 "$cred_file"
    print_message "$GREEN" "✅ Credentials saved to: $cred_file (mode 600)"
}

# Main installation menu
show_menu() {
    echo ""
    print_message "$BLUE" "=========================================="
    print_message "$BLUE" "PostgreSQL Installation Menu"
    print_message "$BLUE" "=========================================="
    echo ""
    echo "1. Complete Installation (PostgreSQL + Database + Extensions)"
    echo "2. Install PostgreSQL Only"
    echo "3. Create Database and User Only"
    echo "4. Install Database Extensions Only"
    echo "5. Install PHP PostgreSQL Extensions"
    echo "6. Configure Performance Settings"
    echo "7. Test Database Connection"
    echo "8. Create Backup Script"
    echo "9. Uninstall PostgreSQL"
    echo "0. Exit"
    echo ""
    read -p "Select option [0-9]: " choice
    
    case $choice in
        1)
            # Complete installation
            check_system
            if check_existing_installation; then
                install_postgresql
            fi
            get_database_config
            create_database
            install_extensions
            configure_postgresql
            test_connection
            create_backup_script
            show_summary
            ;;
        2)
            # Install PostgreSQL only
            check_system
            install_postgresql
            print_message "$GREEN" "✅ PostgreSQL installed successfully"
            ;;
        3)
            # Create database only
            get_database_config
            create_database
            test_connection
            ;;
        4)
            # Install database extensions only
            read -p "Enter database name: " db_name
            install_extensions
            ;;
        5)
            # Install PHP PostgreSQL extensions
            install_php_extensions
            ;;
        6)
            # Configure performance
            configure_postgresql
            ;;
        7)
            # Test connection
            read -p "Enter database name: " db_name
            read -p "Enter database user: " db_user
            read -s -p "Enter database password: " db_pass
            echo
            test_connection
            ;;
        8)
            # Create backup script
            read -p "Enter database name: " db_name
            read -p "Enter database user: " db_user
            read -s -p "Enter database password: " db_pass
            echo
            create_backup_script
            ;;
        9)
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
                
                # Use provided credentials or defaults
                db_name="${2:-$DEFAULT_DB_NAME}"
                db_user="${3:-$DEFAULT_DB_USER}"
                db_pass="${4:-$(openssl rand -base64 12)}"
                
                create_database
                install_extensions
                configure_postgresql
                test_connection
                create_backup_script
                show_summary
                ;;
            --install-only)
                check_system
                install_postgresql
                ;;
            --create-db)
                db_name="${2:-$DEFAULT_DB_NAME}"
                db_user="${3:-$DEFAULT_DB_USER}"
                db_pass="${4:-$(openssl rand -base64 12)}"
                create_database
                test_connection
                ;;
            --uninstall)
                uninstall_postgresql
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --install-php-extensions              Install PHP PostgreSQL extensions"
                echo "  --install-all [db_name] [db_user] [db_pass]  Complete installation"
                echo "  --install-only                        Install PostgreSQL only"
                echo "  --create-db [db_name] [db_user] [db_pass]   Create database only"
                echo "  --uninstall                          Uninstall PostgreSQL"
                echo "  --help                               Show this help message"
                echo ""
                echo "Interactive mode: Run without arguments"
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