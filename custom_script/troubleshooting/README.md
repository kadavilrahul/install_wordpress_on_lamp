### Troubleshooting

1. If wp-admin fails to load after restoration or on other occassion
   a) Deactivate all plugins via WP CLI
   ```bash
   wp plugin deactivate --all --allow-root --path=/var/www/your_website.com
   ```
   
   b) Enter output to chatgpt if error persits.
   
   c) Manually Remove the Broken Plugin
   ```bash
   rm -rf /var/www/your_website.com/wp-content/plugins/plugin_name
   ```
   
   d) Reactivate the plugins

   ```
   wp plugin activate --all --path=/var/www/your_website.com --allow-root
   ```

3. Check if Apache, MySQL , PHP and FPM are running
   ```bash
   Status
   sudo systemctl status apache2
   Restart
   sudo systemctl restart apache2
   ```

   ```bash
   Status
   sudo systemctl status mysql
   Restart
   sudo systemctl restart mysql
   ```
   
   ```bash
   php --version
   Status
   systemctl status php8.3-fpm
   Restart
   systemctl restart php8.3-fpm
   ```

4. Check free memory
   RAM
   ```bash
   free -h
   ```
   Disk Space
   ```bash
   df -h
   ```
   Folder Space
   ```bash
   du -sh /var/
   ```
   ```bash
   du -sh /var/lib
   ```
   ```bash
   du -sh /var/lib/mysql
   ```
   
5. Check Apache error logs

   ```bash
   tail -n 20 /var/log/apache2/error.log
   ```
   Replace your_website.com with actual domain name in below command
   ```bash
   tail -n 50 /var/log/apache2/error_your_website.com.log
   ```
6. Check php error logs

   Add this to wp-config.php
   ```
   # Enable WordPress Debug Mode
   define('WP_DEBUG', true);
   define('WP_DEBUG_LOG', true);
   define('WP_DEBUG_DISPLAY', false);
   ```
   After making this change, clear your debug log again:
   ```
   > /var/www/your_website.com/wp-content/debug.log
   ```
   Then, try accessing your wp-admin and check the log for new errors.
   This should eliminate the warnings and help you find the real issue.

   ```
   grep -i "fatal" /var/www/your_website.com/wp-content/debug.log | tail -20
   ```
   or
   ```
   grep -i "error" /var/www/your_website.com/wp-content/debug.log | tail -30
   ```
   Copy and paste error into chatgpt and resolvet it.

   ```
   # Disable WordPress Debug mode
   define('WP_DEBUG', false);
   define('WP_DEBUG_LOG', false);
   define('WP_DEBUG_DISPLAY', false);
   ```

   After making this change, clear your debug log again:
   ```
   > /var/www/your_website.com/wp-content/debug.log
   ```
7. If /var/lib/mysql has become very large then

   Log into MySQL/MariaDB:
   ```bash
   mysql -u root -p
   ```
   Enter root password

   Check if there are many binary logs
   ```sql
   SHOW BINARY LOGS;
   ```
   Delete all binary logs
   ```sql
   RESET MASTER;
   ```
   ```sql
   EXIT;
   ```
   ```bash
   sudo systemctl restart mysql
   ```
   
9. If you see "Error establishing a Redis connection" on webpage.
   To disable Redis, delete the object-cache.php file in the /wp-content/ directory.
