# Kangaroo SSH JumpServer 🦘

A lightweight, open-source SSH Jumpserver for internal management.

<details>
  <summary><b>TL;DR</b></summary>
  <p>Restricts shells on both the Master and the Slave nodes to ensure non-root users can only perform "jump" actions from Master to Slaves.</p>
</details>

How it works:

1. **Install on Master:** Run the installation script to restrict all non-root users to the [server/client.sh](https://github.com/stefanpejcic/kangaroo/blob/main/server/client.sh) menu interface.
2. **Add Users:** [Create standard Linux system users](https://www.google.com/search?q=linux+create+user) on the Master node.
3. **Link Slaves:** Use `kangaroo add-server` to register remote servers. This automatically creates a new account on the Slave and configures it to forward syslog to the master.

that's it! Users now simply SSH into the **Master**, where they are greeted by the fzf menu where they can view authorized servers and "jump" to them instantly.

---

## Install


<table>
  <tr>
    <th>Docker</th>
    <th>Standalone (Ubuntu 24)</th>
  </tr>
  <tr>
    <td>
      
```bash
docker run -d \
  --name kangaroo \
  -p 2222:22 \
  -p 514:514/udp \
  -p 514:514/tcp \
  -v kangaroo_logs:/var/log/remote \
  kangaroo:latest
```

</td>
<td>
  
```bash
cd /home && \
  git clone https://github.com/stefanpejcic/kangaroo/ && \
  cd kangaroo && bash install.sh
```

</td></tr>
</table>


---

## Usage

```
# kangaroo 
Usage: kangaroo [OPTIONS] COMMAND [ARGS]...

  Kangaroo SSH JumpServer 🦘

Options:
  --help  Show this message and exit.

Commands:
  add-server         Add a new server and assign it to users.
  delete-server      Delete SERVER from USERNAME's SSH config file.
  delete-server-all  Delete SERVER from all users' SSH config files.
  login-logs         Show ssh login logs.
  server             Show SSH config for SERVER from all users.
  servers            List all hosts and number of users who have access.
  user               Show SSH servers and configs for a specific USERNAME.
  users              List all SSH Users.
```


### Manage Users

- List all users:
  ```bash
  kangaroo users
  ```

- View specific user:
  ```bash
  kangaroo user [USERNAME]
  ```

### Manage Servers

- List all unique servers:
  ```bash
  kangaroo servers
  ```

- View server information:
  ```bash
  kangaroo server [SERVER_NAME]
  ```

- Add a server:
  ```bash
  kangaroo add-server --name "web-prod" --ip "192.168.1.10" --user "admin" --users "bob,alice"
  ```
  | Argument | Example Value | Role in SSH Config | Description |
  | --- | --- | --- | --- |
  | **`--name`** | `web-prod` | `Host web-prod` | The shorthand alias you type to connect (e.g., `ssh web-prod`). |
  | **`--ip`** | `192.168.1.10` | `HostName 192.168.1.10` | The actual IP address or domain of the remote server. |
  | **`--user`** | `admin` | `User admin` | The remote username used to log in to the destination (mostly `root`). |
  | **`--users`** | `bob,alice` | *File Path Target* | The specific system users on this machine whose SSH configs will be modified. |
  | **`--port`** | `22` | `Port 22` | (Optional) The port the remote SSH service is listening on. |
  | **`--description`** | `Prod Server` | `# Description` | (Optional) Adds a comment line above the config block for organization. |
  | **`--password`** | `********` | *N/A* | (Optional) Used by the setup script for initial automation (not stored in config). |

- Remove server from a specific user:
  ```bash
  kangaroo delete-server [USERNAME] [SERVER_NAME]
  ```

- Remove server from **ALL** users:
  ```bash
  kangaroo delete-server-all [SERVER_NAME]
  ```

### Logs

View SSH login logs:

- Default (last 10 lines): `kangaroo login-logs`
- Search logs: `kangaroo login-logs --search IP/username/action`
- Follow logs in real-time: `kangaroo login-logs --follow`
- View first 20 lines: `kangaroo login-logs --head --lines 20`


### Screen Recordings
- List all recordings: `journalctl -t tlog-rec-session`
- List for today only: `journalctl -t tlog-rec-session --since today`
- List recordings for user 'stefan': `journalctl _UID=$(id -u stefan) -t tlog-rec-session`
- View a recording ID: '814b22f52288410f9e1801d123f75aac-cc1-7c18': `tlog-play --reader=journal -M "TLOG_REC=814b22f52288410f9e1801d123f75aac-cc1-7c18"`

----

## Todo

- [ ] [2FA](https://www.digitalocean.com/community/tutorials/how-to-set-up-multi-factor-authentication-for-ssh-on-ubuntu-20-04#step-1-installing-google-s-pam)
- [ ] 

## Uninstall

```
bash kangaroo/uninstall.sh
```
