#!/usr/bin/env python3
import os
from collections import defaultdict
import subprocess
import click
import socket
import pwd
import grp
from pathlib import Path


if os.geteuid() != 0:
    click.echo("Run as root")
    return


def parse_ssh_config(path):
    config_map = {}
    current_hosts = []
    current_config = {}

    try:
        with open(path, 'r') as f:
            for line in f:
                line = line.rstrip('\n')
                stripped = line.strip()
                if not stripped or stripped.startswith('#'):
                    continue

                if stripped.lower().startswith('host '):
                    if current_hosts:
                        for h in current_hosts:
                            config_map[h] = current_config
                    current_hosts = stripped[5:].strip().split()
                    current_config = {}
                else:
                    if ' ' in stripped:
                        key, val = stripped.split(None, 1)
                        current_config[key] = val
                    else:
                        current_config[stripped] = ""
            if current_hosts:
                for h in current_hosts:
                    config_map[h] = current_config

    except Exception as e:
        config_map['error'] = str(e)

    return config_map

def get_ssh_users_info():
    users_info = []

    try:
        with open('/etc/passwd', 'r') as f:
            for line in f:
                parts = line.strip().split(':')
                if len(parts) >= 7:
                    username = parts[0]
                    uid = int(parts[2])
                    home_dir = parts[5]
                    shell = parts[6]

                    if uid > 1000 and not any(s in shell for s in ['nologin', 'false']):
                        ssh_config_path = os.path.join(home_dir, '.ssh', 'config')
                        hosts = []
                        config_map = {}

                        if os.path.isfile(ssh_config_path):
                            config_map = parse_ssh_config(ssh_config_path)
                            hosts = [h for h in config_map if h != 'error']

                        users_info.append({
                            'username': username,
                            'home': home_dir,
                            'hosts': hosts,
                            'config_map': config_map
                        })
    except Exception as e:
        click.echo(f"Error reading /etc/passwd: {e}", err=True)

    return users_info

@click.group()
def cli():
    """Kangaroo SSH JumpServer 🦘"""
    pass

@cli.command()
def users():
    """List all SSH Users."""
    users_info = get_ssh_users_info()
    click.echo("=== Users ===\n")
    for user in sorted(users_info, key=lambda u: u['username']):
        click.echo(f"User: {user['username']}")
        if user['hosts']:
            click.echo("  Servers:")
            for host in sorted(user['hosts']):
                click.echo(f"    - {host}")
        else:
            click.echo("  Servers: None")
        click.echo("")


@cli.command()
def servers():
    """List all hosts and number of users who have access."""
    users_info = get_ssh_users_info()
    host_to_hostnames = defaultdict(set)
    host_to_users = defaultdict(set)

    # Collect HostName values and users per host
    for user in users_info:
        for host in user['hosts']:
            config = user['config_map'].get(host, {})
            hostname_val = config.get('HostName', '(no HostName)')
            host_to_hostnames[host].add(hostname_val)
            host_to_users[host].add(user['username'])

    click.echo("=== Servers ===\n")
    for host in sorted(host_to_hostnames.keys()):
        hostnames = ', '.join(sorted(host_to_hostnames[host]))
        user_count = len(host_to_users[host])
        click.echo(f"{host} ({user_count} user{'s' if user_count != 1 else ''}): {hostnames}")




@cli.command()
@click.argument('username')
def user(username):
    """Show SSH servers and configs for a specific USERNAME."""
    users_info = get_ssh_users_info()
    user = next((u for u in users_info if u['username'] == username), None)
    if not user:
        click.echo(f"User '{username}' not found or has no SSH config.")
        return

    click.echo(f"User: {username}")
    if not user['hosts']:
        click.echo("  No SSH servers configured.")
        return

    for host in sorted(user['hosts']):
        click.echo(f"  Server: {host}")
        config = user['config_map'].get(host, {})
        if 'error' in config:
            click.echo(f"    [Error parsing config: {config['error']}]")
            continue
        for k, v in sorted(config.items()):
            click.echo(f"    {k}: {v}")
        click.echo("")


@cli.command()
@click.argument('server')
def server(server):
    """Show SSH config for SERVER from all users."""
    users_info = get_ssh_users_info()

    found = False
    for user in users_info:
        if server in user['hosts']:
            found = True
            click.echo(f"User: {user['username']}")
            config = user['config_map'].get(server, {})
            if 'error' in config:
                click.echo(f"  [Error parsing config: {config['error']}]")
                continue
            for k, v in sorted(config.items()):
                click.echo(f"  {k}: {v}")
            click.echo("")

    if not found:
        click.echo(f"No users found with server '{server}'.")





def remove_host_from_ssh_config(config_path, server_name):
    """Remove all Host blocks containing server_name from SSH config file."""
    if not os.path.isfile(config_path):
        return False, f"Config file not found: {config_path}"

    try:
        with open(config_path, 'r') as f:
            lines = f.readlines()

        new_lines = []
        inside_block = False
        block_hosts = []
        skip_block = False

        for line in lines:
            stripped = line.strip()
            if stripped.lower().startswith('host '):
                # Before starting new block, decide if we skip previous block lines
                inside_block = True
                # parse hosts from this line
                block_hosts = stripped[5:].strip().split()
                # skip block if server_name in hosts list
                skip_block = server_name in block_hosts
                if not skip_block:
                    new_lines.append(line)
            else:
                if inside_block:
                    if skip_block:
                        # skip this line (part of block to delete)
                        continue
                    else:
                        new_lines.append(line)
                else:
                    # lines before first Host block or after last block
                    new_lines.append(line)

        with open(config_path, 'w') as f:
            f.writelines(new_lines)

        return True, None

    except Exception as e:
        return False, str(e)







@cli.command()
@click.argument('username')
@click.argument('server')
def delete_server(username, server):
    """Delete SERVER from USERNAME's SSH config file."""
    users_info = get_ssh_users_info()
    user = next((u for u in users_info if u['username'] == username), None)
    if not user:
        click.echo(f"User '{username}' not found or has no SSH config.")
        return

    ssh_config_path = os.path.join(user['home'], '.ssh', 'config')
    if not os.path.isfile(ssh_config_path):
        click.echo(f"No SSH config file found for user '{username}'.")
        return

    success, error = remove_host_from_ssh_config(ssh_config_path, server)
    if success:
        click.echo(f"Server '{server}' removed from user '{username}' SSH config.")
    else:
        click.echo(f"Failed to remove server: {error}")



@cli.command()
@click.argument('server')
def delete_server_all(server):
    """Delete SERVER from all users' SSH config files."""
    users_info = get_ssh_users_info()
    any_removed = False

    for user in users_info:
        ssh_config_path = os.path.join(user['home'], '.ssh', 'config')
        if os.path.isfile(ssh_config_path):
            success, error = remove_host_from_ssh_config(ssh_config_path, server)
            if success:
                click.echo(f"Removed server '{server}' from user '{user['username']}'.")
                any_removed = True
            else:
                click.echo(f"Failed to remove server from user '{user['username']}': {error}")

    if not any_removed:
        click.echo(f"No SSH config entries found for server '{server}' in any user.")





@cli.command()
@click.option('--description', default='', help='Server description')
@click.option('--name', required=True, help='Server name (e.g., webserver1)')
@click.option('--ip', default='', help='Server IP address')
@click.option('--user', default='root', help='SSH username for the new server')
@click.option('--port', default=22, type=int, help='SSH port for the new server')
@click.option('--password', default='', help='SSH password')
@click.option('--users', default='', help='Comma-separated list of users to add server for')
def add_server(description, name, ip, user, port, password, users):
    """Add a new server and configure SSH access."""

    script_dir = os.path.dirname(os.path.realpath(__file__))
    config_file = os.path.join(script_dir, "jump_servers.conf")

    # 1. click already handles validation
    server_name = name
    server_ip = ip
    ssh_user = user or "root"
    ssh_port = port
    server_description = description or "none"

    if not server_ip:
        try:
            server_ip = socket.gethostbyname(server_name)
            click.echo(f"Resolved {server_name} -> {server_ip}")
        except Exception:
            server_ip = click.prompt("IP Address")

    # 2. pass auth section
    use_password = True
    USERPASS = password

    if not USERPASS:
        click.echo("\nChoose authentication method:")
        click.echo("1) Provide password")
        click.echo("2) Manual SSH key installation")

        auth_choice = click.prompt("Select option", type=int)

        if auth_choice == 1:
            USERPASS = click.prompt("Enter password", hide_input=True)
            use_password = True
        elif auth_choice == 2:
            use_password = False
        else:
            click.echo("Invalid option.")
            return

    # 3. generate SSH key pair
    private_key = f"/etc/ssh/kangaroo_key_id_rsa"
    public_key = f"{private_key}.pub"

    if not os.path.exists(private_key):
        click.echo("Generating SSH key...")
        subprocess.run([
            "ssh-keygen", "-t", "rsa", "-b", "4096",
            "-f", private_key, "-N", ""
        ], check=True)
    else:
        click.echo("Reusing existing SSH key.")

    # 4. copy key to remote
    if use_password:
        subprocess.run([
            "ssh-keygen", "-f", "/root/.ssh/known_hosts",
            "-R", server_ip
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        copy_cmd = (
            f"sshpass -p '{USERPASS}' ssh-copy-id "
            f"-p {ssh_port} -o StrictHostKeyChecking=no "
            f"-i {public_key} {ssh_user}@{server_ip}"
        )

        result = subprocess.run(copy_cmd, shell=True)
        if result.returncode != 0:
            click.echo("Failed to copy SSH key.")
            return
        click.echo("SSH key copied successfully.")
    else:
        click.echo("\nAdd this key to remote authorized_keys:\n")
        with open(public_key) as f:
            click.echo(f.read())
        input("Press ENTER when done...")

    # 5. remote provisioning
    remote_script = f"""
set -e
id -u kangaroo &>/dev/null || useradd -m -s /bin/bash kangaroo
getent group sudo >/dev/null && usermod -aG sudo kangaroo || usermod -aG wheel kangaroo 2>/dev/null

echo "kangaroo ALL=(ALL:ALL) NOPASSWD: ALL, !/usr/bin/rm, !/usr/sbin/reboot, !/usr/sbin/shutdown" > /etc/sudoers.d/kangaroo
chmod 440 /etc/sudoers.d/kangaroo

mkdir -p /home/kangaroo/.ssh
cp ~/.ssh/authorized_keys /home/kangaroo/.ssh/authorized_keys
chown -R kangaroo:kangaroo /home/kangaroo/.ssh
chmod 700 /home/kangaroo/.ssh
chmod 600 /home/kangaroo/.ssh/authorized_keys

systemctl restart sshd || systemctl restart ssh
"""

    subprocess.run([
        "ssh",
        "-p", str(ssh_port),
        "-o", "StrictHostKeyChecking=no",
        "-i", private_key,
        f"{ssh_user}@{server_ip}",
        remote_script
    ], check=True)

    click.echo("Remote configuration complete.")

    # 6. setup local users SSH config
    if not users:
        if click.confirm("Setup SSH for all existing users?"):
            users = "all"
        else:
            users = click.prompt("Enter usernames (comma-separated)")

    if users == "all":
        system_users = [
            u.pw_name for u in pwd.getpwall()
            if u.pw_uid >= 1000 and u.pw_shell.endswith(("bash", "sh", "zsh"))
            and u.pw_name != "root"
        ]
    else:
        system_users = [u.strip() for u in users.split(",")]

    for username in system_users:
        try:
            user_info = pwd.getpwnam(username)
        except KeyError:
            click.echo(f"User {username} not found. Skipping.")
            continue

        home = Path(user_info.pw_dir)
        ssh_dir = home / ".ssh"
        ssh_dir.mkdir(mode=0o700, exist_ok=True)

        key_dest = ssh_dir / "kangaroo_key_id_rsa"
        subprocess.run(["cp", private_key, str(key_dest)])
        os.chown(key_dest, user_info.pw_uid, user_info.pw_gid)
        os.chmod(key_dest, 0o600)

        config_file_user = ssh_dir / "config"
        config_entry = f"""
# Description: {server_description}
Host {server_name}
    HostName {server_ip}
    User kangaroo
    Port {ssh_port}
    IdentityFile ~/.ssh/kangaroo_key_id_rsa
"""

        with open(config_file_user, "a+") as f:
            f.write(config_entry)

        os.chown(config_file_user, user_info.pw_uid, user_info.pw_gid)
        os.chmod(config_file_user, 0o600)

        click.echo(f"Configured SSH for user {username}")

    # 7. Save server to config
    with open(config_file, "a") as f:
        f.write(f"{server_name} {server_ip}\n")

    os.chmod(config_file, 0o600)

    click.echo(
        f"\nServer {server_name} ({server_ip}:{ssh_port}) added successfully 🦘"
    )



@cli.command()
@click.option('--head', is_flag=True, help='Show first lines instead of last')
@click.option('--lines', default=10, show_default=True, help='Number of lines to show')
@click.option('--follow', is_flag=True, help='Follow the log file (like tail -f)')
@click.option('--search', help='Filter logs by username, IP or action')
def login_logs(head, lines, follow, search):
    """
    Show ssh login logs.
    """
    log_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'server', 'logs', 'ssh_login.log')

    if not os.path.isfile(log_path):
        click.echo("No logs yet.")
        return

    if follow and head:
        click.echo("Cannot use --head and --follow together.")
        return

    cmd = []

    if head:
        cmd = ['head', f'-n{lines}', log_path]
    else:
        cmd = ['tail', f'-n{lines}']
        if follow:
            cmd.append('-f')
        cmd.append(log_path)

    try:
        with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as proc:
            for line in proc.stdout:
                if search:
                    if search in line:
                        click.echo(line, nl=False)
                else:
                    click.echo(line, nl=False)
            proc.wait()
            if proc.returncode != 0:
                err = proc.stderr.read()
                click.echo(f"Error reading log: {err}", err=True)
    except Exception as e:
        click.echo(f"Failed to read log file: {e}")


if __name__ == "__main__":
    cli(prog_name="kangaroo")
