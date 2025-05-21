#!/bin/bash
set -m

trap '' SIGINT SIGTERM SIGTSTP

# Path to SSH config
ssh_config="$HOME/.ssh/config"

# Extract the host names and descriptions from the SSH config
available_servers=$(awk '/^Host / {host=$2} /^# Description: / {desc=$3} host {print host " - " desc; host=""}' "$ssh_config")

# Prompt user to select a server using fzf
while true; do
    server_selection=$(echo "$available_servers" | fzf --prompt="Select a server: ")

    # If the user presses Esc or Ctrl+C in fzf, exit
    if [[ -z "$server_selection" ]]; then
        echo "Exiting..."
        exit 0
    fi

    # Extract server name from selection
    server_name=$(echo "$server_selection" | awk '{print $1}')

    # Connect to the selected server
    echo "Connecting to $server_name..."
    ssh "$server_name"
    echo -e "\nDisconnected from $server_name. Returning to server selection..."
done
