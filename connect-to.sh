#!/bin/bash

USER_CONFIG="/home/$USER/servers.yaml"
PS3="Select a server to connect to (or 0 to exit): "

if [[ ! -f "$USER_CONFIG" ]]; then
  echo "No server list configured for user $USER."
  exit 1
fi

while true; do
  mapfile -t servers < <(awk '/name:/ {print $2}' "$USER_CONFIG")

  if [[ ${#servers[@]} -eq 0 ]]; then
    echo "No servers defined."
    exit 1
  fi

  echo "Welcome $USER! Available servers:"

  select srv in "${servers[@]}" "Exit"; do
    if [[ "$srv" == "Exit" || "$srv" == "" ]]; then
      echo "Goodbye!"
      exit 0
    fi

    # Lookup user and host from servers.yaml
    ssh_user=$(awk -v s="$srv" '
      $1 == "name:" && $2 == s {getline; getline; print $2}
    ' "$USER_CONFIG")

    ssh_host=$(awk -v s="$srv" '
      $1 == "name:" && $2 == s {getline; getline; getline; print $2}
    ' "$USER_CONFIG")

    if [[ -z "$ssh_user" || -z "$ssh_host" ]]; then
      echo "Invalid selection."
      break
    fi

    echo "Connecting to $srv ($ssh_user@$ssh_host)..."
    ssh "$ssh_user@$ssh_host"

    echo "Returned from $srv."
    break
  done
done
