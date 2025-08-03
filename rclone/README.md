# Rclone Management Scripts

This folder contains individual scripts for each rclone management option from the original `rclone.sh` file.

## Scripts:

1. **install_package.sh** - Download and install rclone with dependencies
2. **show_status.sh** - Check rclone setup and configuration status  
3. **show_remotes.sh** - Display configured remotes and accessibility
4. **manage_remote.sh** - Configure and use remote storage connections (includes all sub-menu functionality)
5. **uninstall_package.sh** - Remove rclone and all configurations

## Usage:
Each script can be run independently:
```bash
sudo ./install_package.sh
sudo ./show_status.sh
sudo ./manage_remote.sh
# etc.
```

## Special Notes:
- **manage_remote.sh** is the most comprehensive script and includes:
  - Remote selection and configuration
  - Google Drive authentication setup
  - File browsing and navigation
  - Backup copying to remote storage
  - File restoration from remote storage
  
All scripts require root privileges and depend on the `config.json` file for remote configurations.