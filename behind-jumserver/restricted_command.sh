#!/bin/bash
# /usr/local/bin/restricted_shell.sh
LOG_TAG="ssh-restricted"

log_command() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t "$LOG_TAG" "[$timestamp] User: $(whoami) Command: $*"
}

# List of disabled commands (adjust as needed)
disabled_commands=("rm" "shutdown" "reboot" "--delete")

# Start an interactive shell with restricted commands
while true; do
    read -ep "$(whoami)@$(hostname):~$ " user_cmd || break

    # Skip empty input
    [[ -z "$user_cmd" ]] && continue

    # Log the command
    log_command "$user_cmd"

    # Check for disabled commands
    for cmd in "${disabled_commands[@]}"; do
        if [[ "$user_cmd" == *"$cmd"* ]]; then
            echo "Error: Command '$cmd' is disabled."
            log_command "[BLOCKED] Attempted blocked command: $cmd"
            continue 2
        fi
    done

    # Execute the command
    bash -c "$user_cmd"
done
