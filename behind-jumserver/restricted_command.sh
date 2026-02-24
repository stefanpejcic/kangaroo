#!/bin/bash
# /usr/local/bin/restricted_command.sh
LOG_TAG="ssh-restricted"

log_command() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t "$LOG_TAG" "[$timestamp] User: $(whoami) Command: $*"
}

disabled_commands=("rm" "shutdown" "reboot" "--delete" "mkfs"  "dd")

while true; do
    read -ep "$(whoami)@$(hostname):~$ " user_cmd || break

    [[ -z "$user_cmd" ]] && continue

    log_command "$user_cmd"

    for cmd in "${disabled_commands[@]}"; do
        if [[ "$user_cmd" == *"$cmd"* ]]; then
            echo "Error: Command '$cmd' is disabled."
            log_command "[BLOCKED] Attempted blocked command: $cmd"
            continue 2
        fi
    done

    bash -c "$user_cmd"
done
