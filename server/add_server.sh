#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Define variables
CA_KEY="/etc/ssh/ca_key"
CONFIG_FILE="/etc/jump_servers.conf"

# Ensure the CA keys exist
if [ ! -f "$CA_KEY" ]; then
    echo "SSH Certificate Authority keys not found. Generating..."
    ssh-keygen -f $CA_KEY -C "Kangaroo CA" -N ""
    #exit 1
fi

# Get server details from user
read -p "Enter the server description: " server_description
read -p "Enter the server name (e.g., webserver1): " server_name
read -p "Enter the server IP address: " server_ip
read -p "Enter SSH username for the new server: " ssh_user

# Add server to a configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

# Add the new server to the configuration file
echo "$server_name $server_ip" >> "$CONFIG_FILE"

# Generate the SSH certificate for the user
cert_file="/etc/ssh/authorized_keys_${server_name}.cert"

# Create the SSH certificate
ssh-keygen -s "$CA_KEY" -I "$server_name" -n "$ssh_user" -V +52w "$cert_file"

# Copy the certificate to the new server's authorized keys
ssh_command="ssh-copy-id -i $cert_file $ssh_user@$server_ip"

echo "Copying SSH certificate to the new server..."
eval $ssh_command

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
    echo "    IdentityFile ~/.ssh/jumpserver_key"
    echo "    CertificateFile $cert_file"
    echo ""
} >> "$user_ssh_config"

# Function to set up SSH certificate-based authentication for existing users
setup_ssh_access() {
    local user=$1
    local authorized_keys_file="/home/$user/.ssh/authorized_keys"
    local user_ssh_config="/home/$user/.ssh/config"
    if [ -f "$cert_file" ]; then
        echo "Setting up SSH access for user $user..."
        echo "command=\"ssh -i $cert_file $ssh_user@$server_ip\" $cert_file" >> "$authorized_keys_file"
        chown "$user:$user" "$authorized_keys_file"
        chmod 600 "$authorized_keys_file"

{
    echo "# Description: $server_description"
    echo "Host $server_name"
    echo "    HostName $server_ip"
    echo "    User $ssh_user"
    echo "    IdentityFile ~/.ssh/jumpserver_key"
    echo "    CertificateFile $cert_file"
    echo ""
} >> "$user_ssh_config"


        
    else
        echo "No SSH certificate found for the new server."
    fi
}

# Set up SSH access for all existing users or specified users
read -p "Do you want to set up SSH access for all existing users? (y/n): " add_to_all

# Get existing users
existing_users=$(cut -f1 -d: /etc/passwd | grep -v '^root$')

if [[ "$add_to_all" =~ ^[Yy]$ ]]; then
    for user in $existing_users; do
        setup_ssh_access "$user"
    done
else
    read -p "Enter the usernames to add (space-separated): " specific_users
    for user in $specific_users; do
        if id "$user" &>/dev/null; then
            setup_ssh_access "$user"
        else
            echo "User $user does not exist."
        fi
    done
fi

echo "Server $server_name ($server_ip) added, and SSH access configured using certificates from JumpServer."
