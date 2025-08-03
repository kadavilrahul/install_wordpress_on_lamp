# WordPress Management Scripts

This folder contains scripts for WordPress installation and management.

## Scripts:

- **install_lamp_stack.sh** - Complete LAMP installation with WordPress setup
- **remove_websites_databases.sh** - Clean removal of websites and associated data
- **remove_orphaned_databases.sh** - Clean up databases without corresponding websites

## Usage:
```bash
sudo ./install_lamp_stack.sh
sudo ./remove_websites_databases.sh
sudo ./remove_orphaned_databases.sh
```

All scripts require root privileges and include comprehensive error handling.