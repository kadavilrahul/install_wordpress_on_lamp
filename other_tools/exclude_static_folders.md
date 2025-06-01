### To modify your Apache configuration to serve static HTML pages stored in /var/www/your_website.com/products while keeping WordPress functional

Configure Apache to serve both WordPress and static HTML pages without conflicts:
Virtual Host for the Main Domain: Add the following in your Apache configuration (/etc/apache2/sites-available/your_website.com.conf):
Updated Apache Configuration

```bash
<VirtualHost *:80>
    ServerAdmin your_email@gmail.com
    ServerName your_website.com.com
    ServerAlias www.your_website.com
    DocumentRoot /var/www/your_website.com

    <Directory /var/www/your_website.com>
        AllowOverride All
        Require all granted
    </Directory>

    # Exclude /products folder from being processed by WordPress
    Alias /products /var/www/your_website.com/products
    <Directory /var/www/your_website.com/products>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error_your_website.com.log
    CustomLog ${APACHE_LOG_DIR}/access_your_website.com.log combined

    RewriteEngine on
    RewriteCond %{SERVER_NAME} =www.your_website.com [OR]
    RewriteCond %{SERVER_NAME} =your_website.com
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
```


By defining the /products folder explicitly in the configuration, requests to this folder bypass WordPress completely.
How This Works:
Requests to WordPress:
Any request not starting with /products will continue to be processed by WordPress.
Requests to /products:
Directly served by Apache from /var/www/your_website.com/products.


Enable the Configuration:
```bash
sudo a2ensite your_website.com.conf
sudo systemctl reload apache2
```

Test the Setup:
Place a sample HTML file, e.g., test.html, in /var/www/your_website.com/products:

```
<html>
<head><title>Test Page</title></head>
<body><h1>This is a test HTML page</h1></body>
</html>
```

Access it via:
```
http://your_website.com/products/test.html
```
