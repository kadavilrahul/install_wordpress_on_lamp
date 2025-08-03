# Backup and Restore Scripts

This folder contains scripts for backing up and restoring WordPress sites and databases.

## Scripts:

- **backup_restore_menu.sh** - Main backup/restore menu interface
- **backup_wordpress.sh** - Create backups of WordPress websites and databases
- **restore_wordpress.sh** - Restore WordPress sites from backup archives
- **backup_postgresql.sh** - Create PostgreSQL database backups
- **restore_postgresql.sh** - Restore PostgreSQL databases from backup files
- **transfer_backups.sh** - Copy backups to another server via SSH

## Usage:
```bash
sudo ./backup_restore_menu.sh
sudo ./backup_wordpress.sh
sudo ./restore_wordpress.sh
# etc.
```

All scripts require root privileges and support various backup formats.