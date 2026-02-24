#!/usr/bin/env python3
import os
from collections import defaultdict
import click

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




import subprocess

@cli.command()
@click.option('--description', default='', help='Server description')
@click.option('--name', required=True, help='Server name (e.g., webserver1)')
@click.option('--ip', required=True, help='Server IP address')
@click.option('--user', default='root', help='SSH username for the new server')
@click.option('--port', default=22, type=int, help='SSH port for the new server')
@click.option('--password', default='', help='SSH password')
@click.option('--users', default='', help='Comma-separated list of users to add server for')
def add_server(description, name, ip, user, port, password, users):
    """Add a new server and assign it to users."""
    script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'server', 'add_server.sh')
    
    if not os.path.isfile(script_path):
        click.echo(f"Error: Script {script_path} not found.")
        return

    args = [
        script_path,
        f'--description={description}' if description else '',
        f'--name={name}',
        f'--ip={ip}',
        f'--user={user}',
        f'--port={port}',
        f'--password={password}' if password else '',
        f'--users={users}' if users else '',
    ]
    # Filter out empty strings
    args = [arg for arg in args if arg]

    try:
        # Run script with inherited stdin/stdout so user can interact if prompts appear
        result = subprocess.run(args, check=False)
        if result.returncode != 0:
            click.echo(f"Script exited with code {result.returncode}")
    except Exception as e:
        click.echo(f"Failed to run script: {e}")




@cli.command()
@click.option('--head', is_flag=True, help='Show first lines instead of last')
@click.option('--lines', default=10, show_default=True, help='Number of lines to show')
@click.option('--follow', is_flag=True, help='Follow the log file (like tail -f)')
def login_logs(head, lines, follow):
    """
    Show ssh login logs.
    """
    log_path = './server/logs/ssh_login.log'

    if not os.path.isfile(log_path):
        click.echo(f"No logs yet.")
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
                click.echo(line, nl=False)
            proc.wait()
            if proc.returncode != 0:
                err = proc.stderr.read()
                click.echo(f"Error reading log: {err}", err=True)
    except Exception as e:
        click.echo(f"Failed to read log file: {e}")


if __name__ == "__main__":
    cli(prog_name="kangaroo")
