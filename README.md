# WordPress & Server Management Toolkit

This repository provides a comprehensive command-line toolkit for installing, managing, and maintaining WordPress websites on a LAMP stack. It includes specialized tools for backup/restore operations, system troubleshooting, database management, and cloud synchronization.

## Features

### Core WordPress Management
*   **Complete LAMP Stack Installation**: Automated setup of Apache, MySQL, PHP, and WordPress
*   **Multiple Installation Types**: Support for main domains, subdomains, and subdirectory installations
*   **SSL Certificate Management**: Automatic Let's Encrypt SSL certificate installation with conflict detection
*   **Database Management**: Automated database creation, user management, and security configuration

### Backup & Restore System
*   **WordPress Site Backups**: Complete site and database backup with WP-CLI integration
*   **PostgreSQL Support**: Full PostgreSQL database backup and restore capabilities
*   **Cloud Synchronization**: rclone integration for Google Drive backups
*   **Transfer Utilities**: Server-to-server backup transfer capabilities

### System Management Tools
*   **Disk Space Monitoring**: Comprehensive disk usage analysis and cleanup utilities
*   **MySQL Remote Access**: Automated remote database access configuration
*   **PHP Configuration**: Optimized PHP settings for WordPress performance
*   **Redis Configuration**: Memory caching setup and management
*   **SSH Security Management**: Root access control and security hardening

### Troubleshooting & Maintenance
*   **WordPress Diagnostics**: Automatic issue detection and resolution
*   **Permission Management**: Secure file and directory permission setting
*   **Service Monitoring**: Apache, MySQL, and PHP service status management
*   **Error Log Analysis**: Centralized log viewing and analysis
*   **Plugin Management**: Bulk plugin activation/deactivation and cleanup

## Prerequisites

*   Ubuntu server (18.04+)
*   Root or `sudo` privileges
*   Domain name pointed to your server's IP address
*   Internet connection for package downloads and SSL certificates

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git
cd install_wordpress_on_lamp
```

### 2. Configure Your Settings

Copy the sample configuration and customize it:

```bash
cp sample_config.json config.json
nano config.json
```

Update the configuration with your details:

```json
{
  "mysql_root_password": "YOUR_SECURE_PASSWORD",
  "admin_email": "your-email@example.com",
  "main_domains": [
    "example.com"
  ],
  "subdomains": [
    "sub.example.com"
  ],
  "subdirectory_domains": [
    "example.com/subdirectory"
  ],
  "rclone_remotes": [
    {
      "client_id": "YOUR_GOOGLE_DRIVE_API_CLIENT_ID",
      "client_secret": "YOUR_GOOGLE_DRIVE_API_CLIENT_SECRET",
      "remote_name": "server_backup"
    }
  ],
  "redis_max_memory": "1"
}
```

### 3. Run the Main Toolkit

The main script provides access to all tools through a unified menu:

```bash
sudo bash main.sh
```

## Available Tools

### Main Menu Options

1. **Install LAMP Stack + WordPress** - Complete WordPress installation
2. **Backup/Restore** - WordPress and PostgreSQL backup operations
3. **Install Apache + SSL Only** - Web server setup without WordPress
4. **Miscellaneous Tools** - System utilities and disk management
5. **MySQL Remote Access** - Database remote access configuration
6. **Troubleshooting** - WordPress diagnostics and repair tools
7. **Rclone Management** - Cloud backup synchronization
8. **Configure Redis** - Memory caching setup
9. **Remove Websites & Databases** - Clean uninstallation
10. **Remove Orphaned Databases** - Database cleanup
11. **Fix Apache Configs** - Configuration repair
12. **System Status Check** - Comprehensive system overview

### Individual Script Usage

Each tool can also be run independently:

```bash
# Backup and restore operations
sudo bash backup_restore.sh

# System troubleshooting
sudo bash troubleshooting.sh

# MySQL remote access setup
sudo bash mysql_remote.sh

# Disk space management and system utilities
sudo bash miscellaneous.sh

# Cloud backup management
sudo bash rclone.sh
```

## New Features in Latest Update

### Disk Space Management
*   **Disk Usage Analysis**: Detailed system resource monitoring
*   **Directory Size Analysis**: Find largest directories consuming space
*   **File Size Analysis**: Identify largest files on the system
*   **System Log Cleanup**: Automated log rotation and cleanup
*   **Package Cache Cleanup**: APT cache management and optimization
*   **Temporary File Cleanup**: Safe removal of temporary files
*   **Full System Cleanup**: Comprehensive cleanup with before/after comparison

### Enhanced Menu System
*   **Reorganized Main Menu**: Streamlined access to all tools
*   **Improved Navigation**: Better organization of features
*   **Script Integration**: Seamless switching between different tools

### Security Improvements
*   **Sensitive Data Protection**: config.json excluded from version control
*   **Secure Credential Handling**: Improved password management
*   **Permission Hardening**: Enhanced file security settings

## WordPress Installation Types

### Main Domain Installation
Install WordPress directly on your primary domain (e.g., `example.com`)

### Subdomain Installation  
Install WordPress on a subdomain (e.g., `blog.example.com`)

### Subdirectory Installation
Install WordPress in a subdirectory (e.g., `example.com/blog`)

## Cloud Backup with rclone

### Setup Google Drive API
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable Google Drive API
4. Create OAuth 2.0 credentials
5. Add your credentials to `config.json`

### Usage
```bash
sudo bash rclone.sh
```

Features:
*   Multi-remote management
*   Interactive file browsing and restoration
*   Automated backup synchronization
*   Size monitoring and analysis

## Troubleshooting

### Common Issues

**Permission Problems**: Use the troubleshooting script to fix file permissions
```bash
sudo bash troubleshooting.sh
```

**SSL Certificate Issues**: Check domain DNS and use the SSL conflict detection feature

**Database Connection Problems**: Use MySQL remote access tool to verify configuration

**Disk Space Issues**: Use the disk management tools in miscellaneous utilities

### Log Files
*   Apache errors: `/var/log/apache2/error.log`
*   WordPress debug: `/var/www/your-site/wp-content/debug.log`
*   System logs: `/var/log/syslog`

## Security Best Practices

*   Keep `config.json` secure and never commit it to version control
*   Regularly update WordPress core, themes, and plugins
*   Use strong passwords for all accounts
*   Enable firewall and limit SSH access
*   Regular backup verification and testing
*   Monitor system logs for suspicious activity

## File Structure

```
install_wordpress_on_lamp/
├── main.sh                 # Main menu and WordPress installation
├── backup_restore.sh       # Backup and restore operations
├── troubleshooting.sh      # WordPress diagnostics and repair
├── mysql_remote.sh         # MySQL remote access configuration
├── miscellaneous.sh        # System utilities and disk management
├── rclone.sh              # Cloud backup management
├── sample_config.json     # Configuration template
├── config.json            # Your configuration (create from sample)
├── .gitignore             # Git ignore rules
├── README.md              # This file
└── INSTRUCTIONS.md        # Detailed documentation
```

## Full Documentation

For detailed instructions on every feature, troubleshooting guides, and security best practices, please read [INSTRUCTIONS.md](INSTRUCTIONS.md).

## Contributing

We welcome contributions! Please feel free to:
*   Submit bug reports and feature requests
*   Create pull requests for improvements
*   Share your experience and suggestions
*   Help improve documentation

## License

This project is released under the MIT License. See the LICENSE file for details.

## Support

For support and questions:
*   Create an issue on GitHub
*   Check the troubleshooting section
*   Review the detailed documentation in INSTRUCTIONS.md

---

**Note**: Always test scripts in a development environment before using in production. Regular backups are essential for any production website.
