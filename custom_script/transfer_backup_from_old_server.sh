# Ask if the user is on the source/old server
read -p "Are you on the source/old server? (yes/no): " ON_SOURCE_SERVER
if [[ "$ON_SOURCE_SERVER" != "yes" ]]; then
    echo "Please run this script on the source/old server."
    exit 1
fi

# Prompt for the destination IP address
read -p "Enter the destination IP address: " DEST_IP

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
