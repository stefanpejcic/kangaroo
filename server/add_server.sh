#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# variables
cert_file="/etc/ssh/ssh_host_rsa_key.pub"
private_key_file="/etc/ssh/ssh_host_rsa_key"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jump_servers.conf"
server_description=""
server_name=""
server_ip=""
ssh_user="root" #maybe?
ssh_port=22
ssh_password=""
selected_users=""

# Parse long options
for arg in "$@"; do
  case $arg in
    --description=*)
      server_description="${arg#*=}"
      shift
      ;;
    --name=*)
      server_name="${arg#*=}"
      shift
      ;;
    --ip=*)
      server_ip="${arg#*=}"
      shift
      ;;
    --user=*)
      ssh_user="${arg#*=}"
      shift
      ;;
    --port=*)
      ssh_port="${arg#*=}"
      shift
      ;;
    --password=*)
      ssh_password="${arg#*=}"
      shift
      ;;
    --users=*)
      selected_users="${arg#*=}"
      shift
      ;;
    *)
      # unknown option
      ;;
  esac
done




# Prompts
if [[ -z "$server_description" ]]; then
  read -p "Enter the server description: " server_description
fi

if [[ -z "$server_name" ]]; then
  read -p "Enter the server name (e.g., webserver1): " server_name
fi

if [[ -z "$server_ip" ]]; then
  read -p "Enter the server IP address: " server_ip
fi

if [[ -z "$ssh_user" ]]; then
  read -p "Enter SSH username for the new server: " ssh_user
  ssh_user=${ssh_user:-root}
fi

if [[ -z "$ssh_port" ]]; then
  read -p "Enter SSH port for the new server (default 22): " ssh_port
  ssh_port=${ssh_port:-22}
fi


# Add server to a configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi


# Copy the certificate to the new server's authorized keys
echo "Copying SSH certificate to the new server..."

if [[ -z "$server_description" ]]; then
   echo "Insert password for $ssh_user@$server_ip:$ssh_port"
   read -r USERPASS
else
   USERPASS="$ssh_password"
fi

clear 

# check first
if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass not found. Installing..."
    apt update -qq >/dev/null && apt install -y -qq sshpass >/dev/null
    echo "sshpass installed successfully."
    clear
fi

# run!
echo "$USERPASS" | sshpass ssh-copy-id -p "$ssh_port" -o StrictHostKeyChecking=no -f -i "$cert_file" "$ssh_user@$server_ip" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Error copying SSH key to remote server."
    echo "Please try manually with the following command:"
    echo "sshpass -p '$USERPASS' ssh-copy-id -p $ssh_port -o StrictHostKeyChecking=no -i $cert_file $ssh_user@$server_ip"
    exit 1
fi

# Create user-specific SSH config in root home directory
user_ssh_config="$HOME/.ssh/config"

# Ensure the user has an SSH config file
if [ ! -f "$user_ssh_config" ]; then
    touch "$user_ssh_config"
    chmod 600 "$user_ssh_config"
fi

# add for root
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

# Function to set up SSH certificate-based authentication for existing users
setup_ssh_access() {
    local user=$1
    local authorized_keys_dir="/home/$user/.ssh"
    mkdir -p $authorized_keys_dir
    local authorized_keys_file="$authorized_keys_dir/authorized_keys"
    local user_ssh_config="$authorized_keys_dir/config"
    
    ln -s $private_key_file /home/$user/.ssh/jumpserver_key >/dev/null

    if [ -f "$cert_file" ]; then
        echo "Setting up SSH access for user $user"
        echo "command=\"ssh -i $cert_file -p $ssh_port $ssh_user@$server_ip\" $cert_file" >> "$authorized_keys_file"
        chown "$user:$user" "$authorized_keys_file"
        chmod 600 "$authorized_keys_file"

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


        
    else
        echo "No SSH certificate found."
        exit 1
    fi
}


setup_for_all_users() {
   existing_users=$(awk -F: '($7 == "/bin/bash" || $7 == "/bin/sh") {print $1}' /etc/passwd)
       for user in $existing_users; do
           setup_ssh_access "$user"
       done
}

setup_for_some_users() {
   users="$1"
   for user in $users; do
         if id "$user" &>/dev/null; then
            setup_ssh_access "$user"
         else
            echo "User $user does not exist."
         fi
   done
}

# Set up SSH access for all existing users or specified users
if [[ -z "$selected_users" ]]; then
   read -p "Do you want to set up SSH access for all existing users? (y/n): " add_to_all
   if [[ "$add_to_all" =~ ^[Yy]$ ]]; then
      setup_for_all_users
   else
       read -p "Enter the usernames to setup SSH access for (space-separated): " specific_users
       setup_for_some_users "$specific_users"
   fi
else
   if [[ "$selected_users" == "all" ]]; then
      setup_for_all_users
   else
      setup_for_some_users "$selected_users"
   fi
fi

echo "$server_name $server_ip" >> "$CONFIG_FILE"

clear
echo "Server $server_name ($server_ip:$ssh_port) added, and SSH access configured using certificates from Kangaroo 🦘"

exit 0
