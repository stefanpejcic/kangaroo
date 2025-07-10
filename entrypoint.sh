#!/bin/bash

CONFIG_FILE="/etc/users.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing config file: $CONFIG_FILE"
    exit 1
fi

python3 - <<'EOF'
import yaml
import subprocess
import os
import pwd

with open("/etc/users.conf", "r") as f:
    config = yaml.safe_load(f)

all_servers = config.get("servers", {})

for user in config.get("users", []):
    username = user["username"]
    password = user.get("password")
    ssh_key = user.get("ssh_key")
    user_servers_names = user.get("servers", [])
    home_dir = f"/home/{username}"

    # Check if user exists
    try:
        pwd.getpwnam(username)
        print(f"User '{username}' already exists. Skipping creation.")
    except KeyError:
        subprocess.run(["useradd", "-m", "-s", "/usr/local/bin/connect-to", username], check=True)
        subprocess.run(['chpasswd'], input=f"{username}:{password}".encode(), check=True)

    ssh_dir = os.path.join(home_dir, ".ssh")
    os.makedirs(ssh_dir, mode=0o700, exist_ok=True)

    if ssh_key:
        auth_keys_path = os.path.join(ssh_dir, "authorized_keys")
        with open(auth_keys_path, "w") as ak:
            ak.write(ssh_key + "\n")
        uid = pwd.getpwnam(username).pw_uid
        gid = pwd.getpwnam(username).pw_gid
        os.chown(ssh_dir, uid, gid)
        os.chown(auth_keys_path, uid, gid)
        os.chmod(auth_keys_path, 0o600)

    # Collect user's allowed server details
    user_servers = {name: all_servers[name] for name in user_servers_names if name in all_servers}

    user_config_path = os.path.join(home_dir, "servers.yaml")
    with open(user_config_path, "w") as f:
        yaml.dump(user_servers, f)
    os.chown(user_config_path, uid, gid)
EOF

# Start SSH daemon in foreground
exec /usr/sbin/sshd -D
