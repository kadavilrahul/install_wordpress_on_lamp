# Original Monolithic Scripts - Moved on 02/08/2025

This folder contains the original large, monolithic scripts that have been divided into smaller, focused individual files for better maintainability and usability.

## Files Moved and Their Replacements:

### 1. `run.sh` (1756 lines) → 12 individual files:
- `01_install_lamp_wordpress.sh`
- `02_backup_restore.sh` 
- `03_install_apache_ssl_only.sh`
- `04_miscellaneous_tools.sh`
- `05_mysql_remote_access.sh`
- `06_troubleshooting.sh`
- `07_rclone_management.sh`
- `08_configure_redis.sh`
- `09_remove_websites_databases.sh`
- `10_remove_orphaned_databases.sh`
- `11_fix_apache_configs.sh`
- `12_system_status_check.sh`

### 2. `miscellaneous.sh` (511 lines) → 9 individual files:
- `misc_01_show_mysql_databases.sh`
- `misc_02_list_mysql_users.sh`
- `misc_03_get_database_size.sh`
- `misc_04_adjust_php_settings.sh`
- `misc_05_view_php_info.sh`
- `misc_06_disk_space_monitor.sh`
- `misc_07_toggle_root_ssh.sh`
- `misc_08_install_phpmyadmin.sh`
- `misc_09_system_utilities.sh`

### 3. `rclone.sh` (841 lines) → 5 individual files:
- `rclone_01_install_package.sh`
- `rclone_02_show_status.sh`
- `rclone_03_show_remotes.sh`
- `rclone_04_manage_remote.sh`
- `rclone_05_uninstall_package.sh`

### 4. `backup_restore.sh` (1021 lines) → To be divided into 5 individual files
### 5. `troubleshooting.sh` (291 lines) → To be divided into 10 individual files

## Files That Remain Unchanged:
- `mysql_remote.sh` (195 lines) - Single-purpose script, focused enough to remain as is

## Benefits of Division:
1. **Easier Maintenance** - Each file has a single responsibility
2. **Better Testing** - Individual functions can be tested in isolation
3. **Improved Usability** - Users can run specific functions directly
4. **Reduced Complexity** - Smaller files are easier to understand and modify
5. **Preserved Functionality** - All functions copied exactly as they were

## Usage:
These original files are kept for reference. Use the individual numbered files in the main directory for actual operations.