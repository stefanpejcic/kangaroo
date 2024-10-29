#!/bin/bash
# /usr/local/bin/restricted_command.sh

# Check if a command was passed
if [ $# -eq 0 ]; then
    echo "No command specified."
    exit 1
fi

# List of disabled commands
disabled_commands=("rm" "shutdown" "reboot" "--delete")

# Check all arguments against the list of disabled commands
for arg in "$@"; do
    for cmd in "${disabled_commands[@]}"; do
        if [[ "$arg" == "$cmd" ]]; then
            echo "Error: Command '$cmd' is disabled."
            exit 1
        fi
    done
done

# Allow all other commands
exec "$@"
