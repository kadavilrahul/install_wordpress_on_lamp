# Rclone Google Drive Backup Setup

This guide provides instructions on how to install and configure rclone for backing up your website to Google Drive.

## Prerequisites

*   A server with root access
*   A Google Cloud account

## Installation

Run this on VS code or Remote desktop so that login process does not have port conflict errors

1.  **Enter root user:**

    ```bash
    sudo bash
    ```

2.  **Install rclone:**

    ```bash
    sudo apt update
    ```
    ```bash
    sudo apt install rclone
    ```

3.  **Run rclone config:**

    ```bash
    rclone config
    ```

4.  **Create a new remote (with Google drive):**

    *   Select `n` for new remote.
    *   Name it `my_remote`.
    *   Select Google Drive (option `13` or `18` depending on your rclone version).
    *   For setup without `client_id` and `client_secret`, press Enter to use auto config. 
    *   For setup with `client_id` and `client_secret`
    *    - Go to <https://console.cloud.google.com/>
    *    - Click on the project drop-down and select "New Project".
    *    - Give your project a name (e.g., "rclone-active") and click "Create".
    *    - With your new project selected, go to the Google API Library.
    *    - Search for "Google Drive API" and click on it.    
    *    - Go to the Credentials page in the Google Cloud Console.
    *    - Click "Enable".
    *    - Click "Create Credentials" and select "OAuth client ID".
    *    - If prompted, configure the consent screen by providing necessary information like application name, email, and scopes.
    *    - Click "Create Credentials" and select "OAuth client ID" again.
    *    - For the application type, choose "Desktop app" and click "Create".
    *    - After creating the credentials, you’ll be presented with a client ID and client secret. 
    *    - Click "Download" to save the credentials as a JSON file.
    *   Select `1` for full access to all files.
    *   Leave blank "service_account_file>" and enter
    *   Select No (default) for Edit advanced config?
    *   Select Yes (default) for Use auto config?
    *   When the browser opens, use the **SECOND** link if multiple appear.
    *   Log in with your Google account and authorize rclone.
    *   Select No (default) for Configure this as a Shared Drive (Team Drive)?
    *   Select Yes this is OK (default)Keep this "server_silkroademart" remote?
    *   Select `y` to confirm the configuration is correct.
    *   Select `q` to quit config.

## Google Cloud Console Credentials

    Example Credentials:

    ```text
    Client ID: your_client_id
    Client Secret: your_client_secret
    ```

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

1.  **Check Size of Google Drive folders:**

    ```bash
    rclone size "remote_name:"
    rclone size "remote_name:/path/to/folder/"
    ```   ```

2. **Check latest backup files**

    ```bash
    rclone lsl "remote_name:/path/to/folder/" | sort -k2,2 | tail -n 2
  
3. **Restore latest files from Google Drive:**

    ```bash
    read -p "How many latest backup files do you want to copy? (1 or 2): " NUM && [[ "$NUM" == "1" || "$NUM" == "2" ]] && rclone lsl "remote_name:/path/to/folder/" | sort -k2,2 | tail -n $NUM | awk '{print $NF}' | xargs -I{} rclone copy -v "server_silkroademart:backup_silkroademart/{}" /website_backups --progress || echo "Invalid input. Please enter 1 or 2."
    ```
    
## Cron Job for Automatic Backups

    **Set up a cron job:**

    ```bash
    0 5 */1 * * /usr/bin/rclone copy /path/to/backup "remote_name:" --log-file=/var/log/rclone.log
    ```

    This command will create a daily backup at 5:00 AM.  The `copy` command preserves all versions of your backups.  Use `sync` if you want to overwrite older backups with the latest version.


## Uninstallation

1.  **Uninstall rclone:**

    ```bash
    sudo apt remove rclone


## Other commands to  restore files (Test carefully before real use)

    ```bash
    rclone copy -v remote_name:backup.tar.gz /path/to/backup --progress
    ```

    or

    ```bash
    rclone sync -v remote_name: /path/to/backup --progress
    ```

    Sync server to Google Drive (Test this carefully before real execution):**

    ```bash
    rclone sync /path/to/backup "remote_name:"
    rclone sync /path/to/backup "remote_name:" --progress
    ```

    Restore from Google Drive with file name

    ```bash
    rclone copy -v remote_name:/path/to/folder/backup.tar.gz /path/to/backup --progress
    ```
