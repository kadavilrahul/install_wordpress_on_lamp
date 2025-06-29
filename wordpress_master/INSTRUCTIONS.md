# WordPress Master - Comprehensive Instructions & Documentation

## Table of Contents

1. [Quick Start Guide](#quick-start-guide)
2. [Installation Types](#installation-types)
    - [Complete LAMP Stack and WordPress](#complete-lamp-stack-and-wordpress)
    - [Apache and SSL Only](#apache-and-ssl-only)
    - [phpMyAdmin Installation](#phpmyadmin-installation)
3. [Backup and Restore Operations](#backup-and-restore-operations)
    - [WordPress Backup](#wordpress-backup)
    - [WordPress Restore](#wordpress-restore)
    - [PostgreSQL Backup](#postgresql-backup)
    - [PostgreSQL Restore](#postgresql-restore)
    - [Transfer Backups](#transfer-backups)
4. [System Management](#system-management)
    - [PHP Configuration](#php-configuration)
    - [Redis Configuration](#redis-configuration)
    - [SSH Security Management](#ssh-security-management)
    - [System Utilities](#system-utilities)
5. [Database Management](#database-management)
    - [MySQL Commands Guide](#mysql-commands-guide)
    - [DBeaver Connection Setup](#dbeaver-connection-setup)
6. [Troubleshooting Guide](#troubleshooting-guide)
    - [WordPress Issues](#wordpress-issues)
    - [Service Status Checks](#service-status-checks)
    - [System Resource Checks](#system-resource-checks)
    - [Redis Issues](#redis-issues)
7. [Advanced Configurations](#advanced-configurations)
    - [Serving Static HTML with WordPress](#serving-static-html-with-wordpress)
    - [Directory Index Priority](#directory-index-priority)
    - [Hosts File Configuration](#hosts-file-configuration)
8. [Cloud Backup with Rclone](#cloud-backup-with-rclone)
    - [Installation and Setup](#installation-and-setup)
    - [Usage Commands](#usage-commands)
    - [Automated Backups](#automated-backups)
9. [Development Tools](#development-tools)
    - [System Status Check](#system-status-check)
    - [Log File Locations](#log-file-locations)
10. [Security Best Practices](#security-best-practices)
    - [Initial Security Setup](#initial-security-setup)
    - [WordPress Security](#wordpress-security)
    - [SSL Certificate Management](#ssl-certificate-management)
    - [Database Security](#database-security)
    - [File Permissions](#file-permissions)
    - [Monitoring and Maintenance](#monitoring-and-maintenance)
11. [Configuration Files](#configuration-files)
12. [Support and Maintenance](#support-and-maintenance)

---

## Quick Start Guide

### Prerequisites
- Ubuntu 18.04+ (tested on Ubuntu 20.04/22.04)
- Root access (sudo privileges)
- Internet connection
- Minimum 5GB free disk space
- Domain name pointing to your server (for SSL)

### Installation
```bash
# Download the script
wget https://raw.githubusercontent.com/your-repo/wordpress_master/main/install.sh

# Make executable
chmod +x install.sh

# Run as root
sudo ./install.sh
```

### First Run
1. The script will check system requirements
2. Create a configuration file (`config.sh`)
3. Display the interactive menu
4. Follow the prompts for your desired operation

---

## Installation Types

### Complete LAMP Stack and WordPress

Choose from three installation types:

#### A. Main Domain Installation (example.com)
- Installs WordPress at the root of your domain
- Creates database with domain-based naming
- Sets up SSL for both domain.com and www.domain.com
- Configures Redis caching

**Process:**
1. Enter domain name (e.g., `example.com`)
2. Enter admin email
3. Set MySQL root password
4. Configure Redis memory allocation
5. Script automatically:
   - Installs Apache, MySQL, PHP
   - Downloads and configures WordPress
   - Creates database and user
   - Sets up SSL certificate
   - Configures Redis

#### B. Subdomain Installation (blog.example.com)
- Installs WordPress on a subdomain
- Creates separate database for subdomain
- SSL certificate for subdomain only

**DNS Requirements:**
```
A Record: blog.example.com → Your Server IP
```

#### C. Subdirectory Installation (example.com/blog)
- Installs WordPress in a subdirectory
- Configures WordPress URLs for subdirectory access
- Shares main domain SSL certificate

**Access URLs:**
- Website: `https://example.com/blog`
- Admin: `https://example.com/blog/wp-admin`

### Apache and SSL Only

For setting up domains without WordPress:

#### Setup New Domain
- Installs Apache if not present
- Creates professional welcome page
- Configures SSL with advanced fallback logic
- Handles site conflicts automatically

**Features:**
- **DNS Validation**: Checks if domain points to server
- **Conflict Detection**: Identifies interfering Apache sites
- **SSL Fallback Logic**:
  1. Try: `domain.com` + `www.domain.com`
  2. Fallback: `domain.com` only
  3. Final: HTTP only if SSL fails
- **Professional Welcome Page**: Styled HTML template

#### Remove Existing Domain
- Lists all configured domains
- Requires typing "DELETE" for confirmation
- Removes:
  - Apache configuration files
  - SSL certificates
  - Web directory
  - All associated files

### phpMyAdmin Installation

Installs database management interface:
- Pre-configures phpMyAdmin settings
- Creates symlink in web directory
- Enables Apache configuration
- Access: `http://your-domain/phpmyadmin`

---

## Backup and Restore Operations

### WordPress Backup

**Automated Process:**
1. Scans `/var/www/` for WordPress installations
2. Exports database using WP-CLI
3. Creates compressed archive excluding cache directories
4. Stores in `/website_backups/`
5. Cleans up old backups (7+ days)

**Excluded Directories:**
- `wp-content/cache`
- `wp-content/wpo-cache`
- `wp-content/uploads/cache`
- `wp-content/plugins/*/cache`

**Backup Format:**
```
sitename_backup_YYYY-MM-DD_HH-MM-SS.tar.gz
```

### WordPress Restore

**Interactive Process:**
1. Lists available backup files
2. Select backup by number
3. Enter target site name
4. Automated restoration:
   - Extracts files
   - Removes problematic cache files
   - Imports database
   - Deactivates problematic plugins
   - Updates WordPress core
   - Sets correct permissions

**Safety Features:**
- Confirms overwrite of existing sites
- Enables WordPress debug mode during restore
- Comprehensive error logging

### PostgreSQL Backup

**Configuration:**
- Database name (default: your_db)
- Database user (default: your_user)
- Database password
- Retention: 30 days

**Process:**
1. Installs PostgreSQL if needed
2. Creates database and user if not exist
3. Performs compressed backup using `pg_dump -Fc`
4. Stores in `/website_backups/postgres/`

### PostgreSQL Restore

**Process:**
1. Finds most recent dump file
2. Recreates database and user
3. Restores using `pg_restore`
4. Verifies restoration

### Transfer Backups

**Requirements:**
- Run on source server
- SSH access to destination server
- rsync installed

**Process:**
1. Confirms source server location
2. Gets destination IP address
3. Creates backup directory on destination
4. Transfers using rsync with progress

**Command Used:**
```bash
rsync -avz --progress /website_backups/ root@destination_ip:/website_backups
```

---

## System Management

### PHP Configuration

**Optimizations Applied:**
- `upload_max_filesize = 64M`
- `post_max_size = 64M`
- `memory_limit = 512M`
- `max_execution_time = 300`
- `max_input_time = 300`

**Files Modified:**
- `/etc/php/X.X/cli/php.ini`
- `/etc/php/X.X/apache2/php.ini`
- `/etc/php/X.X/fpm/php.ini`

**Services Restarted:**
- Apache2
- PHP-FPM (if running)

### Redis Configuration

**Setup Process:**
1. Installs Redis if not present
2. Configures memory limit
3. Enables and starts service
4. Updates `/etc/redis/redis.conf`

**Configuration:**
```bash
maxmemory XGb  # User-specified
```

### SSH Security Management

**Options:**
1. **Disable Root SSH Login**
   - Modifies `/etc/ssh/sshd_config`
   - Sets `PermitRootLogin no`
   - Restarts SSH service

2. **Enable Root SSH Login**
   - Sets `PermitRootLogin yes`
   - Restarts SSH service

### System Utilities

**Available Utilities:**

#### UFW Firewall
```bash
# Ports opened:
- SSH (22)
- HTTP (80)
- HTTPS (443)
- MySQL (3306)
```

#### Fail2ban
- Protects against brute force attacks
- Monitors SSH, Apache logs
- Automatic IP banning

#### Swap File Setup
- User-configurable size (default: 2GB)
- Creates `/swapfile`
- Adds to `/etc/fstab`

#### Additional Tools
- `plocate` - Fast file location
- `rclone` - Cloud storage sync
- `pv` - Progress viewer
- `rsync` - File synchronization

---

## Database Management

### MySQL Commands Guide

#### Access MySQL
```bash
sudo mysql -u root -p
```

#### Common Operations
```sql
-- Check databases
SHOW DATABASES;

-- Check users
SELECT User FROM mysql.user;

-- Login to specific database
mysql -u database_username -p database_name

-- Check WordPress URLs
SELECT option_name, option_value FROM wp_options 
WHERE option_name IN ('siteurl', 'home');

-- Check database size
SELECT table_schema AS "Database",
ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size (MB)"
FROM information_schema.tables
WHERE table_schema = "database_name"
GROUP BY table_schema;

-- Exit
EXIT;
```

#### Binary Log Management
```sql
-- Check binary logs
SHOW BINARY LOGS;

-- Clean binary logs (if /var/lib/mysql is large)
RESET MASTER;
```

### DBeaver Connection Setup

**Connection Details:**
- **Server Host:** Your server IP
- **Port:** 3306
- **Database:** Your database name
- **Username:** Your database user
- **Password:** Your database password

**SSH Tunnel (if needed):**
- **Use SSH Tunnel:** Yes
- **Host/IP:** Your server IP
- **Port:** 22
- **User Name:** root or your SSH user
- **Authentication:** Password or Key file

**Steps:**
1. Download DBeaver from https://dbeaver.io/
2. Create new MySQL connection
3. Enter connection details
4. Test connection
5. Save and connect

---

## Troubleshooting Guide

### WordPress Issues

#### wp-admin Fails to Load
```bash
# 1. Deactivate all plugins
wp plugin deactivate --all --allow-root --path=/var/www/your_website.com

# 2. Remove broken plugins manually
rm -rf /var/www/your_website.com/wp-content/plugins/plugin_name

# 3. Reactivate plugins
wp plugin activate --all --path=/var/www/your_website.com --allow-root
```

#### Enable WordPress Debug Mode
Add to `wp-config.php`:
```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

Check debug log:
```bash
tail -n 20 /var/www/your_site/wp-content/debug.log
grep -i "fatal\|error" /var/www/your_site/wp-content/debug.log | tail -20
```

### Service Status Checks

#### Apache
```bash
# Status
sudo systemctl status apache2

# Restart
sudo systemctl restart apache2

# Check error logs
tail -n 20 /var/log/apache2/error.log
tail -n 50 /var/log/apache2/error_your_website.com.log
```

#### MySQL
```bash
# Status
sudo systemctl status mysql

# Restart
sudo systemctl restart mysql
```

#### PHP-FPM
```bash
# Status
systemctl status php8.3-fpm

# Restart
systemctl restart php8.3-fpm
```

### System Resource Checks

#### Memory Usage
```bash
free -h
```

#### Disk Usage
```bash
df -h
du -sh /var/
du -sh /var/lib/mysql
```

### Redis Issues

#### Connection Errors
If you see "Error establishing a Redis connection":
```bash
# Remove Redis cache file
rm -f /var/www/your_site/wp-content/object-cache.php
```

---

## Advanced Configurations

### Serving Static HTML with WordPress

To serve static HTML pages alongside WordPress:

#### Apache Configuration
Edit `/etc/apache2/sites-available/your_website.com.conf`:

```apache
<VirtualHost *:80>
    ServerAdmin your_email@gmail.com
    ServerName your_website.com
    ServerAlias www.your_website.com
    DocumentRoot /var/www/your_website.com

    <Directory /var/www/your_website.com>
        AllowOverride All
        Require all granted
    </Directory>

    # Exclude /products folder from WordPress
    Alias /products /var/www/your_website.com/products
    <Directory /var/www/your_website.com/products>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error_your_website.com.log
    CustomLog ${APACHE_LOG_DIR}/access_your_website.com.log combined

    RewriteEngine on
    RewriteCond %{SERVER_NAME} =www.your_website.com [OR]
    RewriteCond %{SERVER_NAME} =your_website.com
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
```

#### Enable Configuration
```bash
sudo a2ensite your_website.com.conf
sudo systemctl reload apache2
```

### Directory Index Priority

To prioritize `index.html` over `index.php`:

#### Method 1: VirtualHost Configuration
```apache
<Directory /var/www/html>
    AllowOverride All
    Options -Indexes +FollowSymLinks
    Require all granted
    DirectoryIndex index.html index.php
</Directory>
```

#### Method 2: .htaccess File
Create `/var/www/html/.htaccess`:
```apache
DirectoryIndex index.html index.php
Options -Indexes
```

### Hosts File Configuration

For development/testing multiple WordPress installations:

#### Windows
Edit `C:\Windows\System32\drivers\etc\hosts`:
```
# WordPress Development Sites
135.181.193.176    nilgiristores.in
135.181.193.176    www.nilgiristores.in
135.181.203.43     silkroademart.com
135.181.203.43     www.silkroademart.com
```

#### macOS/Linux
Edit `/etc/hosts`:
```bash
sudo nano /etc/hosts
```
Add the same entries as above.

#### Flush DNS Cache
**Windows:**
```cmd
ipconfig /flushdns
```

**macOS:**
```bash
sudo dscacheutil -flushcache
```

**Linux:**
```bash
sudo systemctl restart systemd-resolved
```

---

## Cloud Backup with Rclone

### Installation and Setup

#### Prerequisites
- Google Cloud account
- VS Code or Remote Desktop (for authentication)

#### Installation Process
```bash
# 1. Enter root user
sudo bash

# 2. Install rclone
sudo apt update
sudo apt install rclone

# 3. Configure rclone
rclone config
```

#### Configuration Steps
1. Select `n` for new remote
2. Name it `my_remote`
3. Select Google Drive (option 13 or 18)
4. For auto config: Press Enter
5. For manual config with credentials:
   - Go to https://console.cloud.google.com/
   - Create new project (e.g., "rclone-backup")
   - Enable Google Drive API
   - Create OAuth client ID (Desktop app)
   - Download credentials JSON
6. Select `1` for full access
7. Leave service_account_file blank
8. Select No for advanced config
9. Select Yes for auto config
10. Authorize in browser
11. Select No for Shared Drive
12. Confirm configuration

### Google Cloud Console Setup

#### Create Credentials
1. Go to Google Cloud Console
2. Create new project
3. Enable Google Drive API
4. Go to Credentials page
5. Create OAuth client ID
6. Choose "Desktop app"
7. Download credentials

### Verification Commands
```bash
# List directories
rclone lsf my_remote: --dirs-only
rclone lsd my_remote:

# List files
rclone lsl my_remote:

# Tree view
rclone tree my_remote:
```

### Usage Commands

#### Check Storage Size
```bash
# Entire drive
rclone size "my_remote:"

# Specific folder
rclone size "my_remote:/path/to/folder/"
```

#### Check Latest Backups
```bash
rclone lsl "my_remote:/path/to/folder/" | sort -k2,2 | tail -n 2
```

#### Restore Latest Files
```bash
read -p "How many latest backup files do you want to copy? (1 or 2): " NUM && [[ "$NUM" == "1" || "$NUM" == "2" ]] && rclone lsl "my_remote:/path/to/folder/" | sort -k2,2 | tail -n $NUM | awk '{print $NF}' | xargs -I{} rclone copy -v "my_remote:/path/to/folder/{}" /website_backups --progress || echo "Invalid input. Please enter 1 or 2."
```

#### Backup Operations
```bash
# Copy to cloud (preserves versions)
rclone copy /website_backups "my_remote:" --log-file=/var/log/rclone.log

# Sync to cloud (overwrites)
rclone sync /website_backups "my_remote:" --progress

# Copy specific file
rclone copy -v "my_remote:/path/to/backup.tar.gz" /website_backups --progress
```

### Automated Backups

#### Cron Job Setup
```bash
# Edit crontab
crontab -e

# Add daily backup at 5:00 AM
0 5 */1 * * /usr/bin/rclone copy /website_backups "my_remote:" --log-file=/var/log/rclone.log
```

### Uninstallation
```bash
sudo apt remove rclone
```

---

## Development Tools

### System Status Check

Comprehensive system health check:

#### System Information
- OS version and kernel
- System uptime
- Hardware information

#### Resource Usage
- Memory usage (free -h)
- Disk usage by partition
- Directory sizes

#### Service Status
- Apache2 status
- MySQL status
- Redis status
- PHP-FPM status

#### Network Status
- Active connections on key ports (80, 443, 3306, 22)
- Network interface information

#### WordPress Sites
- Automatic detection of WordPress installations
- Site status and configuration

### Log File Locations

#### WordPress Master Logs
```
/var/log/wordpress_master_YYYYMMDD_HHMMSS.log
```

#### System Logs
```
/var/log/apache2/error.log
/var/log/apache2/access.log
/var/log/apache2/error_domain.com.log
/var/log/mysql/error.log
/var/log/rclone.log
```

#### WordPress Debug Logs
```
/var/www/your_site/wp-content/debug.log
```

---

## Security Best Practices

### Initial Security Setup

#### 1. Change Default Passwords
- MySQL root password (set during installation)
- WordPress admin password (set during WP setup)
- Server user passwords

#### 2. Configure Firewall (UFW)
```bash
# Enable UFW (via menu option 12)
ufw --force enable
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3306  # Only if remote DB access needed
```

#### 3. Install Fail2ban
```bash
# Via menu option 12
# Protects against brute force attacks
```

#### 4. Disable Root SSH (After Setup)
```bash
# Via menu option 11
# Create non-root user first
```

### WordPress Security

#### 1. Security Headers
Add to `.htaccess`:
```apache
# Security Headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
Header always set Content-Security-Policy "default-src 'self'"
```

#### 2. Hide WordPress Version
Add to `functions.php`:
```php
// Remove WordPress version
remove_action('wp_head', 'wp_generator');
```

#### 3. Limit Login Attempts
Install security plugins:
- Wordfence Security
- Limit Login Attempts Reloaded
- iThemes Security

#### 4. Regular Updates
```bash
# Update WordPress core
wp core update --allow-root --path=/var/www/your_site

# Update plugins
wp plugin update --all --allow-root --path=/var/www/your_site

# Update themes
wp theme update --all --allow-root --path=/var/www/your_site
```

### SSL Certificate Management

#### Auto-Renewal
Certbot automatically sets up renewal. Check with:
```bash
# Test renewal
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

#### Manual Renewal
```bash
sudo certbot renew
```

### Database Security

#### 1. Secure MySQL Installation
```bash
# Run MySQL secure installation
sudo mysql_secure_installation
```

#### 2. Database User Privileges
```sql
-- Create limited user for applications
CREATE USER 'app_user'@'localhost' IDENTIFIED BY 'strong_password';
GRANT SELECT, INSERT, UPDATE, DELETE ON app_database.* TO 'app_user'@'localhost';
FLUSH PRIVILEGES;
```

#### 3. Regular Backups
- Use menu option 4 for WordPress backups
- Use menu option 6 for PostgreSQL backups
- Set up automated cloud backups with rclone

### File Permissions

#### WordPress Permissions
```bash
# Set correct ownership
sudo chown -R www-data:www-data /var/www/your_site

# Set directory permissions
sudo find /var/www/your_site -type d -exec chmod 755 {} \;

# Set file permissions
sudo find /var/www/your_site -type f -exec chmod 644 {} \;

# Secure wp-config.php
sudo chmod 600 /var/www/your_site/wp-config.php
```

### Monitoring and Maintenance

#### 1. Regular System Updates
```bash
sudo apt update && sudo apt upgrade -y
```

#### 2. Monitor Disk Space
```bash
df -h
du -sh /var/www/*
du -sh /var/lib/mysql
```

#### 3. Monitor Logs
```bash
# Check for errors
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/mysql/error.log
```

#### 4. Backup Verification
- Regularly test restore procedures
- Verify backup integrity
- Test cloud backup accessibility

---

## Configuration Files

### WordPress Master Configuration
Location: `wordpress_master/config.sh`

```bash
# WordPress Master Configuration
# Generated automatically

# Database Configuration
DB_ROOT_PASSWORD="your_secure_password"
ADMIN_EMAIL="admin@example.com"

# Redis Configuration
REDIS_MAX_MEMORY="2"

# Paths
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"

# Last installation details
LAST_DOMAIN="example.com"
LAST_INSTALL_TYPE="main_domain"
LAST_INSTALL_DATE="2024-01-01 12:00:00"
```

### Apache Virtual Host Template
```apache
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/example.com
    DirectoryIndex index.html index.php
    
    <Directory /var/www/example.com>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/example.com-error.log
    CustomLog ${APACHE_LOG_DIR}/example.com-access.log combined
</VirtualHost>
```

### WordPress wp-config.php Additions
```php
// WordPress Master Configurations
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');

// Redis Configuration
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);

// Debug Configuration (disable in production)
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);
```

---

## Support and Maintenance

### Getting Help

1. **Built-in Troubleshooting**: Menu option 13
2. **System Status Check**: Menu option 15
3. **Log Files**: Check `/var/log/wordpress_master_*.log`
4. **Community Support**: GitHub issues and discussions

### Regular Maintenance Tasks

#### Weekly
- [ ] Check system status (menu option 15)
- [ ] Review error logs
- [ ] Update WordPress core and plugins
- [ ] Verify backup integrity

#### Monthly
- [ ] System package updates
- [ ] Security audit
- [ ] Performance optimization
- [ ] Cleanup old backups and logs

#### Quarterly
- [ ] Full security review
- [ ] Disaster recovery testing
- [ ] Performance benchmarking
- [ ] Documentation updates

### Version Information

- **WordPress Master Version**: 1.0
- **Compatible Ubuntu Versions**: 18.04, 20.04, 22.04
- **PHP Versions Supported**: 7.4, 8.0, 8.1, 8.2, 8.3
- **MySQL/MariaDB Versions**: 5.7+, 10.3+

---

*This documentation covers all functionality from the original custom_script collection, enhanced with the WordPress Master interactive interface and additional features.*
