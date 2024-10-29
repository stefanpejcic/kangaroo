#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Get username input
read -p "Enter username for the new user: " username

# Add the user with rbash as their shell
useradd -m -s /bin/rbash "$username"

# Set password for the user
passwd "$username"

# Generate SSH key pair if it doesn't exist
if [ ! -f "/home/$username/.ssh/id_rsa" ]; then
    echo "Generating SSH key pair for user $username..."
    sudo -u "$username" ssh-keygen -t rsa -b 4096 -f "/home/$username/.ssh/id_rsa" -q -N ""
fi

# Create .ssh directory for authorized keys if not exists
mkdir -p "/home/$username/.ssh"
touch "/home/$username/.ssh/authorized_keys"

# Copy public key to authorized_keys
cat "/home/$username/.ssh/id_rsa.pub" >> "/home/$username/.ssh/authorized_keys"

# Set permissions for .ssh directory and files
chown -R "$username:$username" "/home/$username/.ssh"
chmod 700 "/home/$username/.ssh"
chmod 600 "/home/$username/.ssh/authorized_keys"

# Create a symbolic link to the existing choose_server.sh in the user's home directory
ln -s /root/openjumpserver/server/client.sh "/home/$username/choose_server.sh"

# Set the restricted PATH to include user's home bin directory
echo 'export PATH=$HOME/bin' >> "/home/$username/.bash_profile"

# Append commands to .bash_profile to run the script and log out
echo "$HOME/choose_server.sh" >> "/home/$username/.bash_profile"
echo "logout" >> "/home/$username/.bash_profile"

# Set ownership of the .bash_profile and the symlink to the new user
chown "$username:$username" "/home/$username/.bash_profile"

# Set correct permissions for security
chmod 700 "/home/$username/.bash_profile"

echo "User $username created and configured with SSH access to the JumpServer."
