#!/bin/bash

set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_PATH="$0"
SCRIPT_ABS_PATH=$(readlink -f "$SCRIPT_PATH")
SCRIPT_DIR=$(dirname "$SCRIPT_ABS_PATH")
LOGFILE="$SCRIPT_DIR/logs/ssh_login.log"
USER_NAME=$(whoami)
IP_ADDRESS=$(echo $SSH_CONNECTION | awk '{print $1}')
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "User: $USER_NAME connected from IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE

trap '' SIGINT SIGTERM SIGTSTP EXIT

ssh_config="$HOME/.ssh/config"

if [ ! -f "$ssh_config" ]; then
    echo "No servers exist. Contact Administrator"
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
' "$ssh_config" | sort -t '|' -k1,1)

if [[ -z "$raw_servers" ]]; then
    echo "No servers authorized. Contact Administrator."
    exit 1
fi

draw_banner() {
    local width=$(tput cols)
    local line=$(printf '━%.0s' $(seq 1 $width))
    echo -e "\e[1;34m$line\e[0m"
    if [[ -f "$SCRIPT_DIR/logo" ]]; then
        while IFS= read -r l; do
            echo -e "\e[1;32m$l\e[0m"
        done < "$SCRIPT_DIR/logo"
    else
        echo ""
        echo -e "  \e[1m🦘 Kangaroo SSH JumpServer\e[0m"
        echo -e "  https://github.com/stefanpejcic/kangaroo"
    fi
    echo ""
    echo -e "  \e[1mChoose a server from the list below or type to search.\e[0m"
    echo -e "\e[1;34m$line\e[0m"
}

# TODO: mv
chmod 775 /var/run/tlog > /dev/null 2>&1

while true; do
    term_width=$(tput cols)
    col1_w=$(( term_width * 25 / 100 ))
    col2_w=$(( term_width * 25 / 100 ))
    col3_w=$(( term_width - col1_w - col2_w - 5 ))

    formatted_list=$(echo "$raw_servers" | while IFS="|" read -r name ip desc; do
        printf "%-${col1_w}s %-${col2_w}s %-${col3_w}s\n" "$name" "$ip" "$desc"
    done)

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

    [[ -z "$selection" ]] && exit 0
    
    server_name=$(echo "$selection" | awk '{print $1}')
    if ! echo "$raw_servers" | grep -q "^$server_name|"; then
        echo "Unauthorized server selection."
        continue
    fi
    
    DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')  
    echo "User: $USER_NAME connected to server: $server_name using IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE

    # Connect to the selected server
    echo "Connecting to $server_name..."
    /usr/bin/tlog-rec-session -c "/usr/bin/ssh -o StrictHostKeyChecking=no -a -F $server_name"
    echo -e "\nDisconnected from $server_name. Returning to server selection..."
    DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')  
    echo "User: $USER_NAME disconnected from server: $server_name using IP: $IP_ADDRESS at $DATE_TIME" >> $LOGFILE
done
