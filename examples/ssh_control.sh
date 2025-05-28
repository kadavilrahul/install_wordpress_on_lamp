#!/bin/bash

# Script to disable root SSH login
disable_root_ssh() {
    sed -i '1s/yes/no/g' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sed -i '33s/yes/no/g' /etc/ssh/sshd_config
    sed -i '57s/yes/no/g' /etc/ssh/sshd_config
    systemctl restart ssh
}

# Script to enable root SSH login
enable_root_ssh() {
    sed -i '1s/no/yes/g' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sed -i '33s/no/yes/g' /etc/ssh/sshd_config
    sed -i '57s/no/yes/g' /etc/ssh/sshd_config
    systemctl restart ssh
}

# Main script logic
if [ "$1" == "disable" ]; then
    disable_root_ssh
    echo "Root SSH login disabled."
elif [ "$1" == "enable" ]; then
    enable_root_ssh
    echo "Root SSH login enabled."
else
    echo "Usage: $0 [enable|disable]"
    exit 1
fi

exit 0
