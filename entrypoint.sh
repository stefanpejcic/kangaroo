#!/bin/bash

CONFIG_FILE="/etc/users.conf"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ENTRYPOINT] $*"
}

log "========================================"
log "   Starting User Setup and SSH Daemon   "
log "========================================"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log "FATAL ERROR: Missing config file: $CONFIG_FILE"
    exit 1
fi

log "Loading configuration from $CONFIG_FILE"

USER_COUNT=$(python3 - <<'EOF'
import yaml
import subprocess
import os
import pwd
from datetime import datetime

def log(msg):
    print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} [PYTHON] {msg}", flush=True)

config_path = "/etc/users.conf"

log(f"Reading config file: {config_path}")
with open(config_path, "r") as f:
    config = yaml.safe_load(f)

all_servers = config.get("servers", {})
log(f"Found {len(all_servers)} servers in config")

users = config.get("users", [])

for user in users:
    username = user["username"]
    password = user.get("password")
    ssh_key = user.get("ssh_key")
    user_servers_names = user.get("servers", [])
    home_dir = f"/home/{username}"
    email = user.get("email", "")
    code = user.get("code", "")

    try:
        pw_record = pwd.getpwnam(username)
        log(f"User '{username}' already exists. Skipping creation.")
    except KeyError:
        log(f"Creating user '{username}'")
        subprocess.run(["useradd", "-m", "-s", "/usr/local/bin/connect-to", username], check=True)
        if password:
            subprocess.run(['chpasswd'], input=f"{username}:{password}".encode(), check=True)
        pw_record = pwd.getpwnam(username)

    uid, gid = pw_record.pw_uid, pw_record.pw_gid

    ssh_dir = os.path.join(home_dir, ".ssh")
    os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
    os.chown(ssh_dir, uid, gid)
    log(f"Ensured .ssh directory for user '{username}'")

    if ssh_key:
        auth_keys_path = os.path.join(ssh_dir, "authorized_keys")
        with open(auth_keys_path, "w") as ak:
            ak.write(ssh_key + "\n")
        os.chown(auth_keys_path, uid, gid)
        os.chmod(auth_keys_path, 0o600)
        log(f"Written authorized_keys for user '{username}'")

    user_servers = {name: all_servers[name] for name in user_servers_names if name in all_servers}
    user_config_path = os.path.join(home_dir, "servers.yaml")
    with open(user_config_path, "w") as f:
        yaml.dump(user_servers, f)
    os.chown(user_config_path, uid, gid)
    log(f"Written servers.yaml for user '{username}' with {len(user_servers)} servers")

    if code:
        code_path = os.path.join(home_dir, "code")
        with open(code_path, "w") as cf:
            cf.write(code + "\n")
        os.chown(code_path, uid, gid)
        os.chmod(code_path, 0o600)
        log(f"Written code file for user '{username}'")

log(f"User setup completed for {len(users)} users")

print(len(users))  # This will be captured by bash as USER_COUNT
EOF
)

log "Processed $USER_COUNT users"

log "Starting SSH daemon"
/usr/sbin/sshd -D
