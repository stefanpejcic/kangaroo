# Kangaroo SSH JumpServer 🦘
Open source SSH jumpserver - **not** for production use.

it will:

- from master copy ssh key to slave server and on it restrict users to `behind-jumserver/restricted_command.sh` script.
- on master restrict user to `fzf` and allow them access to selected servers only.

User connects to MASTER then selects a slave server to jump to

## Requirements

Currently only Ubuntu is supported.

## Install

```
git clone https://github.com/stefanpejcic/kangaroo/ && bash kangaroo/install.sh
```


## Usage
```
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



## Todo

- [ ] [2FA](https://www.digitalocean.com/community/tutorials/how-to-set-up-multi-factor-authentication-for-ssh-on-ubuntu-20-04#step-1-installing-google-s-pam)
- [ ] 

## Uninstall
```
bash kangaroo/uninstall.sh
```
