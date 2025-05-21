#!/bin/bash

trap '' SIGINT SIGTERM SIGTSTP

ssh_config="$HOME/.ssh/config"

if [ ! -f "$ssh_config" ]; then
    echo "No servers configured for user. Aborting."
    exit 1
fi

available_servers=$(awk '/^Host / {host=$2} /^# Description: / {desc=$3} host {print host " - " desc; host=""}' "$ssh_config")

if [[ -z "$available_servers" ]]; then
    echo "No servers configured for user. Aborting."
    exit 1
fi

while true; do
    server_selection=$(echo "$available_servers" | fzf --prompt="Select server: ")

    # If the user presses Esc or Ctrl+C in fzf, exit
    if [[ -z "$server_selection" ]]; then
        echo "Exiting..."
        exit 0
    fi

    # Extract server name from selection
    server_name=$(echo "$server_selection" | awk '{print $1}')

    # Connect to the selected server
    echo "Connecting to $server_name..."
    ssh -o StrictHostKeyChecking=no "$server_name"
    echo -e "\nDisconnected from $server_name. Returning to server selection..."
done
