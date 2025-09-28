# Site Preservation Fix Documentation

## Problem Identified
When installing new WordPress sites using the installation scripts, existing Apache virtual hosts were getting disabled and not re-enabled, causing previously working sites to become inaccessible.

## Root Cause
The installation scripts would temporarily disable conflicting sites during SSL certificate installation but only re-enable those specific sites that were disabled for SSL conflicts. Any other sites that might have been disabled earlier in the process or by other means were not being restored.

## Solution Implemented
Added comprehensive site preservation logic to ensure ALL originally enabled sites remain enabled after installation.

## Files Modified

### 1. `/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh`
- Added `ORIGINALLY_ENABLED_SITES` global array
- Added `save_enabled_sites()` function to capture all enabled sites before modifications
- Added `restore_enabled_sites()` function to re-enable all originally enabled sites
- Modified `create_vhost_ssl()` to call these functions at the beginning and end

### 2. `/root/install_wordpress_on_lamp/apache/install_ssl_only.sh`
- Added site preservation logic within `setup_new_domain()` function
- Saves enabled sites before any Apache configuration changes
- Restores all originally enabled sites at the end of setup

## How It Works

1. **Before Installation:**
   - Script saves a list of ALL currently enabled Apache sites
   - Stores site names in an array for later restoration

2. **During Installation:**
   - Installation proceeds normally
   - Sites may be temporarily disabled for SSL certificate installation
   - New site configuration is created and enabled

3. **After Installation:**
   - Script checks each originally enabled site
   - Re-enables any site that exists but is not currently enabled
   - Reloads Apache to apply all changes

## Testing
Run the test script to verify site status:
```bash
/root/install_wordpress_on_lamp/test_site_preservation.sh
```

## Backups Created
- `/root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh.backup_[timestamp]`
- `/root/install_wordpress_on_lamp/apache/install_ssl_only.sh.backup_[timestamp]`

## Expected Behavior
After installing a new WordPress site:
- ALL previously enabled sites should remain enabled
- The new site should be enabled
- No manual intervention should be required to restore existing sites

## Verification Commands
```bash
# List all enabled sites
ls -la /etc/apache2/sites-enabled/

# Check specific site status
a2query -s nilgiristores.in
a2query -s goagents.space

# Test site accessibility
curl -I https://nilgiristores.in
curl -I https://goagents.space
```

## Rollback Instructions
If needed, restore the original scripts:
```bash
# Find backup files
ls -la /root/install_wordpress_on_lamp/wordpress/*.backup_*
ls -la /root/install_wordpress_on_lamp/apache/*.backup_*

# Restore original scripts (replace timestamp with actual)
cp /root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh.backup_[timestamp] /root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh
cp /root/install_wordpress_on_lamp/apache/install_ssl_only.sh.backup_[timestamp] /root/install_wordpress_on_lamp/apache/install_ssl_only.sh
```

## Date of Implementation
September 28, 2025