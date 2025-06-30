#!/bin/bash

# Test MySQL remote access
DB_HOST="37.27.192.145"
DB_USER="silkroademart_com_user"
DB_NAME="silkroademart_com_db"
DB_PASS="silkroademart_com_2@"

if mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" $DB_NAME -e "SHOW TABLES;"; then
    echo "MySQL remote connection successful!"
else
    echo "MySQL remote connection failed"
    echo "Possible issues:"
    echo "1. MySQL not configured for remote access"
    echo "2. Firewall blocking port 3306"
    echo "3. Incorrect credentials"
    echo "4. User lacks privileges"
fi

