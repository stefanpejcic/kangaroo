#!/bin/bash

[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass not found. Installing..."
    apt update -qq >/dev/null && apt install -y -qq sshpass >/dev/null
    echo "sshpass installed successfully."
fi


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jump_servers.conf"
ssh_user="root" #maybe?
ssh_port=22
selected_users=""

for arg in "$@"; do
    case $arg in
        --description=*) server_description="${arg#*=}" ;;
        --name=*)        server_name="${arg#*=}"        ;;
        --ip=*)          server_ip="${arg#*=}"          ;;
        --user=*)        ssh_user="${arg#*=}"           ;;
        --port=*)        ssh_port="${arg#*=}"           ;;
        --password=*)    ssh_password="${arg#*=}"       ;;
        --users=*)       selected_users="${arg#*=}"     ;;
    esac
done

# Prompts
[[ -z "$server_name" ]]        && read -p "Server Name: " server_name
[[ -z "$server_ip" ]]          && read -p "IP Address: "  server_ip

if [[ -z "$ssh_user" ]]; then
  read -p "Enter SSH username for the new server: " ssh_user
  ssh_user=${ssh_user:-root}
fi

if [[ -z "$ssh_port" ]]; then
  read -p "Enter SSH port for the new server (default 22): " ssh_port
  ssh_port=${ssh_port:-22}
fi

if [[ -z "$ssh_password" ]]; then
   echo "Insert password for $ssh_user@$server_ip:$ssh_port"
   read -r USERPASS
else
   USERPASS="$ssh_password"
fi

# ======================================================================
# Functions

generate_key() {
	cert_file="/etc/ssh/kangaroo_${server_name}_key_id_rsa.pub"
	private_key_file="/etc/ssh/kangaroo_${server_name}_key_id_rsa"
    if [ ! -f "$private_key_file" ]; then
        echo "Generating $cert_file and $private_key_file"
        ssh-keygen -t rsa -b 4096 -f "$private_key_file" -N ""
    else
        echo "Reusing existing keys pair: $cert_file and $private_key_file"
    fi	
}

test_ssh_connection() {
	if command -v csf >/dev/null 2>&1; then
	    csf -a "$server_ip" "$server_name KangarooSSH JumpServer Slave IP" > /dev/null 2>&1
	fi

    echo "Copying SSH certificate to the new server..."
	ssh-keygen -f "/root/.ssh/known_hosts" -R "$server_ip" >/dev/null 2>&1
    output=$(timeout 15s bash -c \
        "echo \"$USERPASS\" | sshpass ssh-copy-id \
        -p \"$ssh_port\" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -f -i \"$cert_file\" \
        \"$ssh_user@$server_ip\"" 2>&1)
	status=$?

    if [ $status -ne 0 ]; then
        if echo "$output" | grep -q "All keys were skipped because they already exist"; then
            echo "SSH key already exists on remote server. Proceeding..."
        else
            echo "Error copying SSH key to remote server."
            echo "Details: $output"
            echo "Please try manually with the following command:"
            echo "sshpass -p '$USERPASS' ssh-copy-id -p $ssh_port -o StrictHostKeyChecking=no -i $cert_file $ssh_user@$server_ip"
            exit 1
        fi
    else
        echo "SSH key copied successfully."
    fi
}

jail_all_users_on_remote() {
    master_ip=$(curl -s https://ip.unlimited.rs/ip/)

	ssh -p "$ssh_port" -o StrictHostKeyChecking=no -i "$private_key_file" "$ssh_user@$server_ip" << EOF
set -e
MASTER_IP="$master_ip"
SLAVE_IP="$server_ip"

id -u kangaroo &>/dev/null || useradd -m -s /bin/bash kangaroo
getent group sudo >/dev/null && usermod -aG sudo kangaroo || usermod -aG wheel kangaroo 2>/dev/null

echo "kangaroo ALL=(ALL:ALL) NOPASSWD: ALL, !/usr/bin/rm, !/usr/sbin/reboot, !/usr/sbin/shutdown" > /etc/sudoers.d/kangaroo
chmod 440 /etc/sudoers.d/kangaroo
grep -q "sudo -i" /home/kangaroo/.bashrc || echo "exec sudo -i" >> /home/kangaroo/.bashrc
visudo -c
if [ $? -eq 0 ]; then
	echo -e "Successfully applied sudoers to \$SLAVE_IP"
else
	echo -e "Sudoers syntax error on \$SLAVE_IP! Reverting..."
	rm /etc/sudoers.d/kangaroo
fi



echo -e "##### Kangaroo SSH JumpServer #####\n*.* @\$MASTER_IP:514" > /etc/rsyslog.d/999-kangaroo.conf
systemctl restart rsyslog >/dev/null

if command -v csf >/dev/null 2>&1; then
	csf -a "\$MASTER_IP" "KangarooSSH JumpServer Master IP" > /dev/null 2>&1
fi

EOF

#wget -q -O /usr/local/bin/restricted_command.sh https://raw.githubusercontent.com/stefanpejcic/openjumpserver/refs/heads/main/behind-jumserver/restricted_command.sh 2>/dev/null
#chmod +x "/usr/local/bin/restricted_command.sh" && chattr +i "/usr/local/bin/restricted_command.sh"
#echo -e "##### 🦘 Kangaroo SSH JumpServer #####\nMatch User $ssh_user\n    PermitRootLogin yes\n    PubkeyAuthentication yes\n    ForceCommand /usr/local/bin/restricted_command.sh" > /etc/ssh/sshd_config.d/999-kangaroo.conf
#systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "FATAL ERROR running commands on remote server."
        exit 1
    fi
}


# Function to set up SSH certificate-based authentication for existing users on MASTER
setup_ssh_access() {
    local user=$1
    local user_home_dir
    user_home_dir="$(eval echo ~$user)"
    local authorized_keys_dir="$user_home_dir/.ssh"
    local authorized_keys_file="$authorized_keys_dir/authorized_keys"
    local user_ssh_config="$authorized_keys_dir/config"
    local bash_profile="$user_home_dir/.bash_profile"
    local ssh_key_link="$authorized_keys_dir/kangaroo_${server_name}_key_id_rsa"

    if [ ! -f "$cert_file" ]; then
        echo "No SSH certificate found."
        exit 1
    fi

    echo "Setting up SSH access for user $user"
    [[ "$user" == "root" ]] && return

    # Ensure .ssh directory exists with proper permissions
    install -d -m 700 -o "$user" -g "$user" "$authorized_keys_dir"

    # Prepare SSH config
    if [ ! -f "$user_ssh_config" ]; then
        touch "$user_ssh_config"
        chmod 600 "$user_ssh_config"
        chown "$user:$user" "$user_ssh_config"
    fi

    # Copy private key and set permissions
    cp "$private_key_file" "$ssh_key_link"
    chown "$user:$user" "$ssh_key_link"
    chmod 600 "$ssh_key_link"

    # Set authorized_keys permissions
    touch "$authorized_keys_file"
    chown "$user:$user" "$authorized_keys_file"
    chmod 600 "$authorized_keys_file"

    # Add host to SSH config if it doesn't exist
    if ! grep -q "Host $server_name" "$user_ssh_config"; then
        {
            echo "# Description: $server_description"
            echo "Host $server_name"
            echo "    HostName $server_ip"
            echo "    User $ssh_user"
            echo "    Port $ssh_port"
            echo "    IdentityFile ~/.ssh/kangaroo_${server_name}_key_id_rsa"
            echo "    CertificateFile $cert_file"
            echo ""
        } >> "$user_ssh_config"
        echo "Added $server_name to SSH config."
    else
        echo "Host $server_name already exists in SSH config. Skipping."
    fi

    # Ensure bash profile entries exist
    touch "$bash_profile"
    grep -qxF "export PATH=$user_home_dir/bin" "$bash_profile" || echo "export PATH=$user_home_dir/bin" >> "$bash_profile"
    grep -qxF "$HOME/kangaroo.sh" "$bash_profile" || echo "$HOME/kangaroo.sh" >> "$bash_profile"
    grep -qxF "logout" "$bash_profile" || echo "logout" >> "$bash_profile"

    chown "$user:$user" "$bash_profile"
    chmod 700 "$bash_profile"

    # Ensure .ssh directory ownership
    chown -R "$user:$user" "$authorized_keys_dir"
}

setup_ssh_for() {
    local users="$1"

	# adds all users to jump-users group - TODO: https://www.youtube.com/watch?v=tw429JGL5zo&list=RDtw429JGL5zo
	awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | xargs -I {} usermod -aG jump-users {}

	if [[ "$users" == "all" ]]; then
	    users=$(awk -F: '$7 ~ /(\/bin\/(bash|sh|zsh))$/ {print $1}' /etc/passwd)
	fi

    for user in $users; do
        if id "$user" &>/dev/null; then
            setup_ssh_access "$user"
        else
            echo "User '$user' not found. Skipping..."
        fi
    done
}

# ======================================================================
# Main

# 1. generate a key, test SSH connection and cp certificate to the new server's authorized keys
generate_key
test_ssh_connection

# 2. jail all on remote
jail_all_users_on_remote

# 3. set up SSH access for all existing users or specified users
if [[ -z "$selected_users" ]]; then
    read -p "Setup SSH for all existing users? (y/n): " add_to_all
    [[ "$add_to_all" =~ ^[Yy]$ ]] && selected_users="all" || read -p "Enter usernames (space-separated): " selected_users
fi
setup_ssh_for ${selected_users:-all}

# 4. save new server info
mkdir -p $SCRIPT_DIR
echo "$server_name $server_ip" >> "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
echo "Server $server_name ($server_ip:$ssh_port) added, and SSH access configured using certificates from Kangaroo 🦘"
