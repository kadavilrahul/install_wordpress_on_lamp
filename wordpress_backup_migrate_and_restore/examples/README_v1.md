# WordPress and PostgreSQL Backup Script

This script (`backup.sh`) provides an automated solution for backing up WordPress websites and their associated PostgreSQL databases. It's designed to handle multiple WordPress installations in a shared hosting environment.

## Features

- Automatically detects and backs up WordPress installations
- Backs up associated PostgreSQL databases
- Creates compressed archives of website files
- Maintains a configurable retention period for backups
- Excludes cache directories to optimize backup size
- Verifies database backup integrity
- Supports multiple websites in a single backup run

## Prerequisites

- Bash shell environment
- WordPress CLI (`wp-cli`) installed and accessible
- PostgreSQL client tools (`pg_dump`, `pg_restore`)
- Sufficient disk space for backups
- Required file permissions and sudo access

## Configuration

The script uses the following configuration variables:

```bash
WWW_PATH="/var/www"                    # Path to website root directories
BACKUP_DIR="/website_backups"          # Main backup directory
WEB_BACKUP_DIR="${BACKUP_DIR}/web"     # Website backups location
PG_BACKUP_DIR="${BACKUP_DIR}/postgresql" # PostgreSQL backups location
BACKUP_RETENTION_DAYS=7                # Number of days to keep backups
DB_CREDENTIALS_FILE="/etc/website_db_credentials.conf" # Database credentials file
```

### Database Credentials File Format

The script expects PostgreSQL database credentials in the following format:
```
Domain: example.com
Database: example_db
```

### Setup and Installation
Linux:
(Run these commands on Linux terminal to get started)

Git clone and enter repository folder

```bash
git clone https://github.com/kadavilrahul/backup_and_restore.git
```

```bash
cd backup_and_restore
```

```bash
bash backup.sh
```

## Backup Process

1. **Directory Setup**
   - Creates necessary backup directories if they don't exist
   - Sets appropriate permissions for PostgreSQL backup directory

2. **WordPress Detection**
   - Scans the WWW_PATH for WordPress installations
   - Verifies WordPress installation using wp-cli

3. **WordPress Backup**
   - Exports WordPress database to SQL file
   - Creates a compressed archive of all website files
   - Excludes cache directories and existing backup files

4. **PostgreSQL Backup**
   - Identifies associated PostgreSQL database from credentials file
   - Creates a binary dump of the database
   - Verifies backup integrity
   - Includes database backup in the website archive

5. **Cleanup**
   - Removes temporary database dump files
   - Deletes backups older than BACKUP_RETENTION_DAYS

## Backup File Naming

- WordPress backups: `{site_name}_backup_{timestamp}.tar.gz`
- PostgreSQL backups: `postgres_{db_name}_{timestamp}.dump`
- Timestamp format: YYYY-MM-DD_HH-MM-SS

## Output Files

The script creates two types of backup files:

1. Website backups (in WEB_BACKUP_DIR):
   - Complete website files
   - WordPress database dump
   - PostgreSQL database dump (if applicable)

2. PostgreSQL backups (in PG_BACKUP_DIR):
   - Binary database dumps

## Error Handling

The script includes error checking for:
- Database export operations
- Archive creation
- Backup verification
- File permissions

## Maintenance

The script automatically maintains backup storage by:
- Removing backups older than the specified retention period
- Cleaning up temporary files after backup completion

## Security Considerations

- PostgreSQL backup directory permissions are set to 700
- Database credentials file should be properly secured
- Script requires appropriate sudo permissions for PostgreSQL operations


It's recommended to schedule this script using cron for regular backups.
