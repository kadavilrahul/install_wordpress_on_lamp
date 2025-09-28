# Complete Fix Report - Apache Site Preservation Issues

## Critical Issue Discovered
The main problem was that the installation scripts were **completely removing and purging Apache packages** (`apt remove --purge apache2*`), which deleted ALL Apache configurations including existing virtual hosts.

## Root Causes Identified

### 1. Primary Issue - Package Purging
- **Location**: `/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh`
- **Functions**: `install_lamp()` (line 370) and `recover_failed_installation()` (line 971)
- **Problem**: Scripts were running `apt remove --purge apache2*` which completely removes Apache and all its configurations
- **Impact**: ALL existing websites would be deleted when installing a new WordPress site

### 2. Secondary Issue - SSL Conflicts
- **Location**: Multiple scripts handling SSL installation
- **Problem**: Sites temporarily disabled for SSL certificate installation weren't always re-enabled
- **Impact**: Some sites might remain disabled after SSL installation

## Solutions Implemented

### 1. Apache Configuration Backup and Restore
Added comprehensive backup and restore logic to `install_lamp()`:
- **Before removal**: Backs up `/etc/apache2/sites-available` and `/etc/apache2/sites-enabled`
- **After reinstallation**: Restores all configurations and re-enables previously enabled sites
- **Backup location**: `/tmp/apache_backup_[timestamp]/`

### 2. Recovery Function Protection
Modified `recover_failed_installation()`:
- Added Apache configuration backup before recovery
- Ensures configurations are preserved even during disaster recovery

### 3. Site Preservation During Installation
Added to `create_vhost_ssl()`:
- `save_enabled_sites()`: Captures all enabled sites before modifications
- `restore_enabled_sites()`: Re-enables all originally enabled sites after installation

### 4. SSL Installation Protection
Enhanced SSL installation in both scripts:
- `/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh`
- `/root/install_wordpress_on_lamp/apache/install_ssl_only.sh`
- Ensures all sites are restored after SSL certificate installation

## Files Modified

1. **`/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh`**
   - Added Apache backup logic in `install_lamp()` function
   - Added Apache backup logic in `recover_failed_installation()` function
   - Added site preservation functions
   - Modified `create_vhost_ssl()` to preserve sites

2. **`/root/install_wordpress_on_lamp/apache/install_ssl_only.sh`**
   - Added site preservation logic in `setup_new_domain()` function
   - Ensures sites are restored after SSL setup

## Testing Commands

```bash
# Check current enabled sites
ls -la /etc/apache2/sites-enabled/

# Run the test script
/root/install_wordpress_on_lamp/test_site_preservation.sh

# Verify specific sites
a2query -s nilgiristores.in
a2query -s goagents.space

# Test site accessibility
curl -I https://nilgiristores.in
curl -I https://goagents.space
```

## Backup Files Created
- `/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh.backup_*`
- `/root/install_wordpress_on_lamp/apache/install_ssl_only.sh.backup_*`

## Expected Behavior After Fix

1. **During New WordPress Installation**:
   - Existing Apache configurations are backed up
   - Apache may be reinstalled if needed
   - All original configurations are restored
   - All originally enabled sites remain enabled
   - New WordPress site is added without affecting existing sites

2. **During Recovery/Cleanup**:
   - Apache configurations are preserved
   - Sites are restored after any cleanup operations

3. **During SSL Certificate Installation**:
   - Sites may be temporarily disabled for SSL installation
   - All sites are automatically re-enabled after SSL setup

## Verification Steps

1. **Before Installing New Site**:
   ```bash
   ls -la /etc/apache2/sites-enabled/ > /tmp/before.txt
   ```

2. **After Installing New Site**:
   ```bash
   ls -la /etc/apache2/sites-enabled/ > /tmp/after.txt
   diff /tmp/before.txt /tmp/after.txt
   ```
   - Should show only the new site added, all existing sites preserved

## Critical Recommendation
**NEVER use `apt remove --purge apache2*` without backing up configurations first!**

## Implementation Date
September 28, 2025

## Author Notes
This was a critical bug that would have caused significant downtime for existing websites whenever a new WordPress site was installed. The fix ensures complete preservation of all Apache configurations throughout the installation process.