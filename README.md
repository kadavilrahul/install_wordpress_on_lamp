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

- **Complete LAMP Stack Installation** - Automated Apache, MySQL, PHP, and WordPress setup
- **Backup & Restore System** - WordPress site and database backup/restore with cloud storage integration
- **SSL Certificate Management** - Automated SSL setup with Let's Encrypt and conflict detection
- **MySQL Management** - Remote access configuration, user management, and database operations
- **System Monitoring** - Server health checks, disk space monitoring, and performance optimization
- **Cloud Storage Integration** - Rclone support for Google Drive and other cloud providers
- **Redis Caching** - Performance optimization with Redis cache configuration
- **Troubleshooting Tools** - Comprehensive diagnostic and repair utilities
- **Modular Architecture** - Organized folder structure with dedicated run.sh for each component

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

## Menu Categories (main.sh)

The new modular system organizes all operations into 9 main categories:

1. **WordPress Management** - Installation and maintenance
2. **New Website Setup** - Install blank website with Apache + SSL
3. **Backup & Restore** - Backup and restore operations
4. **MySQL Database** - Database administration
5. **PHP Configuration** - PHP settings and information
6. **System Management** - System utilities and monitoring
7. **Cloud Storage (Rclone)** - Cloud backup management
8. **Redis Cache** - Caching configuration
9. **Troubleshooting** - Diagnostic and repair tools

## Detailed Operations

### 1. Install LAMP Stack + WordPress
Complete installation of Apache, MySQL, PHP, and WordPress with:
- Automatic package installation and configuration
- SSL certificate setup with Let's Encrypt
- WordPress installation with security hardening
- Database creation and user setup

### 3. Backup/Restore
- **WordPress Backup** - Creates compressed archives of sites and databases
- **WordPress Restore** - Restores sites from backup archives
- **PostgreSQL Support** - Database backup/restore for PostgreSQL
- **Transfer Backups** - Simplified backup transfer between servers

### 2. New Website Setup (Apache + SSL)
- Install new blank website with Apache web server
- Automatic SSL certificate installation with Let's Encrypt
- Virtual host configuration for new domains
- Apache configuration repair tools
- Multi-domain SSL setup with conflict detection

### 4. MySQL Management
- **Remote Access Setup** - Configure MySQL for remote connections
- **Database Operations** - Show databases, list users, check sizes
- **phpMyAdmin Installation** - Web-based MySQL administration
- **Security Configuration** - User management and access control

### 5. PHP Management
- PHP configuration optimization
- Version information and diagnostics
- Performance tuning for WordPress

### 6. Troubleshooting
- System diagnostics and health checks
- Common issue resolution
- Log analysis and error detection
- Service status monitoring

### 7. Rclone Management
- Cloud storage configuration
- Google Drive integration
- Backup synchronization
- Remote storage management

### 8. Redis Configuration
- Redis installation and setup
- Memory optimization
- WordPress cache integration
- Performance monitoring

### 9. System Management
- **System Status** - Resource usage and service monitoring
- **Disk Space Monitor** - Storage cleanup and monitoring
- **SSH Configuration** - Root access management
- **Utility Installation** - Common system tools

### 10. Website Management
- Remove websites and databases
- Clean up orphaned databases
- Site maintenance operations

### 11. Apache Management
- Virtual host management
- SSL certificate operations
- Configuration troubleshooting

## Directory Structure

```
install_wordpress_on_lamp/
├── main.sh                  # New category-based main menu
├── run.sh                   # Legacy main menu (backward compatibility)
├── config.json              # Configuration file (create from sample)
├── sample_config.json       # Configuration template
├── apache/                  # Apache management scripts
│   └── run.sh              # Apache-specific menu
├── backup_restore/          # Backup and restore utilities
│   └── run.sh              # Backup/restore menu
├── mysql/                   # MySQL management tools
│   └── run.sh              # MySQL management menu
├── php/                     # PHP configuration scripts
│   └── run.sh              # PHP configuration menu
├── rclone/                  # Cloud storage integration
│   └── run.sh              # Rclone management menu
├── redis/                   # Redis caching setup
│   └── run.sh              # Redis configuration menu
├── system/                  # System utilities and monitoring
│   └── run.sh              # System management menu
├── troubleshooting/         # Diagnostic and repair tools
│   └── run.sh              # Troubleshooting menu
├── wordpress/               # WordPress installation scripts
│   └── run.sh              # WordPress management menu
└── .examples/              # Example configurations and documentation
```

## Usage Options

### 1. New Category-Based Menu (Recommended)
```bash
sudo bash main.sh                    # Interactive category menu
sudo bash main.sh wordpress          # WordPress management menu
sudo bash main.sh mysql              # MySQL management menu
sudo bash main.sh wordpress install  # Direct command execution
```

### 2. Direct Folder Access
```bash
sudo bash wordpress/run.sh           # WordPress menu
sudo bash mysql/run.sh               # MySQL menu
sudo bash apache/run.sh ssl          # Direct SSL installation
```

### 3. Legacy Commands (Backward Compatible)
```bash
sudo bash run.sh                     # Original detailed menu
sudo bash main.sh lamp               # Install LAMP stack
sudo bash main.sh backup             # Backup WordPress
sudo bash main.sh mysql              # MySQL remote access
```

## Requirements

- **Operating System:** Ubuntu 18.04+ or Debian 9+
- **Privileges:** Root access (sudo)
- **Network:** Internet connection for package downloads
- **Storage:** Minimum 2GB free space

## Security Features

- **SSL/TLS Encryption** - Automatic HTTPS setup
- **Firewall Configuration** - UFW integration and recommendations
- **Secure MySQL Setup** - Remote access with security warnings
- **SSH Key Management** - Automated key-based authentication
- **WordPress Hardening** - Security best practices implementation

## Backup System

The backup system supports:
- **WordPress Sites** - Complete site and database backups
- **Automatic Discovery** - Finds WordPress installations automatically
- **Compression** - Efficient tar.gz archives
- **Cloud Integration** - Rclone support for remote storage
- **Retention Management** - Automatic cleanup of old backups

### Backup Locations
- Local backups: `/website_backups/`
- WordPress sites: `/var/www/`
- Logs: `/var/log/wordpress_master_*.log`

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo chmod +x main.sh
   sudo ./main.sh
   # Or for legacy:
   sudo chmod +x run.sh
   sudo ./run.sh
   ```

2. **MySQL Connection Failed**
   - Check MySQL service: `sudo systemctl status mysql`
   - Verify credentials in config.json
   - Check firewall settings

3. **SSL Certificate Failed**
   - Verify DNS points to server IP
   - Check domain accessibility
   - Review Apache error logs

4. **Backup Transfer Issues**
   - Ensure SSH access to destination
   - Check network connectivity
   - Verify destination directory permissions

### Log Files

All operations are logged to `/var/log/wordpress_master_*.log` with timestamps for debugging.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. Use at your own risk and ensure you understand the security implications of the configurations.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review log files for error details
3. Ensure all requirements are met
4. Test on a non-production server first

## Changelog

### Recent Updates
- **NEW: Modular Architecture** - Separate run.sh for each component folder
- **NEW: Category-Based Menu** - Organized main.sh with 9 categories
- **NEW: Direct Folder Access** - Run operations directly from component folders
- Simplified backup transfer system
- Enhanced SSL conflict detection
- Improved WordPress site discovery
- Added comprehensive logging
- Security hardening improvements
- Full backward compatibility maintained

---

**⚠️ Important:** Always test on a development server before using in production. This tool makes significant system changes and should be used by experienced administrators.