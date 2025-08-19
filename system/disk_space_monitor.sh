#!/bin/bash

[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

if [ $# -eq 0 ]; then
    echo "1) Show usage  2) Clean logs  3) Clean cache  4) Clean temp  5) Clean MySQL  6) Clean Docker  7) Clean all"
    read -p "Select option: " choice
    case $choice in
        1) set -- usage ;;
        2) set -- logs ;;
        3) set -- cache ;;
        4) set -- temp ;;
        5) set -- mysql ;;
        6) set -- docker ;;
        7) set -- all ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
fi

case $1 in
    usage) 
        echo "=== Disk Usage ==="
        df -h | awk 'NR==1 {print "Filesystem      Used  Available  Use%  Mounted on"} NR>1 {print $1 "  " $3 "  " $4 "  " $5 "  " $6}'
        echo
        echo "=== Memory Usage ==="
        free -h | awk 'NR==1 {print "Type     Used   Available"} /^Mem/ {print "Memory   " $3 "   " $7} /^Swap/ {print "Swap     " $3 "   " $4}'
        ;;
    logs) journalctl --vacuum-time=7d; find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null ;;
    cache) apt-get clean; apt-get autoremove -y ;;
    temp) find /tmp -mtime +7 -delete 2>/dev/null; find /var/tmp -mtime +30 -delete 2>/dev/null ;;
    mysql) command -v mysql >/dev/null && mysql -u root -p -e "RESET MASTER;" || echo "MySQL not found" ;;
    docker) command -v docker >/dev/null && docker system prune -af || echo "Docker not found" ;;
    all) 
        echo "=== Before Cleanup ==="
        df -h / | awk 'NR>1 {print "Used: " $3 " (" $5 ")"}'
        journalctl --vacuum-time=7d >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1; apt-get autoremove -y >/dev/null 2>&1
        find /tmp -mtime +7 -delete 2>/dev/null
        find /var/tmp -mtime +30 -delete 2>/dev/null
        command -v docker >/dev/null && docker system prune -af >/dev/null 2>&1
        echo "=== After Cleanup ==="
        df -h / | awk 'NR>1 {print "Used: " $3 " (" $5 ")"}'
        ;;
    *) echo "Usage: $0 {usage|logs|cache|temp|mysql|docker|all}" ;;
esac