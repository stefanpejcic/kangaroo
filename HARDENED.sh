#!/bin/bash

: '
CREATE FILE server/ips AND IN IT SET YOUR TEAM IP ADDRESSES ONE PER LINE
THEN RUN THIS SCRIPT TO RESTRICT INCOMING ACCESS ONLY TO THOSE IP ADDRESSES
'

set -euo pipefail

SCRIPT_ABS_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_ABS_PATH")
IP_FILE="$SCRIPT_DIR/server/ips"

[[ -f "$IP_FILE" ]] || { echo "ERROR: IP file not found: $IP_FILE"; exit 1; }

mapfile -t ALLOWED < <(grep -Ev '^\s*#|^\s*$' "$IP_FILE")

[[ ${#ALLOWED[@]} -eq 0 ]] && { echo "ERROR: No IPs found in $IP_FILE"; exit 1; }

echo "Allowing inbound from: ${ALLOWED[*]}"

### Flush
iptables -F
iptables -X
iptables -Z
ip6tables -F
ip6tables -X
ip6tables -Z

### Default policies
iptables  -P INPUT   DROP
iptables  -P FORWARD DROP
iptables  -P OUTPUT  ACCEPT   # outbound unrestricted

ip6tables -P INPUT   DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT  ACCEPT   # outbound unrestricted

### Loopback
iptables -A INPUT -i lo -j ACCEPT

### Established inbound (return traffic for outbound connections)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

### Whitelist inbound
for IP in "${ALLOWED[@]}"; do
  iptables -A INPUT -s "$IP" -j ACCEPT
done

### Persist
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save
elif command -v iptables-save &>/dev/null; then
  mkdir -p /etc/iptables/
  iptables-save  > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6
  echo "Rules saved to /etc/iptables/rules.v{4,6}"
  echo "InstallING persistence:"
  apt install iptables-persistent -y
fi

echo "Done. Active rules:"
iptables -L -n -v --line-numbers
