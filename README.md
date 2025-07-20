# WordPress & Server Management Toolkit

A complete command-line toolkit for WordPress installation, management, and maintenance on Ubuntu servers with LAMP stack.

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git
```
```bash
cd install_wordpress_on_lamp
```
```bash
cp sample_config.json config.json
```
```bash
nano config.json  # Add your settings
```

### 2. Run Main Script

```bash
sudo bash run.sh
```

### 3. Prerequisites

* Ubuntu 18.04+ server
* Root/sudo access
* Domain pointing to your server
* Internet connection

## Main Features

* **WordPress Installation** - Complete LAMP stack + WordPress setup
* **Backup & Restore** - Website and database backup with cloud sync
* **System Management** - SSL, Apache, MySQL, PHP configuration
* **Troubleshooting** - WordPress diagnostics and repair tools
* **Cloud Backup** - Google Drive integration with rclone
* **Security Tools** - Firewall, fail2ban, SSH management

## Individual Scripts

Run tools independently:

```bash
sudo bash backup_restore.sh    # Backup operations
sudo bash troubleshooting.sh   # WordPress diagnostics
sudo bash rclone.sh           # Cloud backup management
sudo bash miscellaneous.sh    # System utilities
```

## Configuration

Edit `config.json` with your settings:

```json
{
  "mysql_root_password": "your_password",
  "admin_email": "your@email.com",
  "main_domains": ["example.com"],
  "rclone_remotes": [{
    "client_id": "google_drive_client_id",
    "client_secret": "google_drive_client_secret",
    "remote_name": "server_backup"
  }],
  "redis_max_memory": "1"
}
```

## Installation Types

* **Main Domain** - `example.com`
* **Subdomain** - `blog.example.com`
* **Subdirectory** - `example.com/blog`

## Cloud Backup Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create project → Enable Google Drive API → Create OAuth credentials
3. Add credentials to `config.json`
4. Use `sudo bash rclone.sh` for cloud backup management

## Common Issues

* **Permissions** - `sudo bash troubleshooting.sh`
* **SSL Problems** - Check DNS, use SSL conflict detection
* **Database Issues** - Use MySQL remote access tools
* **Disk Space** - Use disk management utilities

## Security Tips

* Secure `config.json` (never commit to git)
* Update WordPress regularly
* Use strong passwords
* Enable firewall and limit SSH
* Regular backup testing

## Support

* **Full Documentation** - See [INSTRUCTIONS.md](INSTRUCTIONS.md)
* **Issues** - Create GitHub issue
* **Testing** - Always test in development first

---

**⚠️ Important**: Test in development environment before production use. Keep regular backups.
