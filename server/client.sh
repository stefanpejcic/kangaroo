#!/bin/bash

# Path to the server list
server_list="/etc/server_list"

while true; do
    echo "Available Servers:"

    # Load server list and format it for fzf
    server_selection=$(awk '{print $1 " - " $2 " (" $3 ")"}' "$server_list" | fzf --prompt="Select a server: ")

    # If the user presses Esc or Ctrl+C in fzf, it will exit
    if [[ -z "$server_selection" ]]; then
        echo "Exiting..."
        exit 0
    fi

    # Extract server name and IP from the selection
    server_name=$(echo "$server_selection" | awk '{print $1}')
    server_ip=$(grep "^$server_name" "$server_list" | awk '{print $2}')

    echo "Connecting to $server_name ($server_ip)..."
    ssh "$server_ip"
    echo -e "\nDisconnected from $server_name. Returning to server selection..."
done
