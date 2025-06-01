### This configuration tells Apache to look for index.html before index.php when a directory is requested

1. Edit Your VirtualHost to Allow .htaccess
Filename: 
/etc/apache2/sites-available/your_site.conf
or
/etc/apache2/sites-available/000-default.conf
or
/etc/apache2/sites-available/default.conf

Add the following block inside your <VirtualHost *:80> section, right after DocumentRoot /var/www/html:

```
<Directory /var/www/html>
    AllowOverride All
    Options -Indexes +FollowSymLinks
    Require all granted
</Directory>
```

Your file should look like this:

```
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Options -Indexes +FollowSymLinks
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

2. Reload Apache
After saving the file, reload Apache to apply changes:
```
sudo systemctl reload apache2
```

3. Create/Edit .htaccess in /var/www/html
Add this to /var/www/html/.htaccess or /var/www/your_site.com/.htaccess
```
DirectoryIndex index.html index.php
Options -Indexes
```

4. Test
 - Visit http://your_server_ip/ — you should see your index.html content.
 - If you remove/rename index.html, you should get a 403 Forbidden error (not a directory listing).

5. Summary
 - Add a <Directory /var/www/your_site> or <Directory /var/www/html> block with AllowOverride All to your VirtualHost.
 - Reload Apache.
 - Use .htaccess to control directory index and disable directory listing.