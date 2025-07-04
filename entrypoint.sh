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

with open("/etc/users.conf", "r") as f:
    config = yaml.safe_load(f)

for user in config.get("users", []):
    username = user["username"]
    password = user.get("password")
    ssh_key = user.get("ssh_key")
    home_dir = f"/home/{username}"

    subprocess.run(["useradd", "-ms", "/bin/bash", username])
    subprocess.run(["bash", "-c", f"echo '{username}:{password}' | chpasswd"])

    os.makedirs(f"{home_dir}/.ssh", exist_ok=True)
    if ssh_key:
        with open(f"{home_dir}/.ssh/authorized_keys", "w") as ak:
            ak.write(ssh_key + "\n")
        subprocess.run(["chown", "-R", f"{username}:{username}", f"{home_dir}/.ssh"])
        subprocess.run(["chmod", "600", f"{home_dir}/.ssh/authorized_keys"])

    # Save per-user server list
    servers = user.get("servers", [])
    user_config_path = f"{home_dir}/servers.yaml"
    with open(user_config_path, "w") as f:
        yaml.dump(servers, f)
    subprocess.run(["chown", f"{username}:{username}", user_config_path])
EOF

# Start SSH daemon
exec /usr/sbin/sshd -D
