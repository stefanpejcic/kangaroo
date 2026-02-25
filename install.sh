#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$SCRIPT_DIR" == /root* ]]; then
    echo "[ERROR] Do not install Kangaroo from /root/ or any of its subdirectories."
    echo "Users can not access /root/ - instead install in /home/ or other shared location."
    exit 1
fi

echo "alias kangaroo=\"python3 $SCRIPT_DIR/cli.py\"" >> ~/.bashrc


# ======================================================================
# Functions

install_if_missing() {
    local cmd="$1"
    local pkg="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        apt update -qq >/dev/null && apt install -y -qq "$pkg" >/dev/null
        echo "$pkg installed successfully."
    fi
}

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
##### Kangaroo SSH JumpServer #####
template(name="RemoteLog" type="string" string="/var/log/remote/%HOSTNAME%.log")
*.* action(type="omfile" dynaFile="RemoteLog")
EOF
fi


echo "Restarting rsyslog service.."
sudo systemctl restart rsyslog

}






# ======================================================================
# Main
install_if_missing "tlog-rec-session" "tlog"
install_if_missing "fzf" "fzf"

chmod a+x "${SCRIPT_DIR}/server/client.sh"
mkdir -p "${SCRIPT_DIR}/server/logs"
touch "${SCRIPT_DIR}/server/logs/ssh_login.log"
chmod 666 "${SCRIPT_DIR}/server/logs/ssh_login.log"

if ! grep -q 'Kangaroo SSH JumpServer' /etc/ssh/sshd_config; then
echo "Restricting all users except 'root' to ${SCRIPT_DIR}/server/client.sh"

  cat << EOF >> /etc/ssh/sshd_config
##### 🦘 Kangaroo SSH JumpServer #####
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match Group jump-users
    ForceCommand tlog-rec-session -c ${SCRIPT_DIR}/server/client.sh
    AllowTcpForwarding no
    X11Forwarding no
EOF


echo "Restarting SSH service.."
sudo systemctl restart ssh
fi

# group existing users
echo "Adding all exisitng users to jump-users group.."
groupadd jump-users
awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | xargs -I {} usermod -aG jump-users {}


log_collector

echo "🦘 Kangaroo SSH JumpServer is installed! - please execute 'source ~/.bashrc'"
echo
echo "" 
echo
exit 0
