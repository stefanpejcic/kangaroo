#!/bin/bash

[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass not found. Installing..."
    apt update -qq >/dev/null && apt install -y -qq sshpass >/dev/null
    echo "sshpass installed successfully."
fi

cert_file="/etc/ssh/ssh_host_rsa_key.pub"
private_key_file="/etc/ssh/ssh_host_rsa_key"
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

test_ssh_connection() {
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

    master_ip=$(curl -s https://ip.openpanel.com)

ssh -p "$ssh_port" -o StrictHostKeyChecking=no -i "$private_key_file" "$ssh_user@$server_ip" << EOF
set -e

SCRIPT_PATH="/usr/local/bin/restricted_command.sh"
MASTER_IP="$master_ip"

if [ ! -f "\$SCRIPT_PATH" ]; then
    wget --no-verbose -O "\$SCRIPT_PATH" https://raw.githubusercontent.com/stefanpejcic/openjumpserver/refs/heads/main/behind-jumserver/restricted_command.sh
    chmod +x "\$SCRIPT_PATH" && chattr +i "\$SCRIPT_PATH"
fi

cat > /etc/ssh/sshd_config.d/999-kangaroo.conf <<EOL
##### 🦘 Kangaroo SSH JumpServer #####
Match User $ssh_user
    ForceCommand $SCRIPT_PATH
EOL

systemctl restart ssh >/dev/null

if command -v csf >/dev/null 2>&1; then
    echo "CSF detected on slave server. Adding \$MASTER_IP to allow list..."
    csf -a "\$MASTER_IP" "KangarooSSH JumpServer Master IP" || true
    csf -r || true
fi

EOF

    if [ $? -ne 0 ]; then
        echo "FATAL ERROR running commands on remote server."
        exit 1
    fi
}


add_ssh_kagaroo_for_user() {
    local user=$1
    [[ "$user" == "root" ]] && return

    user_home_dir="$(eval echo ~$user)"
	user_ssh_config="$user_home_dir/.ssh/config"
	
	install -d -m 700 -o "$user" -g "$user" "$user_home_dir/.ssh"
	install -m 600 -o "$user" -g "$user" /dev/null "$user_ssh_config"

	{
	    echo "# Description: $server_description"
	    echo "Host $server_name"
	    echo "    HostName $server_ip"
	    echo "    User $ssh_user"
	    echo "    Port $ssh_port"
	    echo "    IdentityFile ~/.ssh/jumpserver_key"
	    echo "    CertificateFile $cert_file"
	    echo ""
	} >> "$user_ssh_config"
	
	chown -R "$user:$user" "$user_home_dir/.ssh"
    local ssh_key_link="$user_home_dir/.ssh/jumpserver_key"
	ln -sfT "$private_key_file" "$ssh_key_link"
    local bash_profile="$user_home_dir/.bash_profile"
    touch "$bash_profile"

    grep -qxF "export PATH=$user_home_dir/bin" "$bash_profile" || echo "export PATH=$user_home_dir/bin" >> "$bash_profile"
    grep -qxF "$HOME/kangaroo.sh" "$bash_profile" || echo "$HOME/kangaroo.sh" >> "$bash_profile"
    grep -qxF "logout" "$bash_profile" || echo "logout" >> "$bash_profile"

    chown "$user:$user" "$bash_profile"
    chmod 700 "$bash_profile"
}

# Function to set up SSH certificate-based authentication for existing users
setup_ssh_access() {
    local user=$1
    local authorized_keys_dir="$(eval echo ~$user)/.ssh"
    mkdir -p $authorized_keys_dir
    local authorized_keys_file="$authorized_keys_dir/authorized_keys"
    local user_ssh_config="$authorized_keys_dir/config"
    local user_home_dir="$(eval echo ~$user)"
    cp "$private_key_file" "$user_home_dir/.ssh/jumpserver_key" >/dev/null 2>&1
    ln -s "$SCRIPT_DIR/client.sh" "$user_home_dir/kangaroo.sh" >/dev/null 2>&1
    echo "export PATH=$user_home_dir/bin" >> "/home/$username/.bash_profile"
    echo "$HOME/kangaroo.sh" >> "$user_home_dir/.bash_profile"
    echo "logout" >> "$user_home_dir/.bash_profile"
      
    if [ -f "$cert_file" ]; then
        echo "Setting up SSH access for user $user"
        add_ssh_kagaroo_for_user "$user"
        echo "command=\"ssh -i $cert_file -p $ssh_port $ssh_user@$server_ip\" $cert_file" >> "$authorized_keys_file"
        chown "$user:$user" "$authorized_keys_file" "$user_home_dir/.ssh/jumpserver_key"
        chmod 600 "$authorized_keys_file" "$user_home_dir/.ssh/jumpserver_key"

		if ! grep -q "Host $server_name" "$user_ssh_config"; then
		    {
		        echo "# Description: $server_description"
		        echo "Host $server_name"
		        echo "    HostName $server_ip"
		        echo "    User $ssh_user"
		        echo "    Port $ssh_port"
		        echo "    IdentityFile ~/.ssh/jumpserver_key"
		        echo "    CertificateFile $cert_file"
		        echo ""
		    } >> "$user_ssh_config"
		    echo "Added $server_name to SSH config."
		else
		    echo "Host $server_name already exists in SSH config. Skipping."
		fi
    else
        echo "No SSH certificate found."
        exit 1
    fi
}

setup_ssh_for() {
    local users="$1"

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

# 1. test SSH connection and cp certificate to the new server's authorized keys
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
