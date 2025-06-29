# WordPress Master - Comprehensive LAMP Stack Management Tool

## Overview

WordPress Master is a comprehensive, interactive installation and management script that combines all the functionality from the custom_script collection into a single, user-friendly tool. It provides a complete LAMP stack setup with WordPress installation, backup/restore capabilities, and system management features.

## Features

### Installation & Setup
- **Complete LAMP Stack Installation** - Automated Apache, MySQL, PHP setup
- **WordPress Installation Types**:
  - Main Domain (example.com)
  - Subdomain (blog.example.com) 
  - Subdirectory (example.com/blog)
- **Apache + SSL Only** - Domain setup with SSL certificates
- **phpMyAdmin Installation** - Database management interface

### Backup & Restore
- **WordPress Backup** - Automated backup of all WordPress sites
- **WordPress Restore** - Interactive restoration from backups
- **PostgreSQL Backup** - Database backup functionality
- **PostgreSQL Restore** - Database restoration
- **Transfer Backups** - Move backups between servers

### System Management
- **PHP Configuration** - Optimize PHP settings for WordPress
- **Redis Configuration** - Setup and configure Redis caching
- **SSH Security Management** - Enable/disable root SSH access
- **System Utilities** - UFW firewall, Fail2ban, swap setup

### Troubleshooting & Tools
- **Troubleshooting Guide** - Built-in help for common issues
- **MySQL Commands Guide** - Database management commands
- **System Status Check** - Comprehensive system health check

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/install_wordpress_on_lamp/wordpress_master/main.sh
```

2. Run as root:
```bash
bash main.sh
```

## Usage

The script provides an interactive menu system. Simply run the script and follow the prompts:


### Menu Options

1. **Install Complete LAMP Stack + WordPress** - Full WordPress setup
2. **Install Apache + SSL Only** - Basic web server setup
3. **Install phpMyAdmin** - Database management tool
4. **Backup WordPress Sites** - Create backups of all WordPress installations
5. **Restore WordPress Sites** - Restore from existing backups
6. **Backup PostgreSQL Database** - PostgreSQL backup functionality
7. **Restore PostgreSQL Database** - PostgreSQL restoration
8. **Transfer Backups from Old Server** - Migrate backups between servers
9. **Adjust PHP Configuration** - Optimize PHP settings
10. **Configure Redis** - Setup Redis caching
11. **SSH Security Management** - Manage SSH access
12. **System Utilities** - Install security and system tools
13. **Troubleshooting Guide** - Help with common issues
14. **MySQL Database Commands** - Database management guide
15. **System Status Check** - Check system health
16. **Exit** - Close the application

## Configuration

The script automatically creates a configuration file at `config.sh` to store settings between sessions. This includes:

- Database credentials
- Email settings
- Redis configuration
- Installation history

## Requirements

- Ubuntu 18.04+ (tested on Ubuntu 20.04/22.04)
- Root access (sudo)
- Internet connection
- Minimum 5GB free disk space

## Features Comparison

| Feature | custom_script | wordpress_master |
|---------|---------------|------------------|
| Installation Types | Manual scripts | Interactive menu |
| Automation Level | Manual execution | Fully automated |
| Error Handling | Basic | Advanced with rollback |
| User Interface | Command-line scripts | Interactive menu system |
| Configuration | None | Persistent config file |
| Backup/Restore | Separate scripts | Integrated functionality |
| Troubleshooting | Separate docs | Built-in guides |

## Advanced Usage

### Unattended Installation
For automated deployments, you can pre-configure settings in `config.sh`:

```bash
# Pre-configure settings
cat > config.sh << EOF
DB_ROOT_PASSWORD="your_secure_password"
ADMIN_EMAIL="admin@example.com"
REDIS_MAX_MEMORY="2"
EOF

# Run specific function
sudo ./install.sh
```

### Backup Automation
Set up automated backups with cron:

```bash
# Add to crontab for daily backups at 2 AM
0 2 * * * /path/to/wordpress_master/install.sh backup_wordpress
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

2. **MySQL Connection Issues**
   - Check if MySQL is running: `systemctl status mysql`
   - Verify credentials in config.sh

3. **SSL Certificate Failures**
   - Ensure domain points to your server
   - Check firewall settings (ports 80, 443)

4. **WordPress Installation Issues**
   - Check Apache error logs: `/var/log/apache2/error.log`
   - Verify file permissions: `chown -R www-data:www-data /var/www/`

### Log Files

- Main log: `/var/log/wordpress_master_YYYYMMDD_HHMMSS.log`
- Apache logs: `/var/log/apache2/`
- MySQL logs: `/var/log/mysql/`

## Security Considerations

- Change default passwords immediately after installation
- Keep the system updated: `apt update && apt upgrade`
- Configure UFW firewall (option 12 in menu)
- Install Fail2ban for SSH protection
- Disable root SSH login after setup (option 11)

## Contributing

This script consolidates functionality from the custom_script collection. To contribute:

1. Test thoroughly on clean Ubuntu installations
2. Follow the existing code style and error handling patterns
3. Update documentation for new features
4. Ensure backward compatibility

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
1. Check the built-in troubleshooting guide (menu option 13)
2. Review log files for detailed error information
3. Consult the MySQL commands guide (menu option 14)
4. Run system status check (menu option 15)

## Changelog

### Version 1.0
- Initial release combining all custom_script functionality
- Interactive menu system
- Comprehensive error handling
- Built-in troubleshooting guides
- Configuration persistence
- Advanced backup/restore capabilities