#!/bin/bash

# Set variables
DB_NAME="your_db"
DB_USER="your_user"
DB_PASS="your_password"  # Change this to a secure password
# Find the most recent dump file
DUMP_FILE=$(find /website_backups/postgres -name "*.dump" -type f -printf '%T+ %p\n' | sort -r | head -n 1 | awk '{print $2}')

# Check if a dump file was found
if [ -z "$DUMP_FILE" ]; then
  echo "No dump file found in /website_backups/postgres"
  exit 1
fi

# Update system packages
echo "Updating system packages..."
sudo apt update -y

# Install PostgreSQL (if not installed)
echo "Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL service
echo "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Switch to postgres user and execute commands
echo "Setting up database and user..."
sudo -u postgres psql <<EOF
-- Drop database if it exists
DROP DATABASE IF EXISTS $DB_NAME;

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Drop user if it exists and recreate
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN CREATEDB CREATEROLE PASSWORD '$DB_PASS';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

# Restore the dump file
echo "Restoring the database from dump..."
sudo -u postgres pg_restore --clean --if-exists -d $DB_NAME "$DUMP_FILE"

# Verify database and table existence
echo "Verifying database..."
sudo -u postgres psql -d $DB_NAME -c "\dt"

echo "Database restoration completed successfully!"
