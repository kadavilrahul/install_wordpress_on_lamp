# WordPress & Backup Management Toolkit

This repository provides a powerful command-line toolkit for installing, managing, and backing up WordPress websites on a LAMP stack. It also includes a robust, multi-site backup solution using rclone to sync your website data to Google Drive.

## Features

*   **Comprehensive WordPress Management**: A menu-driven script (`main.sh`) to install and manage WordPress on a LAMP stack, including main domain, subdomain, and subdirectory installations.
*   **Cloud Backups**: A sophisticated script (`rclone.sh`) to manage backups for multiple websites to Google Drive.
*   **Automated Configuration**: The rclone script is fully automated and pulls settings from a central `config.json` file.
*   **Cron Job Management**: Easily set up and manage daily cron jobs for automated backups.
*   **System Management**: Adjust PHP settings, manage SSH security, and use various system utilities.
*   **Database Tools**: Includes phpMyAdmin installation and PostgreSQL backup/restore capabilities.
*   **Detailed Documentation**: For a full guide, see [INSTRUCTIONS.md](INSTRUCTIONS.md).

## Prerequisites

*   A fresh Ubuntu server (18.04+).
*   Root or `sudo` privileges.
*   A domain name pointed to your server's IP address.

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/kadavilrahul/install_wordpress_on_lamp.git
cd install_wordpress_on_lamp
```

### 2. Run the Main Toolkit

The `main.sh` script is a comprehensive, menu-driven tool for all WordPress and server management tasks.

```bash
sudo ./main.sh
```

From its menu, you can:
*   Install a new WordPress site.
*   Backup and restore websites locally.
*   Install phpMyAdmin.
*   Adjust PHP and Redis settings.
*   And much more.

### 3. Configure and Use Cloud Backups

The `rclone.sh` script manages syncing your backups to Google Drive.

#### Configuration

1.  **Copy the Sample Config**:
    ```bash
    cp sample_config.json config.json
    ```

2.  **Edit `config.json`**:
    Open `config.json` and replace the placeholder values with your own Google Cloud credentials and desired remote names.

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
    > **Note**: For instructions on how to get your Google Drive API credentials, please refer to the official rclone documentation or see the detailed steps in [INSTRUCTIONS.md](./INSTRUCTIONS.md#cloud-backup-with-rclone).

#### Usage

Run the script to access the backup management menu.

```bash
sudo ./rclone.sh
```

From its menu, you can:
*   Install rclone.
*   Configure remotes and authenticate with Google Drive.
*   Sync backups to and from Google Drive.
*   Set up automated daily cron jobs.
*   Remove remotes and their cron jobs.

## Security

The `config.json` file contains sensitive credentials. This file is already included in the `.gitignore` file to prevent it from being accidentally committed to version control.

## Full Documentation

For detailed instructions on every feature, troubleshooting, and security best practices, please read [INSTRUCTIONS.md](INSTRUCTIONS.md).

For future feature ideas and a competitive analysis, see [RECOMMENDATIONS.md](RECOMMENDATIONS.md).

## License

This script is released under the MIT License.

## Contributions

Feel free to submit pull requests and report issues!
