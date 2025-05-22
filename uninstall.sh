#!/bin/bash

# Define variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/jump_servers.conf"
SSHD_CONFIG="/etc/ssh/sshd_config"
CLIENT_SCRIPT="${SCRIPT_DIR}/server/client.sh"

remove_logs() {
  rm -rf /var/log/remote >/dev/null
  if grep -q 'Kangaroo SSH JumpServer' "/etc/rsyslog.d/remote.conf"; then
      echo "Reverting sshd_config changes..."
      sed -i '/##### 🦘 Kangaroo SSH JumpServer #####/,+3d' "/etc/rsyslog.d/remote.conf"
      echo "Restarting rsyslog service..."
      systemctl restart rsyslog
  fi
}

remove_ssh_force_command() {
  if grep -q 'Kangaroo SSH JumpServer' "$SSHD_CONFIG"; then
      echo "Reverting sshd_config changes..."
      # Backup first
      cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
  
      # Remove block between the start comment and ForceCommand line
      sed -i '/##### 🦘 Kangaroo SSH JumpServer #####/,+4d' "$SSHD_CONFIG"
  
      # Restart SSH service
      echo "Restarting SSH service..."
      systemctl restart ssh 
  fi
}

uninstall_fzf() {
  if dpkg -l | grep -q '^ii\s*fzf'; then
          echo "Removing fzf..."
          apt remove -y fzf
  fi
}

remove_git_dir() {
  if [ -f "$CLIENT_SCRIPT" ]; then
      read -p "Do you want to delete the client script? [y/N]: " DELETE_SCRIPT
      if [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]]; then
          echo "Deleting $CLIENT_SCRIPT..."
          rm -rf "$SCRIPT_DIR"
      fi
  fi
}


remove_for_all_users() {
   existing_users=$(awk -F: '($7 == "/bin/bash" || $7 == "/bin/sh") {print $1}' /etc/passwd)
       for user in $existing_users; do
          if [ "$user" != "root" ]; then
            ssh_dir="$(eval echo ~$user)/.ssh" 
            rm -rf "$ssh_dir/authorized_keys" "$ssh_dir/jumpserver_key" "$ssh_dir/config"
          fi
       done
}


# main
echo "🧹 Uninstalling Kangaroo SSH JumpServer..."
remove_ssh_force_command
remove_logs
uninstall_fzf
remove_for_all_users
remove_git_dir
echo "✅ Uninstallation complete."
