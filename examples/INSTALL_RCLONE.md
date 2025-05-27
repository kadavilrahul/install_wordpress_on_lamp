# Rclone Google Drive Backup Setup

This guide provides instructions on how to install and configure rclone for backing up your website to Google Drive.

## Prerequisites

*   A server with root access
*   A Google Cloud account

## Installation

1.  **Enter root user:**

    ```bash
    sudo bash
    ```

2.  **Install rclone:**

    ```bash
    sudo apt update
    sudo apt install rclone
    ```

## Configuration

1.  **Run rclone config:**

    ```bash
    rclone config
    ```

2.  **Create a new remote:**

    *   Select `n` for new remote.
    *   Name it `my_remote`.
        *   Select Google Drive (option `13` or `18` depending on your rclone version).
        *   For `client_id` and `client_secret`, follow the instructions to create your own OAuth 2.0 credentials.
        *   Select `1` for full access to all files.
    *   When the browser opens, use the **SECOND** link if multiple appear.
    *   Log in with your Google account and authorize rclone.
    *   Select `y` to confirm the configuration is correct.
    *   Select `q` to quit config.

    **Important:** Run this configuration from a desktop session with Chrome installed to avoid port conflict errors.

## Google Cloud Console Credentials

1.  **Log in to Google Cloud Console:**

    Go to <https://console.cloud.google.com/>

2.  **Create a Project:**

    *   Click on the project drop-down and select "New Project".
    *   Give your project a name (e.g., "rclone-active") and click "Create".

3.  **Enable the Google Drive API:**

    *   With your new project selected, go to the Google API Library.
    *   Search for "Google Drive API" and click on it.
    *   Click "Enable".

4.  **Create OAuth 2.0 Credentials:**

    *   Go to the Credentials page in the Google Cloud Console.
    *   Click "Create Credentials" and select "OAuth client ID".
    *   If prompted, configure the consent screen by providing necessary information like application name, email, and scopes.
    *   Click "Create Credentials" and select "OAuth client ID" again.
    *   For the application type, choose "Desktop app" and click "Create".
    *   After creating the credentials, you’ll be presented with a client ID and client secret.
    *   Click "Download" to save the credentials as a JSON file.

    Example Credentials:

    ```text
    Client ID: your_client_id
        Client Secret: your_client_secret
        ```
    80 |
## Verification

1.  **Create a folder inside the rclone associated folder in Google Drive.**

2.  **Test Commands:**

    ```bash
    rclone lsf my_remote: --dirs-only
        rclone lsd my_remote:
        rclone lsl my_remote:
        rclone tree my_remote:
        ```

## Usage

1.  **Check size of server folders:**

    ```bash
    du -sh /path/to/website
        ```
    101 |
    2.  **Check Size of Google Drive folders:**
    103 |
        ```bash
        rclone size "my_remote:"
        rclone size "my_remote:folder1/"
        ```

3.  **Transfer from server to Google Drive:**

    ```bash
    rclone sync /path/to/backup "my_remote:"
        rclone sync /path/to/backup "my_remote:" --progress
        ```
    115 |
    ## Cron Job for Automatic Backups

1.  **Set up a cron job:**

    ```bash
    0 5 */1 * * /usr/bin/rclone copy /path/to/backup "my_remote:" --log-file=/var/log/rclone.log
        ```
    123 |
        This command will create a daily backup at 5:00 AM. The `copy` command preserves all versions of your backups. Use `sync` if you want to overwrite older backups with the latest version.

## Restore from Google Drive

1.  **Restore files:**

    ```bash
    rclone sync -v my_remote: /path/to/backup --progress
        ```
    133 |
        or
    135 |
        ```bash
        rclone copy -v my_remote:backup.tar.gz /path/to/backup --progress
        ```
    139 |
        or
    141 |
        ```bash
        rclone copy -v my_remote:folder1/backup.tar.gz /path/to/backup --progress
        ```

## Uninstallation

1.  **Uninstall rclone:**

    ```bash
    sudo apt remove rclone