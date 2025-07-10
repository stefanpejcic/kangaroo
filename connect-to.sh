#!/bin/bash

USER_CONFIG="/home/$USER/servers.yaml"
USER_CODE_FILE="/home/$USER/code"
USER_LOG_FILE="/home/$USER/connection.log"
PS3="Select a server to connect to (or 0 to exit): "

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$USER_LOG_FILE"
}

# Check if user code file exists
if [[ -f "$USER_CODE_FILE" ]]; then
  read -r expected_code < "$USER_CODE_FILE"

  tries=0
  max_tries=3
  while (( tries < max_tries )); do
    read -rsp "Enter your access code: " input_code
    echo
    if [[ "$input_code" == "$expected_code" ]]; then
      log "Access code correct on attempt $((tries + 1))"
      echo "Access code accepted."
      break
    else
      log "Incorrect access code attempt $((tries + 1))"
      echo "Incorrect code."
      ((tries++))
    fi
  done

  if (( tries == max_tries )); then
    log "Too many failed code attempts, aborting."
    echo "Too many failed attempts. Aborting."
    exit 1
  fi
else
  log "No access code required."
fi

if [[ ! -f "$USER_CONFIG" ]]; then
  log "No server list configured."
  echo "No server list configured for user $USER."
  exit 1
fi

while true; do
  mapfile -t servers < <(awk '/name:/ {print $2}' "$USER_CONFIG")

  if [[ ${#servers[@]} -eq 0 ]]; then
    log "No servers defined."
    echo "No servers defined."
    exit 1
  fi

  echo "Welcome $USER! Available servers:"
  log "User started server selection."

  select srv in "${servers[@]}" "Exit"; do
    if [[ "$srv" == "Exit" || "$srv" == "" ]]; then
      log "User exited server selection."
      echo "Goodbye!"
      exit 0
    fi

    ssh_user=$(awk -v s="$srv" '
      $1 == "name:" && $2 == s {getline; getline; print $2}
    ' "$USER_CONFIG")

    ssh_host=$(awk -v s="$srv" '
      $1 == "name:" && $2 == s {getline; getline; getline; print $2}
    ' "$USER_CONFIG")

    if [[ -z "$ssh_user" || -z "$ssh_host" ]]; then
      log "Invalid server selection: $srv"
      echo "Invalid selection."
      break
    fi

    log "Connecting to $srv ($ssh_user@$ssh_host)."
    echo "Connecting to $srv ($ssh_user@$ssh_host)..."
    ssh "$ssh_user@$ssh_host"
    log "Returned from $srv."
    echo "Returned from $srv."
    break
  done
done
