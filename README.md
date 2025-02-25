# WordPress Auto-Installer Script on LAMP stack

## Overview

This Bash script automates the installation of a LAMP stack, WordPress, and phpMyAdmin on an Ubuntu server. It performs the following tasks:

* Updates system packages
* Installs Apache, MySQL, PHP, and required PHP extensions
* Configures and enables Apache and MySQL services
* Downloads and configures WordPress
* Sets up a MySQL database and user for WordPress
* Configures WordPress settings
* Installs and links phpMyAdmin

## Prerequisites

Before running the script, ensure that you:

* Have a fresh Ubuntu installation
* Have sudo privileges
* Update the script variables according to your domain and database credentials

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
Modify redis server memory in the script.
Execute the script with:

```bash
bash install_on_maindomain.sh
```
```bash
bash install_on_subdomain.sh
```

### 4. Open your domain/subdomain on browser and complete wordpress installtion

## Features

* Fully automated WordPress setup
* Secure MySQL database and user creation
* Configures Apache and PHP for optimal performance
* Sets correct file permissions for WordPress
* Installs and configures phpMyAdmin

## Troubleshooting

Ensure MySQL service is running before executing the script:
```bash
sudo systemctl start mysql
```

Check Apache status if WordPress does not load:
```bash
sudo systemctl status apache2
```

Verify MySQL credentials if the database setup fails.

If phpMyAdmin is not accessible, check the symlink:
```bash
ls -l /var/www/html/phpmyadmin
```

## License

This script is released under the MIT License.


## Contributions

Feel free to submit pull requests and report issues!
