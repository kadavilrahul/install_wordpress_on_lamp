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

### 5. Optionally Install Rclone to transfer backups to cloud like google drive

Read file INSTALL_RCLONE.md

### 6. Backup and restore Wordpress installation

Create backups in the form of tar files to /website_backups folder

```bash
bash backup_wordpress.sh
```

Restore backups from tar files located in /website_backups folder

```bash
bash restore_wordpress.sh
```
### 7. Optionally Backup and restore HTML installation (Postgres database)
(Note: Files located in wordperess root directory are automatically backed up and restored through full wordpress backup and restore function)

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

## Troubleshooting



## License

This script is released under the MIT License.


## Contributions

Feel free to submit pull requests and report issues!
