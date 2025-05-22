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

- `bash  server/add_server.sh --description="new slave server for testing" --name="slave1" --ip=185.119.XX.XX --password="rnj4vZ9Czeg0VWp" --user=all` or interactive: `bash server/add_server.sh`





## Uninstall
```
bash kangaroo/uninstall.sh
```
