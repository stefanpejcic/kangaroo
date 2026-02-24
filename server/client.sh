#!/bin/bash

SCRIPT_PATH="$0"
SCRIPT_ABS_PATH=$(readlink -f "$SCRIPT_PATH")
SCRIPT_DIR=$(dirname "$SCRIPT_ABS_PATH")
LOGFILE="$SCRIPT_DIR/logs/ssh_login.log"
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

raw_servers=$(awk '
    /^Host / { host=$2 } 
    /^[[:space:]]*HostName / { hostname=$2 } 
    /^# Description: / { desc=substr($0, index($0,$3)) } 
    host && hostname && desc {
        print host "|" hostname "|" desc
        host=""; hostname=""; desc=""
    }
' "$ssh_config")

if [[ -z "$raw_servers" ]]; then
    echo "No servers configured. Aborting."
    exit 1
fi

draw_banner() {
    local width=$(tput cols)
    local line=$(printf '━%.0s' $(seq 1 $width))
    echo -e "\e[1;34m$line\e[0m"
    echo -e "  \e[1m🦘 Kangaroo SSH\e[0m"
    echo -e "  https://github.com/stefanpejcic/kangaroo"
    echo -e "\e[1;34m$line\e[0m"
}

while true; do
# Get current terminal width
    term_width=$(tput cols)
    
    # Define column widths (percentages)
    col1_w=$(( term_width * 25 / 100 ))
    col2_w=$(( term_width * 25 / 100 ))
    col3_w=$(( term_width - col1_w - col2_w - 5 )) # Remaining space

    # 2. Manually format the rows to fill the terminal width
    formatted_list=$(echo "$raw_servers" | while IFS="|" read -r name ip desc; do
        printf "%-${col1_w}s %-${col2_w}s %-${col3_w}s\n" "$name" "$ip" "$desc"
    done)

    # Create the aligned header
    header_row=$(printf "\e[1;37m%-${col1_w}s %-${col2_w}s %-${col3_w}s\e[0m" "NAME" "IP" "DESCRIPTION")
    full_header="$(draw_banner)\n$header_row\n"

    selection=$(echo "$formatted_list" | \
        fzf --header "$(echo -e "$full_header")" \
            --layout=reverse \
            --height 100% \
            --border none \
            --no-hscroll \
            --info inline \
            --color="header:bold:blue,prompt:bold:yellow,pointer:bold:red" \
            --prompt="Search Host > ")
        
    # If the user presses Esc or Ctrl+C in fzf, exit
    if [[ -z "$selection" ]]; then
        echo "Exiting..."
        exit 0
    fi
    
    server_name=$(echo "$selection" | awk '{print $1}')
    DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')  
    echo "User: $USER_NAME connected to server: $server_name using IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE

    # Connect to the selected server
    echo "Connecting to $server_name..."
    ssh -o StrictHostKeyChecking=no "$server_name"
    echo -e "\nDisconnected from $server_name. Returning to server selection..."
    DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')  
    echo "User: $USER_NAME disconnected from server: $server_name using IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE
done
