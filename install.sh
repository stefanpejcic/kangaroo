#!/bin/bash


sudo apt update
sudo apt install fzf


if ! grep -q 'Kangaroo SSH JumpServer' /etc/ssh/sshd_config; then
  cat << EOF >> /etc/ssh/sshd_config
##### 🦘 Kangaroo SSH JumpServer #####
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match User *,!root
    ForceCommand %h/kangaroo.sh
EOF
fi


sudo systemctl restart ssh
