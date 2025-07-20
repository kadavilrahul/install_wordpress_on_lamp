# WordPress Master - User Guide


## Main Menu Options

1. **Install LAMP + WordPress** - Complete WordPress setup
2. **Backup/Restore** - Website and database backup operations  
3. **Apache + SSL Setup** - Web server with SSL certificates
4. **System Tools** - Utilities and disk management
5. **MySQL Remote Access** - Database remote connection setup
6. **Troubleshooting** - WordPress diagnostics and fixes
7. **Cloud Backup (Rclone)** - Google Drive synchronization
8. **Configure Redis** - Memory caching setup
9. **Remove Sites** - Clean website removal
10. **Database Cleanup** - Remove orphaned databases
11. **Fix Apache** - Repair Apache configurations
12. **System Status** - Comprehensive health check

## WordPress Installation Types

### Main Domain (example.com)
- WordPress at domain root
- SSL for domain.com and www.domain.com
- Redis caching enabled

### Subdomain (blog.example.com)
- WordPress on subdomain
- Separate database
- DNS requirement: A record pointing to server

### Subdirectory (example.com/blog)
- WordPress in folder
- Shares main domain SSL
- Access: https://example.com/blog

## Backup System

### WordPress Backup
- Auto-scans `/var/www/` for WordPress sites
- WP-CLI database export
- Excludes cache directories
- Stores in `/website_backups/`
- 7-day retention

### PostgreSQL Backup
- Compressed dumps using `pg_dump -Fc`
- 30-day retention
- Automatic database creation

### Cloud Backup (Rclone)
- Google Drive integration
- Interactive file browser
- Remote folder selection
- Progress monitoring

## System Management

### PHP Optimization
- upload_max_filesize: 64M
- post_max_size: 64M
- memory_limit: 512M
- max_execution_time: 300

### Redis Setup
- Memory limit configuration
- Service management
- WordPress integration

### Security Tools
- UFW firewall (ports 22, 80, 443, 3306)
- Fail2ban brute force protection
- SSH root access control
- SSL certificate management

## Database Management

### MySQL Commands
```bash
# Access MySQL
sudo mysql -u root -p

# Show databases
SHOW DATABASES;

# Check users
SELECT User FROM mysql.user;

# Check WordPress URLs
SELECT option_name, option_value FROM wp_options 
WHERE option_name IN ('siteurl', 'home');
```

### Remote Database Access
- Bind address configuration
- User privilege management
- Firewall port opening
- Connection testing

## Troubleshooting

### Common WordPress Issues

**wp-admin Not Loading**
```bash
# Deactivate plugins
wp plugin deactivate --all --allow-root --path=/var/www/site

# Check debug log
tail -n 20 /var/www/site/wp-content/debug.log
```

**Permission Problems**
```bash
# Fix ownership
sudo chown -R www-data:www-data /var/www/site

# Set permissions
sudo find /var/www/site -type d -exec chmod 755 {} \;
sudo find /var/www/site -type f -exec chmod 644 {} \;
```

**Redis Connection Errors**
```bash
# Remove Redis cache
rm -f /var/www/site/wp-content/object-cache.php
```

### Service Management
```bash
# Check service status
sudo systemctl status apache2
sudo systemctl status mysql
sudo systemctl status php8.3-fpm

# Restart services
sudo systemctl restart apache2
sudo systemctl restart mysql
```

### Log Locations
- Apache: `/var/log/apache2/error.log`
- WordPress: `/var/www/site/wp-content/debug.log`
- MySQL: `/var/log/mysql/error.log`
- System: `/var/log/syslog`

## Cloud Backup Setup

### Google Drive API
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create project → Enable Google Drive API
3. Create OAuth 2.0 credentials (Desktop app)
4. Download credentials JSON
5. Add to config.json

### Rclone Configuration
```bash
sudo bash rclone.sh
# Select: Configure or Re-Configure Remote
# Follow browser authentication
```

### Manual Commands
```bash
# Upload backups
rclone copy /website_backups "server_backup:" --progress

# Download backups
rclone copy "server_backup:backups/" /website_backups --progress

# Check sizes
rclone size "server_backup:"
```

## Security Best Practices

### Initial Setup
- Change default passwords
- Configure firewall (UFW)
- Install fail2ban
- Disable root SSH after setup

### WordPress Security
- Regular updates (core, plugins, themes)
- Strong passwords
- Security plugins (Wordfence, iThemes)
- Hide WordPress version

### SSL Management
```bash
# Test renewal
sudo certbot renew --dry-run

# Manual renewal
sudo certbot renew
```

### File Permissions
```bash
# WordPress standard permissions
sudo chown -R www-data:www-data /var/www/site
sudo find /var/www/site -type d -exec chmod 755 {} \;
sudo find /var/www/site -type f -exec chmod 644 {} \;
sudo chmod 600 /var/www/site/wp-config.php
```

## Configuration Files

### config.json
```json
{
  "mysql_root_password": "secure_password",
  "admin_email": "admin@example.com",
  "main_domains": ["example.com"],
  "subdomains": ["blog.example.com"],
  "subdirectory_domains": ["example.com/blog"],
  "rclone_remotes": [{
    "client_id": "google_drive_client_id",
    "client_secret": "google_drive_client_secret", 
    "remote_name": "server_backup"
  }],
  "redis_max_memory": "2"
}
```

### wp-config.php Additions
```php
// Performance
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');

// Redis
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);

// Debug (disable in production)
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
```

## Maintenance Tasks

### Daily
- Check system status
- Monitor error logs
- Verify backup completion

### Weekly
- Update WordPress core/plugins
- Review security logs
- Test backup restoration

### Monthly
- System package updates
- Security audit
- Performance optimization
- Clean old backups

## Advanced Features

### Multiple Site Management
- Automatic WordPress detection
- Batch operations
- Site-specific configurations
- Centralized backup management

### System Monitoring
- Disk usage analysis
- Service health checks
- Resource monitoring
- Error log analysis

### Automation Options
- Cron job setup for backups
- Automated updates
- Log rotation
- Cleanup scripts

## Support & Troubleshooting

### Getting Help
1. Built-in troubleshooting menu
2. System status check
3. Log file analysis
4. GitHub issues

### Common Error Solutions
- **SSL Certificate Errors**: Check DNS, run conflict detection
- **Database Connection**: Verify credentials, check service status
- **File Permission Issues**: Use built-in permission repair
- **Plugin Conflicts**: Deactivate all, reactivate one by one
- **Disk Space Full**: Use disk cleanup utilities

### Emergency Recovery
- Access via SSH
- Use troubleshooting script
- Check service status
- Review error logs
- Restore from backup

---

**Important**: Always test in development environment before production use. Keep regular backups and monitor system health.