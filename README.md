# WordPress Master Installation Tool

A comprehensive LAMP stack management system for WordPress hosting with automated installation, backup/restore, and server management capabilities.

## Installation

Clone this repository to your server:

1. **Clone the repository**
   ```bash
   git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git && cd install_wordpress_on_lamp
   ```

2. **Create configuration file** from the sample, edit config.json with your settings
   ```bash
   cp sample_config.json config.json
   ```

3. **Run the tool as root:**
   ```bash
   bash run.sh
   ```

## Features

✅ **Complete LAMP Stack** - Automated Apache, MySQL, PHP, and WordPress setup  
✅ **Backup & Restore** - WordPress sites and databases with cloud storage integration  
✅ **SSL Management** - Automated Let's Encrypt certificates with conflict detection  
✅ **CLI & Interactive** - Both command-line and menu-driven interfaces  
✅ **Cloud Integration** - Rclone support for Google Drive and other providers  
✅ **Performance Tools** - Redis caching, PHP optimization, system monitoring  
✅ **Troubleshooting** - Comprehensive diagnostic and repair utilities  
✅ **Modular Design** - Organized components with individual CLI support

## Configuration

Create a `config.json` file based on `sample_config.json`:

```json
{
  "mysql_root_password": "your_secure_password",
  "admin_email": "admin@yourdomain.com",
  "main_domains": ["example.com"],
  "subdomains": ["blog.example.com"],
  "subdirectory_domains": ["example.com/shop"],
  "rclone_remotes": [{
    "client_id": "your_google_drive_client_id",
    "client_secret": "your_google_drive_client_secret",
    "remote_name": "server_backup"
  }],
  "redis_max_memory": "1"
}
```

## Quick Start

### Interactive Menu
```bash
sudo bash run.sh                    # Main category menu
sudo bash mysql/run.sh              # MySQL management
sudo bash backup_restore/run.sh     # Backup operations
```

### Direct CLI Commands
```bash
# WordPress operations
sudo bash wordpress/run.sh install        # Install LAMP + WordPress
sudo bash wordpress/run.sh remove         # Remove sites

# Backup operations  
sudo bash backup_restore/backup_wordpress.sh --first    # Backup first site
sudo bash backup_restore/backup_wordpress.sh --all      # Backup all sites

# System management
sudo bash mysql/run.sh remote             # Configure MySQL remote access
sudo bash apache/run.sh ssl               # Install SSL certificate
sudo bash system/run.sh status            # Check system status
sudo bash rclone/run.sh config             # Configure cloud storage
```

## Component Categories

1. **wordpress** - LAMP installation and WordPress management
2. **apache** - Website setup with SSL certificates  
3. **backup_restore** - Backup and restore operations
4. **mysql** - Database administration and remote access
5. **php** - PHP configuration and optimization
6. **system** - System monitoring and utilities
7. **rclone** - Cloud storage integration
8. **redis** - Caching configuration
9. **troubleshooting** - Diagnostic tools

## Key Operations

### WordPress Management
```bash
./wordpress/run.sh install     # Complete LAMP + WordPress installation
./wordpress/run.sh remove      # Remove websites and databases  
./wordpress/run.sh cleanup     # Clean orphaned databases
```

### Apache & SSL
```bash
./apache/run.sh ssl            # Install website with SSL certificate
./apache/run.sh fix            # Repair Apache configurations
```

### Backup & Restore
```bash
./backup_restore/backup_wordpress.sh --first     # Backup first site
./backup_restore/backup_wordpress.sh --all       # Backup all sites
./backup_restore/run.sh restore                  # Restore from backups
./backup_restore/run.sh transfer                 # Transfer to cloud
```

### MySQL Database  
```bash
./mysql/run.sh remote          # Configure remote access
./mysql/run.sh show            # Show databases
./mysql/run.sh users           # List MySQL users
./mysql/run.sh phpmyadmin      # Install phpMyAdmin
```

### System & Performance
```bash
./system/run.sh status         # System health check
./system/run.sh disk           # Disk space monitor
./php/run.sh adjust            # Optimize PHP settings
./redis/run.sh configure       # Setup Redis caching
```

### Cloud Storage
```bash
./rclone/run.sh install        # Install rclone
./rclone/run.sh config         # Configure Google Drive
./rclone/run.sh copy           # Upload backups to cloud
./rclone/run.sh cron           # Setup automated backups
```

### Troubleshooting
```bash
./troubleshooting/run.sh menu  # Launch diagnostic tools
./troubleshooting/run.sh guide # View database fix guide
```

## Directory Structure

```
install_wordpress_on_lamp/
├── run.sh                   # Main category menu
├── main.sh                  # Legacy menu (backward compatibility)  
├── config.json              # Your configuration (create from sample)
├── sample_config.json       # Configuration template
├── apache/run.sh            # Apache & SSL management
├── backup_restore/run.sh    # Backup & restore operations
├── mysql/run.sh             # Database management  
├── php/run.sh               # PHP configuration
├── rclone/run.sh            # Cloud storage integration
├── redis/run.sh             # Caching setup
├── system/run.sh            # System monitoring & utilities
├── troubleshooting/run.sh   # Diagnostic tools
└── wordpress/run.sh         # WordPress & LAMP installation
```

**Each component has both interactive menus and CLI support:**
- `./mysql/run.sh` - Interactive menu
- `./mysql/run.sh --help` - Show CLI commands  
- `./mysql/run.sh remote` - Direct command execution

## Usage Modes

### 1. Interactive Menus
```bash
sudo bash run.sh                     # Main category menu
sudo bash mysql/run.sh               # MySQL management menu
sudo bash backup_restore/run.sh      # Backup & restore menu
```

### 2. Direct CLI Commands  
```bash
sudo bash mysql/run.sh remote        # Configure MySQL remote access
sudo bash apache/run.sh ssl          # Install SSL certificate
sudo bash backup_restore/backup_wordpress.sh --all  # Backup all sites
```

### 3. Help & Discovery
```bash
sudo bash mysql/run.sh --help        # Show MySQL CLI commands
sudo bash rclone/run.sh --help       # Show cloud storage commands
sudo bash backup_restore/backup_wordpress.sh --help  # Backup options
```

## Requirements

- **Operating System:** Ubuntu 18.04+ or Debian 9+
- **Privileges:** Root access (sudo)
- **Network:** Internet connection for package downloads
- **Storage:** Minimum 2GB free space

## Automated Backup System

**Backup Features:**
- ✅ Complete WordPress site and database backups
- ✅ Cloud integration with Google Drive/rclone
- ✅ Automated cron scheduling  
- ✅ Compression and cleanup
- ✅ CLI and interactive modes

**Backup Commands:**
```bash
# Backup specific site
./backup_restore/backup_wordpress.sh --site example.com

# Backup all WordPress sites  
./backup_restore/backup_wordpress.sh --all

# Setup automated daily backups
./rclone/run.sh cron
```

**Storage Locations:**
- Local: `/website_backups/`
- WordPress: `/var/www/`  
- Logs: `/var/log/wordpress_master_*.log`

## Troubleshooting

### Quick Fixes
```bash
# Fix permissions
sudo chmod +x run.sh && sudo bash run.sh

# Check system status  
sudo bash system/run.sh status

# View troubleshooting guide
sudo bash troubleshooting/run.sh guide

# Check service status
sudo systemctl status mysql apache2 redis-server
```

### Common Issues
- **Permission Denied** → Run with `sudo` and check file permissions
- **MySQL Connection** → Verify service running and config.json credentials  
- **SSL Failed** → Check DNS pointing to server IP and domain accessibility
- **Backup Issues** → Check disk space and network connectivity
- **Port Issues** → Reboot server if rclone/network has problems

### Debug Logs
All operations logged to: `/var/log/wordpress_master_*.log`

## Recent Updates

✅ **Full CLI Support** - Every menu option now has direct CLI commands  
✅ **Enhanced Backup System** - Fixed cron jobs with proper CLI integration  
✅ **Modular Architecture** - Independent run.sh for each component  
✅ **Improved Help System** - `--help` support across all components  
✅ **Better Error Handling** - Comprehensive logging and diagnostics

## Requirements & Security

**System Requirements:**
- Ubuntu 18.04+ or Debian 9+
- Root/sudo access
- 2GB+ free space
- Internet connection

**Security Features:**
- SSL/TLS encryption with Let's Encrypt
- MySQL security hardening  
- WordPress security best practices
- Firewall integration recommendations

---

**⚠️ Production Warning:** Test on development servers first. This tool makes significant system changes.