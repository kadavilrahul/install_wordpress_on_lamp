## Access MySQL database:
```bash
sudo mysql -u root -p
```
Enter MySQL root password

### Check existing databases:
```bash
SHOW DATABASES;
```

### Check existing users:
```bash
SELECT User FROM mysql.user;
```

### Login to databases:

```bash
mysql -u database_username -p database_name
```
Enter MySQL database password (not root password)

### Check home URL and site URL in wp_options table:
```bash
SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl', 'home');
```

### Check size of database:
Replace database_name with the actual name of your WordPress database.
```bash
SELECT table_schema AS "Database",
ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS "Size (MB)"
FROM information_schema.tables
WHERE table_schema = "database_name"
GROUP BY table_schema;
```

### Exit
```bash
EXIT;
```

### Exit:
```bash
EXIT;
```
