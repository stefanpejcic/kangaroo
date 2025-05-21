#!/bin/bash


sudo apt update
sudo apt install fzf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jump_servers.conf"

if ! grep -q 'Kangaroo SSH JumpServer' /etc/ssh/sshd_config; then
  cat << EOF >> /etc/ssh/sshd_config
##### 🦘 Kangaroo SSH JumpServer #####
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match User *,!root
    ForceCommand ${SCRIPT_DIR}/server/client.sh
EOF
fi


sudo systemctl restart ssh
