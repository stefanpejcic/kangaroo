#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == /root* ]]; then
    echo "❌ Do not install Kangaroo from /root/ or any of its subdirectories."
    echo "Users can not access /root/ - instead install in /home/ or other shared location."
    exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
    echo "Installing fzf..."
    apt update -qq >/dev/null && apt install -y -qq fzf >/dev/null
    echo "fzf installed successfully."
    clear
fi

CONFIG_FILE="$SCRIPT_DIR/jump_servers.conf"

if ! grep -q 'Kangaroo SSH JumpServer' /etc/ssh/sshd_config; then
echo "Restricting all users except 'root' to ${SCRIPT_DIR}/server/client.sh"

  cat << EOF >> /etc/ssh/sshd_config
##### 🦘 Kangaroo SSH JumpServer #####
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match User *,!root
    ForceCommand ${SCRIPT_DIR}/server/client.sh
EOF

echo "Restarting SSH service.."
sudo systemctl restart ssh

fi

chmod a+x "${SCRIPT_DIR}/server/client.sh"

echo "🦘 Kangaroo SSH JumpServer is installed!"
