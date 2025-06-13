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

### 3. Run these scripts to install Wordpress on LAMP

For installing wordpress on main domain like your_website.com

```bash
bash install_on_maindomain.sh
```
For installing wordpress on subdomain like test.your_website.com

```bash
bash install_on_subdomain.sh
```
For installing wordpress onsubdirectory like your_website.com/wordpress
(Note that many plugins will not function properly in this setup)

```bash
bash install_on_subdirectory.sh
```

### For installing only apache and SSL

```bash
cd install_apache_and_ssl_only
```

```bash
bash maindomain.sh
```

```bash
bash subdomain.sh
```

### 4. Complete wordpress installtion on browser

* Enter your domain/subdomain/subdirectory URL on browser 
* Enter site title
* Enter username
* Enter password
* Enter admin email ID

### 5. Optionally Install Rclone to transfer backups to cloud like google drive and vice versa

Read below file for rclone installation
```
INSTALL_RCLONE.md
```

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

### 7. Modify redis max memory

```bash
bash redis.sh
```

```bash
redis-cli info memory | grep -E "(used_memory_human|maxmemory_human)"
```

### 8. Miscellaneous tools

- Create SWAP memory, 
- Modify php max execution time, max memory, upload file size, post max size, max input time
- Uninterrupted fire wall UFW
- Fail2ban
- Check php information at your_website.com/info.php

```bash
bash miscellaneous.sh
```

```bash
bash adjust_php.sh
```

### 9. Modify time zone

Check your zone
```bash
timedatectl list-timezones
```
Change timezone. Replace Asia/Kolkata with yours
```bash
sudo timedatectl set-timezone Asia/Kolkata
```
Verify change
```bash
timedatectl status
```

### 10. Cron jobs for automatic execution

- Renew SSL every month
```bash
(crontab -l 2>/dev/null; echo "00 02 * */1 0 python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew --quiet") | crontab -
```

Backup websites

```bash
(crontab -l 2>/dev/null; echo "00 01 */1 * * bash install_wordpress_on_lamp/backup_wordpress.sh") | crontab -
```

Transfer files to google drive through rclone:

Change remote_name:/path/to/folder to actual remote name and path of cloud drive

```bash
(crontab -l 2>/dev/null; echo "00 03 */1 * * /usr/bin/rclone copy /website_backups remote_name:/path/to/folder/ --log-file=/var/log/rclone.log && find /website_backups -type f -exec rm -f {} \;") | crontab -
```

- Verify cron job
```bash
crontab -l
```

## Optional Installations:

### 1. Disable or enable root login for server security

- Create a new user with root privileges first 
  You’ll be prompted to set a password and (optionally) fill in user details.

```bash
sudo adduser newusername
```
- Add the User to the sudo Group. This gives the user root privileges via sudo.
```bash
sudo usermod -aG sudo newusername
```
- Open a new terminal and try logging in:
```bash
ssh newusername@your_ip_address
```
Then test sudo:
```bash
sudo whoami
```
If you need to login to new user from root
```bash
su newusername
```
Now run ssh control script
Disable root login
```bash
bash /root/install_wordpress_on_lamp/ssh_control.sh disable
```
Login to another user:
```bash
ssh newusername@your_ip_address
```
Enter root
```bash
sudo -i
```
Enable root login
```bash
bash /root/install_wordpress_on_lamp/ssh_control.sh enable
```

### 2. phpmyadmin

```bash
bash php_myadmin.sh
```

### 3. Backup and restore HTML installation (Postgres database)
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

### 4. Modify hosts file on local computer
Read file to modify hosts file so that installations can be accessed on any server.
```
other_tools/modify_hosts_file.md
```

### 5. Configure Apache to serve both WordPress and static HTML pages without conflicts 
Read file to modify your Apache configuration to serve static HTML pages stored in /var/www/your_website.com/products while keeping WordPress functional
```
other_tools/exclude_static_folders.md
```

### 6. Serve index.html pages first and then index.php pages 
Read file to modify your Apache configuration to serve static HTML pages stored in /var/www/your_website.com/products while keeping WordPress functional
```
other_tools/serve_index_html.md
```

## License

This script is released under the MIT License.

## Contributions

Feel free to submit pull requests and report issues!
