# WordPress Auto-Installer Script on LAMP stack

## Overview

This Bash script automates the installation of a LAMP stack, WordPress, and phpMyAdmin on an Ubuntu server. It performs the following tasks:

* Updates system packages
* Asks for domain name, subdomain name or subdirectory name
* Asks for email, MySQl password, Redis memory to be allocated
* Installs Apache, MySQL, PHP, and required PHP extensions
* Configures and enables Apache and MySQL services
* Downloads and configures WordPress
* Sets up a MySQL database and user for WordPress
* Configures WordPress settings
* Installs other related services

## Prerequisites

Before running the script, ensure that you:

* Have a fresh Ubuntu installation
* Have sudo privileges

## Installation

### 1. Point the DNS correctly
Go to your domain registrar and point th DNS to your server for domain, www, subdomain as needed

### 2.  Download the Script
Clone the repository or download the script manually:

```bash
git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git
```
```bash
cd install_wordpress_on_lamp
```

### 3. Run the Script

Execute the script with:

For installing wordpress on main domain like example.com

```bash
bash install_on_maindomain.sh
```
For installing wordpress onmain domain like example.com

```bash
bash install_on_subdomain.sh
```
For installing wordpress onsubdirectory like example.com/wordpress
(Note that many plugins will not function properly in this setup)

```bash
bash install_on_subdirectory.sh
```

### 4. Complete wordpress installtion on browser

* Enter your domain/subdomain/subdirectory URL on browser 
* Enter site title
* Enter username
* Enter password
* Enter admin email ID

### 5. Optionally Install Rclone to transfer backups to cloud like google drive and vice versa

Read file INSTALL_RCLONE.md

### 6. Backup and restore Wordpress installation

To create backups in the form of tar files to /website_backups folder

The scripts use the following configuration variables:

```bash
WWW_PATH="/var/www"                    # Path to website root directories
BACKUP_DIR="/website_backups"          # Main backup directory
WEB_BACKUP_DIR="${BACKUP_DIR}/web"     # Website backups location
PG_BACKUP_DIR="${BACKUP_DIR}/postgresql" # PostgreSQL backups location
BACKUP_RETENTION_DAYS=7                # Number of days to keep backups
DB_CREDENTIALS_FILE="/etc/website_db_credentials.conf" # Database credentials file
```

```bash
bash backup_wordpress.sh
```
Execute command from file INSTALL_RCLONE.md to transfer backups from cloud to server
or 
Trasnfer backup from an older server

```bash
bash transfer_backup_from_old_server.sh
```

Restore backups from tar files located in /website_backups folder

```bash
bash restore_wordpress.sh
```

### 7. Troubleshooting

1. If wp-admin fails to load after restoration or on other occassion
   a) Deactivate all plugins via WP CLI
   ```bash
   wp plugin deactivate --all --allow-root --path=/var/www/your_website.com
   ```
   b) Enter output to chatgpt if error persits
   C) Manually Remove the Broken Plugin
   ```bash
   rm -rf /var/www/your_website.com/wp-content/plugins/plugin_name
   ```
   d) Reactivate the plugins

2. Check if Apache, MySQL , PHP and FPM are running
   ```bash
   Status
   sudo systemctl status apache2
   Restart
   sudo systemctl restart apache2
   ```

   ```bash
   Status
   sudo systemctl status mysql
   Restart
   sudo systemctl restart mysql
   ```
   
   ```bash
   php --version
   Status
   systemctl status php8.3-fpm
   Restart
   systemctl restart php8.3-fpm
   ```

3. Check free memory
   RAM
   ```bash
   free -h
   ```
   Disk Space
   ```bash
   df -h
   ```
   Folder Space
   ```bash
   du -sh /var/
   ```
   ```bash
   du -sh /var/lib
   ```
   ```bash
   du -sh /var/lib/mysql
   ```
   
5. Check Apache error logs

   ```bash
   tail -n 20 /var/log/apache2/error.log
   ```
   Replace yourdomain.com with actual domain name in below command
   ```bash
   tail -n 50 /var/log/apache2/error_yourdomain.com.log
   ```

6. Error establishing a Redis connection
   To disable Redis, delete the object-cache.php file in the /wp-content/ directory.

### 8. Optionally Backup and restore HTML installation (Postgres database)
(Note: Files located in wordperess root directory are automatically backed up and restored through full wordpress backup and restore function)

The scripts use the following configuration variables:

```bash
PG_BACKUP_DIR="${BACKUP_DIR}/postgresql" # PostgreSQL backups location
```
The script expects PostgreSQL database credentials in the following format:

```
Domain: example.com
Database: example_db
```

```bash
bash backup_postgres.sh
```
```bash
bash restore_postgres.sh
```

## Features

* Fully automated WordPress setup
* Secure MySQL database and user creation
* Configures Apache and PHP for optimal performance
* Sets correct file permissions for WordPress
* Installs and configures phpMyAdmin

## License

This script is released under the MIT License.


## Contributions

Feel free to submit pull requests and report issues!
