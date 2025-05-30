#!/bin/bash

# Script to disable root SSH login
disable_root_ssh() {
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config.d/50-cloud-init.conf || { echo "Error modifying /etc/ssh/sshd_config.d/50-cloud-init.conf"; return 1; }
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config || { echo "Error modifying /etc/ssh/sshd_config"; return 1; }
    systemctl restart ssh
}

# Script to enable root SSH login
enable_root_ssh() {
    sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config.d/50-cloud-init.conf || { echo "Error modifying /etc/ssh/sshd_config.d/50-cloud-init.conf"; return 1; }
    sed -i 's/^PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config || { echo "Error modifying /etc/ssh/sshd_config"; return 1; }
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