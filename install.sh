#!/bin/bash

: '
to add slave servers:
bash server/add_server.sh --description="op mejl server" --name="mail" --ip=185.119.XX.XX --password="XXXXX" --users=stefan,stefan2
'


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$SCRIPT_DIR" == /root* ]]; then
    echo "[ERROR] Do not install Kangaroo from /root/ or any of its subdirectories."
    echo "Users can not access /root/ - instead install in /home/ or other shared location."
    exit 1
fi

echo 'alias kangaroo="python3 $SCRIPT_DIR/cli.py"' >> ~/.bashrc

log_collector() {

if ! grep -q 'Kangaroo SSH JumpServer' /etc/rsyslog.conf; then
echo "Configuring logs from slave servers.."

  cat << EOF >> /etc/rsyslog.conf
##### 🦘 Kangaroo SSH JumpServer #####
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
EOF

fi

sudo mkdir -p /var/log/remote/
sudo chown syslog:adm /var/log/remote

if ! grep -q 'Kangaroo SSH JumpServer' /etc/rsyslog.d/remote.conf; then
echo "Configuring logs from slave servers.."

  cat << EOF >> /etc/rsyslog.d/remote.conf
##### 🦘 Kangaroo SSH JumpServer #####
$template RemoteLog,"/var/log/remote/%HOSTNAME%.log"
*.* ?RemoteLog
& ~
EOF
fi


echo "Restarting rsyslog service.."
sudo systemctl restart rsyslog
clear

}



if ! command -v fzf >/dev/null 2>&1; then
    echo "Installing fzf..."
    apt update -qq >/dev/null && apt install -y -qq fzf >/dev/null
    echo "fzf installed successfully."
    clear
fi

chmod a+x "${SCRIPT_DIR}/server/client.sh"
mkdir -p "${SCRIPT_DIR}/server/logs"
touch "${SCRIPT_DIR}/server/logs/ssh_login.log"
chmod 666 "${SCRIPT_DIR}/server/logs/ssh_login.log"

if ! grep -q 'Kangaroo SSH JumpServer' /etc/ssh/sshd_config; then
echo "Restricting all users except 'root' to ${SCRIPT_DIR}/server/client.sh"

  cat << EOF >> /etc/ssh/sshd_config
##### 🦘 Kangaroo SSH JumpServer #####
#PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match User *,!root
    ForceCommand ${SCRIPT_DIR}/server/client.sh
EOF

clear
echo "Restarting SSH service.."
sudo systemctl restart ssh
clear
fi


log_collector


echo "🦘 Kangaroo SSH JumpServer is installed! - please execute 'source ~/.bashrc'"
echo
echo "" 
echo
exit 0
