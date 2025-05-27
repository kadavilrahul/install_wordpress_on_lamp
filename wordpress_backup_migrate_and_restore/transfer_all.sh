# Set the destination IP address
DEST_IP="your_ip"

# Set the destination backup directory
DEST_BACKUP_DIR="/website_backups"

# Create the backup directory on the destination server if it doesn't exist
ssh root@${DEST_IP} "mkdir -p ${DEST_BACKUP_DIR}"

# Transfer the backup files
rsync -avz /website_backups/ root@${DEST_IP}:${DEST_BACKUP_DIR}

# your_password

# Simple rsyc command
# rsync -avz /website_backups/ your_ip:/website_backups
# your_password
