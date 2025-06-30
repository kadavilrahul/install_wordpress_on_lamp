#!/bin/bash

SUMMARY_FILE="/root/installation_summary_nilgiristores.in.txt"

# Extract DB credentials
DB_NAME=$(grep "Database Name:" "$SUMMARY_FILE" | awk '{print $3}')
DB_USER=$(grep "Database User:" "$SUMMARY_FILE" | awk '{print $3}')
DB_PASSWORD=$(grep "Database Password:" "$SUMMARY_FILE" | awk '{print $3}')

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: Could not extract database credentials from $SUMMARY_FILE" >&2
  exit 1
fi

# Get DB size in bytes
DB_SIZE_BYTES=$(mysql -u"$DB_USER" -p"$DB_PASSWORD" -Nse "SELECT SUM(data_length + index_length) FROM information_schema.tables WHERE table_schema='$DB_NAME';")

# Convert to GB
DB_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $DB_SIZE_BYTES/1024/1024/1024}")

# Add 20% and round up to next GB (minimum 1GB)
REDIS_MAX_MEMORY=$(awk "BEGIN {v=($DB_SIZE_GB*1.2); print (v<1)?1:int((v+0.999))}")

# Update redis.conf
sed -i "/^maxmemory /d" /etc/redis/redis.conf
echo "maxmemory ${REDIS_MAX_MEMORY}gb" >> /etc/redis/redis.conf

# Restart Redis
systemctl restart redis-server

echo "Redis maxmemory set to ${REDIS_MAX_MEMORY}GB (20% higher than DB size, rounded up)."
