#!/bin/bash

# Add cron job for SSL renewal
(crontab -l 2>/dev/null; echo "0 0,12 * * * python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew --quiet") | crontab -

echo "SSL renewal cron job added."
