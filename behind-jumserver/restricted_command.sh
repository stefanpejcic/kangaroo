#!/bin/bash
# /usr/local/bin/restricted_command.sh
LOG_TAG="ssh-restricted"


log_command() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t $LOG_TAG "[$timestamp] User: $(whoami) Command: $*"
}

# Check if a command was passed
if [ $# -eq 0 ]; then
    echo "No command specified."
    #exit 1
fi

log_command "$@"

# List of disabled commands
disabled_commands=("rm" "shutdown" "reboot" "--delete")

for arg in "$@"; do
    for cmd in "${disabled_commands[@]}"; do
        if [[ "$arg" == "$cmd" ]]; then
            log_command "[BLOCKED] Attempted blocked command: $cmd"
            echo "Error: Command '$cmd' is disabled."
            exit 1
        fi
    done
done

exec "$@"
