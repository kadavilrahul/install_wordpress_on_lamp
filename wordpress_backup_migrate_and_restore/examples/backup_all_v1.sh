#!/bin/bash

# Configuration
WWW_PATH="/var/www"
BACKUP_DIR="/website_backups"
WEB_BACKUP_DIR="${BACKUP_DIR}/web"
PG_BACKUP_DIR="${BACKUP_DIR}/postgresql"
BACKUP_RETENTION_DAYS=7
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
DB_CREDENTIALS_FILE="/etc/website_db_credentials.conf"

# Ensure backup directories exist with correct permissions
mkdir -p "$WEB_BACKUP_DIR" "$PG_BACKUP_DIR"
sudo chown postgres:postgres "$PG_BACKUP_DIR"
sudo chmod 700 "$PG_BACKUP_DIR"

# Function to get PostgreSQL database name from credentials file
get_postgres_db_name() {
    local domain=$1
    local db_name=""
    
    if [ -f "$DB_CREDENTIALS_FILE" ]; then
        db_name=$(awk -v domain="Domain: $domain" '
            $0 ~ domain {
                getline
                sub(/Database: /, "")
                print
                exit
            }
        ' "$DB_CREDENTIALS_FILE")
    fi
    
    echo "$db_name"
}

# Function to check if a directory contains WordPress
is_wordpress() {
    local site_path="$1"
    if [ -f "$site_path/wp-config.php" ]; then
        wp core is-installed --path="$site_path" --allow-root &>/dev/null
        return $?
    fi
    return 1
}

# Function to backup PostgreSQL database
backup_postgres() {
    local domain="$1"
    local db_name=$(get_postgres_db_name "$domain")
    
    if [ -z "$db_name" ]; then
        echo "No PostgreSQL database found for domain: $domain"
        return 0
    fi

    echo "Backing up PostgreSQL database: $db_name for domain: $domain"
    local backup_file="${PG_BACKUP_DIR}/postgres_${db_name}_${TIMESTAMP}.dump"

    # Perform database backup
    sudo -u postgres pg_dump -F c "$db_name" -f "$backup_file"
    if [ $? -ne 0 ]; then
        echo "Failed to export PostgreSQL DB for site: $domain"
        return 1
    fi

    # Verify backup file
    sudo pg_restore -l "$backup_file" >/dev/null 2>&1 || {
        echo "Failed to verify PostgreSQL backup for: $domain"
        return 1
    }

    # Copy the backup file to the website root directory
    cp "$backup_file" "$WWW_PATH/$domain/pg_db.dump"
    
    echo "PostgreSQL backup completed for: $domain"
}

# Function to backup WordPress site with all additional content
backup_wordpress_site() {
    local site_path="$1"
    local site_name="$2"
    local backup_file="${WEB_BACKUP_DIR}/${site_name}_backup_${TIMESTAMP}.tar.gz"

    echo "Starting backup for WordPress site: $site_name"
    echo "Site path: $site_path"

    # Export WordPress database to site root
    cd "$site_path"
    wp db export wp_db.sql --allow-root
    if [ $? -ne 0 ]; then
        echo "Failed to export WordPress DB for site: $site_name"
        return 1
    fi
    echo "WordPress database export completed for: $site_name"

    # Backup PostgreSQL database if it exists
    backup_postgres "$site_name"

    echo "Creating archive for: $site_name"
    # Create single backup archive including everything
    tar -czf "$backup_file" \
        --exclude='*/cache' \
        --exclude='*.tar.gz' \
        -C "$WWW_PATH" "$site_name"

    # Clean up database dumps after they're archived
    rm -f "$site_path/wp_db.sql"
    rm -f "$site_path/pg_db.dump"
    
    echo "Backup completed for site: $site_name"
}

# Iterate through all directories in www path
for site_dir in "$WWW_PATH"/*; do
    [ -d "$site_dir" ] || continue  # Skip non-directories
    site_name=$(basename "$site_dir")

    echo "Checking directory: $site_dir"
    if is_wordpress "$site_dir"; then
        echo "Processing WordPress site: $site_name"
        backup_wordpress_site "$site_dir" "$site_name"
    else
        echo "Skipping non-WordPress directory: $site_name"
    fi
done

# Cleanup old backups
find "$PG_BACKUP_DIR" -name "postgres_*_*.dump" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
find "$WEB_BACKUP_DIR" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete
