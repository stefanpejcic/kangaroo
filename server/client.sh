#!/bin/bash

SCRIPT_PATH="$0"
SCRIPT_ABS_PATH=$(readlink -f "$SCRIPT_PATH")
SCRIPT_DIR=$(dirname "$SCRIPT_ABS_PATH")
LOGFILE="$SCRIPT_DIR/ssh_login.log"
USER_NAME=$(whoami)
IP_ADDRESS=$(echo $SSH_CONNECTION | awk '{print $1}')
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "User: $USER_NAME connected from IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE

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
