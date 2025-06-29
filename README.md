# WordPress & Backup Management Toolkit

This repository provides a powerful command-line toolkit for installing, managing, and backing up WordPress websites on a LAMP stack. It also includes a robust, multi-site backup solution using rclone to sync your website data to Google Drive.

## Features

*   **WordPress Installer**: A menu-driven script (`wordpress_master/install_min.sh`) to install and manage WordPress on a LAMP stack.
*   **Multi-Site Backups**: A sophisticated script (`wordpress_master/rclone.sh`) to manage backups for multiple websites to Google Drive.
*   **Automated Configuration**: The rclone script is fully automated and pulls settings from a central `config.json` file.
*   **Cron Job Management**: Easily set up and manage daily cron jobs for automated backups.
*   **Utilities**: A collection of scripts for server management, including PHP configuration, SSH security, and more.

## Prerequisites

*   A fresh Ubuntu server.
*   Root or `sudo` privileges.
*   A domain name pointed to your server's IP address.

## Quick Start

### 1. Clone the Repository

Clone this repository to your server.

```bash
git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git
cd install_wordpress_on_lamp
```

### 2. Configure Backups (rclone)

Before running the backup script, you need to configure your Google Drive credentials.

1.  **Copy the Sample Config**:
    ```bash
    cp wordpress_master/sample_config.json wordpress_master/config.json
    ```

2.  **Edit `config.json`**:
    Open `wordpress_master/config.json` and replace the placeholder values with your own Google Cloud credentials and desired remote names.

    ```json
    {
      "rclone_remotes": [
        {
          "client_id": "YOUR_GOOGLE_DRIVE_API_CLIENT_ID",
          "client_secret": "YOUR_GOOGLE_DRIVE_API_CLIENT_SECRET",
          "remote_name": "my_first_website_remote"
        },
        {
          "client_id": "YOUR_GOOGLE_DRIVE_API_CLIENT_ID",
          "client_secret": "YOUR_GOOGLE_DRIVE_API_CLIENT_SECRET",
          "remote_name": "my_second_website_remote"
        }
      ]
    }
    ```
    > **Note**: For instructions on how to get your Google Drive API credentials, please refer to the official rclone documentation.

### 3. Run the Tools

The main tools are located in the `wordpress_master` directory.

#### WordPress Management

The `install_min.sh` script is a comprehensive, menu-driven tool for all WordPress and server management tasks.

```bash
sudo ./wordpress_master/install_min.sh
```

From its menu, you can:
*   Install a new WordPress site (on a main domain, subdomain, or subdirectory).
*   Backup and restore websites locally.
*   Install phpMyAdmin.
*   Adjust PHP and Redis settings.
*   And much more.

#### Google Drive Backups (rclone)

The `rclone.sh` script manages syncing your backups to Google Drive. It uses the `config.json` you created.

```bash
sudo ./wordpress_master/rclone.sh
```

**Main Menu:**
*   **Install rclone Package**: A one-time setup to install rclone and jq on your system.
*   **Manage a Website Remote**: Enter the remote management menu.
*   **Uninstall rclone Package**: Completely removes rclone and all its configurations.

**Remote Management Menu:**
After selecting a remote to manage, you can:
*   **Configure or Re-Configure Remote**: Authenticate rclone with your Google account (a one-time, browser-based step for each remote).
*   **Sync from Server TO Google Drive**: Upload your local `/website_backups` to Google Drive.
*   **Sync FROM Google Drive to Server**: Restore backups from Google Drive to your server.
*   **Setup Daily Backup Cron Job**: Automate daily backups to Google Drive.
*   **Delete This Remote & Its Cron Job**: Clean up a specific remote's configuration.

## Security

The `wordpress_master/config.json` file contains sensitive credentials. This file is already included in the `.gitignore` file to prevent it from being accidentally committed to version control.

## Other Scripts

The `custom_script` directory contains standalone scripts for various tasks. While most of their functionality is integrated into the main `install_min.sh` tool, you can run them individually if needed.

## License

This script is released under the MIT License.

## Contributions

Feel free to submit pull requests and report issues!
