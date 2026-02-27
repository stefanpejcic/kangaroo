#!/usr/bin/env python3
"""Kangaroo SSH JumpServer 🦘 - manages SSH configs across system users."""

import os
import sys
import pwd
import secrets
import socket
import subprocess
import threading
from collections import defaultdict
from pathlib import Path

import click

# ---------------------------------------------------------------------------
# Constants / paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
KANGAROO_KEY = Path("/etc/ssh/kangaroo_key_id_rsa")
SERVERS_CONF = SCRIPT_DIR / "jump_servers.conf"
TOKEN_FILE = SCRIPT_DIR / ".kangaroo_token"
MASTER_PORT_FILE = SCRIPT_DIR / ".kangaroo_master_port"

DEFAULT_MASTER_PORT = 7437


# ---------------------------------------------------------------------------
# Token management
# ---------------------------------------------------------------------------

def get_or_create_token() -> str:
    """Return the persistent master token, creating it if necessary."""
    if TOKEN_FILE.is_file():
        return TOKEN_FILE.read_text().strip()
    token = secrets.token_urlsafe(32)
    TOKEN_FILE.write_text(token)
    TOKEN_FILE.chmod(0o600)
    return token


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

def require_root() -> None:
    if os.geteuid() != 0:
        click.echo("Run as root", err=True)
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# SSH config parsing
# ---------------------------------------------------------------------------

def parse_ssh_config(path: str | Path) -> dict[str, dict[str, str]]:
    """Parse an SSH config file and return a mapping of {host: {key: value}}."""
    config_map: dict[str, dict[str, str]] = {}
    current_hosts: list[str] = []
    current_config: dict[str, str] = {}

    def _flush() -> None:
        for h in current_hosts:
            config_map[h] = current_config

    try:
        with open(path) as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue

                if line.lower().startswith("host "):
                    _flush()
                    current_hosts = line[5:].split()
                    current_config = {}
                else:
                    parts = line.split(None, 1)
                    current_config[parts[0]] = parts[1] if len(parts) > 1 else ""

        _flush()
    except OSError as exc:
        config_map["error"] = str(exc)

    return config_map


# ---------------------------------------------------------------------------
# User discovery
# ---------------------------------------------------------------------------

def get_ssh_users() -> list[dict]:
    """Return info about system users (uid > 1000, login shell) with SSH configs."""
    users: list[dict] = []

    try:
        passwd_entries = pwd.getpwall()
    except Exception as exc:
        click.echo(f"Error reading passwd database: {exc}", err=True)
        return users

    for entry in passwd_entries:
        if entry.pw_uid <= 1000:
            continue
        shell = entry.pw_shell
        if any(s in shell for s in ("nologin", "false")):
            continue

        ssh_config_path = Path(entry.pw_dir) / ".ssh" / "config"
        config_map: dict[str, dict[str, str]] = {}
        hosts: list[str] = []

        if ssh_config_path.is_file():
            config_map = parse_ssh_config(ssh_config_path)
            hosts = [h for h in config_map if h != "error"]

        users.append(
            {
                "username": entry.pw_name,
                "uid": entry.pw_uid,
                "gid": entry.pw_gid,
                "home": entry.pw_dir,
                "hosts": hosts,
                "config_map": config_map,
            }
        )

    return users


def find_user(username: str, users: list[dict]) -> dict | None:
    return next((u for u in users if u["username"] == username), None)


# ---------------------------------------------------------------------------
# SSH config mutation
# ---------------------------------------------------------------------------

def remove_host_block(config_path: str | Path, server_name: str) -> tuple[bool, str | None]:
    """Remove all Host blocks that include *server_name* from the given config file."""
    config_path = Path(config_path)
    if not config_path.is_file():
        return False, f"Config file not found: {config_path}"

    try:
        lines = config_path.read_text().splitlines(keepends=True)
        new_lines: list[str] = []
        skip_block = False

        for line in lines:
            stripped = line.strip()
            if stripped.lower().startswith("host "):
                block_hosts = stripped[5:].split()
                skip_block = server_name in block_hosts
            if not skip_block:
                new_lines.append(line)

        config_path.write_text("".join(new_lines))
        return True, None
    except OSError as exc:
        return False, str(exc)


def append_host_block(config_path: Path, uid: int, gid: int, entry: str) -> None:
    """Append a Host block to *config_path*, creating the file if necessary."""
    config_path.parent.mkdir(mode=0o700, exist_ok=True)
    with open(config_path, "a") as f:
        f.write(entry)
    os.chown(config_path, uid, gid)
    os.chmod(config_path, 0o600)


# ---------------------------------------------------------------------------
# Remote provisioning helpers  (kept from original)
# ---------------------------------------------------------------------------

REMOTE_PROVISION_SCRIPT = """\
set -e
id -u kangaroo &>/dev/null || useradd -m -s /bin/bash kangaroo
getent group sudo >/dev/null && usermod -aG sudo kangaroo || usermod -aG wheel kangaroo 2>/dev/null

echo "kangaroo ALL=(ALL:ALL) NOPASSWD: ALL, !/usr/bin/rm, !/usr/sbin/reboot, !/usr/sbin/shutdown" > /etc/sudoers.d/kangaroo
chmod 755 /etc/sudoers.d
chmod 440 /etc/sudoers.d/kangaroo

if [ -d /usr/local/cpanel/whostmgr ]; then
    chmod 440 /etc/sudoers.d/48-wp-toolkit
fi

grep -q "sudo -i" /home/kangaroo/.bashrc || echo "exec sudo -i" >> /home/kangaroo/.bashrc
visudo -c
if [ $? -eq 0 ]; then
	:
else
	echo -e "Sudoers syntax error! Reverting..."
	rm /etc/sudoers.d/kangaroo
    exit 1
fi

mkdir -p /home/kangaroo/.ssh
cp ~/.ssh/authorized_keys /home/kangaroo/.ssh/authorized_keys
chown -R kangaroo:kangaroo /home/kangaroo/.ssh
chmod 700 /home/kangaroo/.ssh
chmod 600 /home/kangaroo/.ssh/authorized_keys

if [ -d /etc/ssh/sshd_config.d ]; then
	echo -e "##### 🦘 Kangaroo SSH JumpServer #####\nMatch User kangaroo\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/999-kangaroo.conf
else
	echo -e "##### 🦘 Kangaroo SSH JumpServer #####\nMatch User kangaroo\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi

systemctl restart sshd || systemctl restart ssh
"""


def ensure_kangaroo_key() -> Path:
    """Generate the shared kangaroo key pair if it does not exist yet."""
    if not KANGAROO_KEY.exists():
        click.echo("Generating SSH key...")
        subprocess.run(
            ["ssh-keygen", "-t", "rsa", "-b", "4096", "-f", str(KANGAROO_KEY), "-N", ""],
            check=True,
        )
    else:
        click.echo("Reusing existing SSH key.")
    return KANGAROO_KEY


def copy_key_to_remote(password: str, ssh_user: str, server_ip: str, port: int, public_key: Path) -> bool:
    subprocess.run(
        ["ssh-keygen", "-f", "/root/.ssh/known_hosts", "-R", server_ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    cmd = (
        f"sshpass -p '{password}' ssh-copy-id "
        f"-p {port} -o StrictHostKeyChecking=no "
        f"-i {public_key} {ssh_user}@{server_ip}"
    )
    result = subprocess.run(cmd, shell=True)
    return result.returncode == 0


def run_remote_provision(ssh_user: str, server_ip: str, port: int, private_key: Path) -> None:
    subprocess.run(
        [
            "ssh",
            "-p", str(port),
            "-o", "StrictHostKeyChecking=no",
            "-i", str(private_key),
            f"{ssh_user}@{server_ip}",
            REMOTE_PROVISION_SCRIPT,
        ],
        check=True,
    )


# ---------------------------------------------------------------------------
# Authentication prompt helper
# ---------------------------------------------------------------------------

def resolve_auth(password: str) -> tuple[bool, str]:
    """Return (use_password, password_value). Prompts if needed."""
    if password:
        return True, password

    click.echo("\nChoose authentication method:")
    click.echo("  1) Password")
    click.echo("  2) Manual SSH key installation")
    choice = click.prompt("Select option", type=click.IntRange(1, 2))
    if choice == 1:
        return True, click.prompt("Password", hide_input=True)
    return False, ""


# ---------------------------------------------------------------------------
# Shared helper: configure local users for a new server
# ---------------------------------------------------------------------------

def configure_users_for_server(
    name: str,
    ip: str,
    port: int,
    description: str,
    system_users: list[str],
    private_key: Path,
) -> None:
    """Write SSH config entries for each local user and copy the kangaroo key."""
    config_entry = (
        f"\n# Description: {description or 'none'}\n"
        f"Host {name}\n"
        f"    HostName {ip}\n"
        f"    User kangaroo\n"
        f"    Port {port}\n"
        f"    IdentityFile ~/.ssh/kangaroo_key_id_rsa\n"
    )

    for username in system_users:
        try:
            entry = pwd.getpwnam(username)
        except KeyError:
            click.echo(f"User '{username}' not found. Skipping.")
            continue

        home = Path(entry.pw_dir)
        key_dest = home / ".ssh" / "kangaroo_key_id_rsa"

        subprocess.run(["cp", str(private_key), str(key_dest)], check=True)
        os.chown(key_dest, entry.pw_uid, entry.pw_gid)
        os.chmod(key_dest, 0o600)

        append_host_block(
            home / ".ssh" / "config",
            entry.pw_uid,
            entry.pw_gid,
            config_entry,
        )
        click.echo(f"Configured SSH for user '{username}'.")

    # Persist server record
    with open(SERVERS_CONF, "a") as f:
        f.write(f"{name} {ip}\n")
    os.chmod(SERVERS_CONF, 0o600)


def all_system_users() -> list[str]:
    return [
        u.pw_name
        for u in pwd.getpwall()
        if u.pw_uid >= 1000
        and u.pw_shell.endswith(("bash", "sh", "zsh"))
        and u.pw_name != "root"
    ]


# ---------------------------------------------------------------------------
# Flask application (lazy import)
# ---------------------------------------------------------------------------

def build_flask_app(master_port: int) -> "Flask":  # noqa: F821  (type hint only)
    from flask import Flask, jsonify, request, send_file, abort
    import io
    import tempfile

    app = Flask(__name__)

    # ------------------------------------------------------------------ /key
    @app.route("/key")
    def route_key():
        pub = Path(f"{KANGAROO_KEY}.pub")
        if not pub.is_file():
            return jsonify({"error": "Key not generated yet. Run: kangaroo add-server first."}), 404
        return pub.read_text(), 200, {"Content-Type": "text/plain"}

    # ------------------------------------------------------------ /download
    @app.route("/download")
    def route_download():
        """Return the slave bootstrap script as a downloadable file."""
        expected_token = get_or_create_token()
        provided_token = request.args.get("token")
        if not provided_token or provided_token != expected_token:
            abort(403)  # Forbidden

        master_ip = request.host.split(":")[0]

        slave_script = _build_slave_script(master_ip, master_port, expected_token)
        buf = io.BytesIO(slave_script.encode())
        buf.seek(0)
        return send_file(
            buf,
            mimetype="text/x-sh",
            as_attachment=True,
            download_name="kangaroo_slave_setup.sh",
        )

    # ------------------------------------------------------------- /connect
    @app.route("/connect", methods=["POST"])
    def route_connect():
        """Called by slave after it has set itself up."""
        data = request.get_json(force=True, silent=True) or {}

        # Token validation
        token = get_or_create_token()
        if data.get("token") != token:
            return jsonify({"error": "Invalid token"}), 403

        name = data.get("hostname", "").strip()
        ip = data.get("ip", "").strip()
        ssh_port = int(data.get("ssh_port", 22))
        description = data.get("description", "")

        if not name or not ip:
            return jsonify({"error": "hostname and ip are required"}), 400

        private_key = ensure_kangaroo_key()
        target_users = "stefan,radovan,duka,filip,lazar,nikola,petar"
        users = [u.strip() for u in target_users.split(",")] #all_system_users()

        try:
            configure_users_for_server(name, ip, ssh_port, description, users, private_key)
        except Exception as exc:
            return jsonify({"error": str(exc)}), 500

        click.echo(f"\n🦘 Slave '{name}' ({ip}:{ssh_port}) registered and configured for all users.")
        return jsonify({"status": "ok", "server": name, "ip": ip, "port": ssh_port}), 200

    return app


def _build_slave_script(master_ip: str, master_port: int, token: str) -> str:
    """Generate the bash script that runs on the slave to self-register."""
    return f"""\
#!/usr/bin/env bash
# Kangaroo 🦘 Slave Setup Script
# Auto-generated — do not edit manually.
set -e

MASTER_IP="{master_ip}"
MASTER_PORT="{master_port}"
TOKEN="{token}"

echo "=== Kangaroo Slave Setup ==="

# ----------------------------------------------------------------
# 1. Detect identity
# ----------------------------------------------------------------
HOSTNAME_VAL=$(hostname)
IP_VAL=$(hostname -I | awk '{{print $1}}')
SSH_PORT=$(ss -tlnp | grep sshd | awk '{{print $4}}' | sed 's/.*://; q')
SSH_PORT=${{SSH_PORT:-22}}

echo "Hostname : $HOSTNAME_VAL"
echo "IP       : $IP_VAL"
echo "SSH port : $SSH_PORT"

# ----------------------------------------------------------------
# 2. Add master's public key to authorized_keys
# ----------------------------------------------------------------
echo "Fetching master public key..."
mkdir -p ~/.ssh
curl -fsSL "http://${{MASTER_IP}}:${{MASTER_PORT}}/key" >> ~/.ssh/authorized_keys
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "Public key added."

# ----------------------------------------------------------------
# 3. Provision kangaroo user
# ----------------------------------------------------------------
id -u kangaroo &>/dev/null || useradd -m -s /bin/bash kangaroo
getent group sudo >/dev/null && usermod -aG sudo kangaroo || usermod -aG wheel kangaroo 2>/dev/null

echo "kangaroo ALL=(ALL:ALL) NOPASSWD: ALL, !/usr/bin/rm, !/usr/sbin/reboot, !/usr/sbin/shutdown" > /etc/sudoers.d/kangaroo
chmod 755 /etc/sudoers.d
chmod 440 /etc/sudoers.d/kangaroo

if [ -d /usr/local/cpanel/whostmgr ]; then
    chmod 440 /etc/sudoers.d/48-wp-toolkit
fi

if [ -f /etc/hosts.allow ]; then
	echo -e "ALL : ${{MASTER_IP}} : allow" >> /etc/hosts.allow
fi


grep -q "sudo -i" /home/kangaroo/.bashrc || echo "exec sudo -i" >> /home/kangaroo/.bashrc
visudo -c
if [ $? -eq 0 ]; then
	echo "Successfully applied sudoers"
else
	echo "Sudoers syntax error! Reverting..."
	rm /etc/sudoers.d/kangaroo
    exit 1
fi

mkdir -p /home/kangaroo/.ssh
cp ~/.ssh/authorized_keys /home/kangaroo/.ssh/authorized_keys
chown -R kangaroo:kangaroo /home/kangaroo/.ssh
chmod 700 /home/kangaroo/.ssh
chmod 600 /home/kangaroo/.ssh/authorized_keys

if [ -d /etc/ssh/sshd_config.d ]; then
	echo -e "##### 🦘 Kangaroo SSH JumpServer #####\nMatch User kangaroo\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/999-kangaroo.conf
else
	echo -e "##### 🦘 Kangaroo SSH JumpServer #####\nMatch User kangaroo\n    PermitRootLogin yes\n    PasswordAuthentication yes\n    PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi

systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

if command -v csf >/dev/null 2>&1; then
	csf -a "${{MASTER_IP}}" "KangarooSSH JumpServer Master IP" > /dev/null 2>&1
fi

echo "kangaroo user provisioned."

# ----------------------------------------------------------------
# 4. Notify master
# ----------------------------------------------------------------
echo "Notifying master..."
curl -fsSL -X POST \\
     -H "Content-Type: application/json" \\
     -d "{{\\\"token\\\":\\\"$TOKEN\\\",\\\"hostname\\\":\\\"$HOSTNAME_VAL\\\",\\\"description\\\":\\\"$HOSTNAME_VAL\\\",\\\"ip\\\":\\\"$IP_VAL\\\",\\\"ssh_port\\\":$SSH_PORT}}" \\
     "http://${{MASTER_IP}}:${{MASTER_PORT}}/connect"

echo ""
echo "=== Done! This server has been registered with the Kangaroo master. ==="
"""


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

@click.group()
def cli() -> None:
    """Kangaroo SSH JumpServer 🦘"""
    require_root()


# ------------------------------------------------------------------ users

@cli.command("users")
def cmd_users() -> None:
    """List all SSH users."""
    for user in sorted(get_ssh_users(), key=lambda u: u["username"]):
        click.echo(f"User: {user['username']}")
        if user["hosts"]:
            click.echo("  Servers:")
            for host in sorted(user["hosts"]):
                click.echo(f"    - {host}")
        else:
            click.echo("  Servers: None")
        click.echo("")


# ----------------------------------------------------------------- servers

@cli.command("servers")
def cmd_servers() -> None:
    """List all hosts and how many users have access."""
    host_hostnames: dict[str, set[str]] = defaultdict(set)
    host_users: dict[str, set[str]] = defaultdict(set)

    for user in get_ssh_users():
        for host in user["hosts"]:
            hostname = user["config_map"].get(host, {}).get("HostName", "(no HostName)")
            host_hostnames[host].add(hostname)
            host_users[host].add(user["username"])

    click.echo("=== Servers ===\n")
    for host in sorted(host_hostnames):
        hostnames = ", ".join(sorted(host_hostnames[host]))
        count = len(host_users[host])
        click.echo(f"{host} ({count} user{'s' if count != 1 else ''}): {hostnames}")


# -------------------------------------------------------------------- user

@cli.command("user")
@click.argument("username")
def cmd_user(username: str) -> None:
    """Show SSH servers and config for USERNAME."""
    user = find_user(username, get_ssh_users())
    if not user:
        click.echo(f"User '{username}' not found or has no SSH config.")
        return

    click.echo(f"User: {username}")
    if not user["hosts"]:
        click.echo("  No SSH servers configured.")
        return

    for host in sorted(user["hosts"]):
        click.echo(f"  Server: {host}")
        config = user["config_map"].get(host, {})
        if "error" in config:
            click.echo(f"    [Error: {config['error']}]")
            continue
        for k, v in sorted(config.items()):
            click.echo(f"    {k}: {v}")
        click.echo("")


# ------------------------------------------------------------------ server

@cli.command("server")
@click.argument("server_name")
def cmd_server(server_name: str) -> None:
    """Show SSH config for SERVER_NAME across all users."""
    found = False
    for user in get_ssh_users():
        if server_name not in user["hosts"]:
            continue
        found = True
        click.echo(f"User: {user['username']}")
        config = user["config_map"].get(server_name, {})
        if "error" in config:
            click.echo(f"  [Error: {config['error']}]")
        else:
            for k, v in sorted(config.items()):
                click.echo(f"  {k}: {v}")
        click.echo("")

    if not found:
        click.echo(f"No users found with server '{server_name}'.")


# ---------------------------------------------------------- delete-server

@cli.command("delete-server")
@click.argument("username")
@click.argument("server_name")
def cmd_delete_server(username: str, server_name: str) -> None:
    """Delete SERVER_NAME from USERNAME's SSH config."""
    user = find_user(username, get_ssh_users())
    if not user:
        click.echo(f"User '{username}' not found or has no SSH config.")
        return

    config_path = Path(user["home"]) / ".ssh" / "config"
    if not config_path.is_file():
        click.echo(f"No SSH config file found for '{username}'.")
        return

    ok, err = remove_host_block(config_path, server_name)
    if ok:
        click.echo(f"Removed '{server_name}' from '{username}' SSH config.")
    else:
        click.echo(f"Failed: {err}")


# ------------------------------------------------------ delete-server-all

@cli.command("delete-server-all")
@click.argument("server_name")
def cmd_delete_server_all(server_name: str) -> None:
    """Delete SERVER_NAME from all users' SSH configs."""
    removed_any = False
    for user in get_ssh_users():
        config_path = Path(user["home"]) / ".ssh" / "config"
        if not config_path.is_file():
            continue
        ok, err = remove_host_block(config_path, server_name)
        if ok:
            click.echo(f"Removed '{server_name}' from '{user['username']}'.")
            removed_any = True
        else:
            click.echo(f"Failed for '{user['username']}': {err}")

    if not removed_any:
        click.echo(f"No SSH config entries found for '{server_name}'.")


# ------------------------------------------------------------ add-server

@cli.command("add-server")
@click.option("--name", required=True, help="Server alias (e.g. webserver1)")
@click.option("--ip", default="", help="Server IP address")
@click.option("--user", "ssh_user", default="root", help="SSH username")
@click.option("--port", default=22, type=int, show_default=True, help="SSH port")
@click.option("--password", default="", help="SSH password")
@click.option("--description", default="", help="Human-readable description")
@click.option("--users", "target_users", default="", help="Comma-separated usernames (or 'all')")
def cmd_add_server(
    name: str,
    ip: str,
    ssh_user: str,
    port: int,
    password: str,
    description: str,
    target_users: str,
) -> None:
    """Add a new server and configure SSH access for users."""
    # Resolve IP
    if not ip:
        try:
            ip = socket.gethostbyname(name)
            click.echo(f"Resolved {name} -> {ip}")
        except socket.gaierror:
            ip = click.prompt("IP Address")

    # Auth
    use_password, password = resolve_auth(password)

    # Key pair
    private_key = ensure_kangaroo_key()
    public_key = Path(f"{private_key}.pub")

    # Deploy key
    if use_password:
        if not copy_key_to_remote(password, ssh_user, ip, port, public_key):
            click.echo("Failed to copy SSH key.")
            return
        click.echo("SSH key copied successfully.")
    else:
        click.echo("\nAdd this key to remote authorized_keys:\n")
        click.echo(public_key.read_text())
        input("Press ENTER when done...")

    # Remote provisioning
    run_remote_provision(ssh_user, ip, port, private_key)
    click.echo("Remote configuration complete.")

    # Resolve local users to configure
    if not target_users:
        if click.confirm("Setup SSH for all existing users?"):
            target_users = "all"
        else:
            target_users = click.prompt("Enter usernames (comma-separated)")

    system_users = all_system_users() if target_users == "all" else [u.strip() for u in target_users.split(",")]

    configure_users_for_server(name, ip, port, description, system_users, private_key)

    click.echo(f"\nServer {name} ({ip}:{port}) added successfully 🦘")


# --------------------------------------------------------------- connect

def is_port_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex((host, port)) == 0

import time

def start_master_api_subprocess(port: int) -> None:
    cmd = [
        sys.executable,
        str(Path(__file__).resolve()),
        "master-api",
        "--port",
        str(port),
    ]

    subprocess.Popen(cmd, start_new_session=True)

    for _ in range(20):
        if is_port_open("127.0.0.1", port):
            return
        time.sleep(0.25)

    click.echo("Failed to start Master API.", err=True)

@cli.command("connect")
@click.option("--port", default=DEFAULT_MASTER_PORT, show_default=True, help="Port the master API listens on")
@click.option("--ip", default="", help="Override the master IP shown in the command (auto-detected if omitted)")
def cmd_connect(port: int, ip: str) -> None:
    """Show the one-liner command to run on a slave to self-register with this master."""
    ensure_kangaroo_key()
    token = get_or_create_token()

    if not is_port_open("127.0.0.1", port):
        click.echo("🦘 Master API not running. Starting in background...")
        start_master_api_subprocess(port)
    else:
        click.echo("🦘 Master API already running.")

    # Detect IP if not provided
    if not ip:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
        except Exception:
            ip = "<MASTER_IP>"

    click.echo("\n🦘 Kangaroo — Slave Registration\n")
    click.echo("Run this command on the slave machine:\n")
    click.echo(
        f"  curl -fsSL http://{ip}:{port}/download?token={token} | bash\n"
    )


# ----------------------------------------------------------- master-api

@cli.command("master-api")
@click.option("--port", default=DEFAULT_MASTER_PORT, show_default=True, help="Port to listen on")
@click.option("--host", default="0.0.0.0", show_default=True, help="Bind address")
def cmd_master_api(port: int, host: str) -> None:
    """Start the master HTTP API (key distribution + slave registration)."""
    try:
        from flask import Flask  # noqa: F401
    except ImportError:
        click.echo("Flask is required: pip install flask", err=True)
        raise SystemExit(1)

    ensure_kangaroo_key()
    token = get_or_create_token()

    click.echo(f"\n🦘 Kangaroo Master API starting on {host}:{port}")
    click.echo(f"   Token : {token}")
    click.echo(f"   Endpoints:")
    click.echo(f"     GET  /key       — public key")
    click.echo(f"     GET  /download  — slave setup script")
    click.echo(f"     POST /connect   — slave registration\n")

    app = build_flask_app(port)
    app.run(host=host, port=port, debug=False)


# ---------------------------------------------------------- login-logs

@cli.command("login-logs")
@click.option("--head", "use_head", is_flag=True, help="Show first lines instead of last")
@click.option("--lines", default=10, show_default=True, help="Number of lines")
@click.option("--follow", is_flag=True, help="Follow log output (like tail -f)")
@click.option("--search", default="", help="Filter by username, IP, or action")
def cmd_login_logs(use_head: bool, lines: int, follow: bool, search: str) -> None:
    """Show SSH login logs."""
    log_path = SCRIPT_DIR / "server" / "logs" / "ssh_login.log"

    if not log_path.is_file():
        click.echo("No logs yet.")
        return

    if use_head and follow:
        click.echo("Cannot use --head and --follow together.", err=True)
        return

    if use_head:
        cmd = ["head", f"-n{lines}", str(log_path)]
    else:
        cmd = ["tail", f"-n{lines}"]
        if follow:
            cmd.append("-f")
        cmd.append(str(log_path))

    try:
        with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as proc:
            for line in proc.stdout:
                if not search or search in line:
                    click.echo(line, nl=False)
            proc.wait()
            if proc.returncode != 0:
                click.echo(f"Error reading log: {proc.stderr.read()}", err=True)
    except OSError as exc:
        click.echo(f"Failed to read log file: {exc}", err=True)


if __name__ == "__main__":
    cli(prog_name="kangaroo")
